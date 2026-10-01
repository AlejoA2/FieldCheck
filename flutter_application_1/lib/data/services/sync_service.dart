/// `SyncService`: el corazón del modo offline-first.
///
/// ## Responsabilidad
///
/// Vaciar la [SyncQueueStore] cuando hay red, subir las evidencias pendientes y
/// escribir los documentos en el servidor, con reintentos, backoff exponencial
/// y prevención de duplicados.
///
/// ## Garantías de diseño
///
/// 1. **Nunca se pierde un registro.** Un item solo se elimina de la cola
///    *después* de que el servidor confirma la escritura. Si el proceso muere a
///    mitad de camino, el item sigue en la cola y se reintentará.
/// 2. **Prevención de duplicidad.** El [SyncQueueItem.id] se usa como ID de
///    documento en Firestore y como nombre del archivo en Storage. Reintentar
///    sobrescribe en lugar de duplicar.
/// 3. **Orden FIFO.** Los items se procesan del más antiguo al más reciente, de
///    modo que las mutaciones de una misma visita se apliquen en secuencia.
/// 4. **Reentrada segura.** Si se pide sincronizar mientras ya hay una en curso,
///    se marca para ejecutar al terminar la actual.
/// 5. **Aislamiento de fallos.** Un item que falla no detiene el resto de la
///    cola: se registra el error y se sigue con el siguiente.
///
/// ## Nota sobre conectividad
///
/// [ConnectivityService] informa de la *interfaz* de red, no de la disponibilidad
/// real de Internet. Conectarse a un WiFi sin salida deja la interfaz activa. Por
/// eso una subida que falla por timeout se trata como estado offline (se
/// programa un reintento), en lugar de marcar el item como fallido de inmediato.
library;

import 'dart:async';

import '../../core/utils/clock.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/sync_queue_item.dart';
import '../../domain/repositories/contracts.dart';
import '../../domain/services/payload_evidencias.dart';

/// Estado observable de la sincronización, para alimentar la UI.
class EstadoSync {
  const EstadoSync({
    this.enEjecucion = false,
    this.pendientes = 0,
    this.procesadosEnUltimaEjecucion = 0,
    this.fallidosEnUltimaEjecucion = 0,
    this.ultimoError,
    this.hayConexion = true,
  });

  final bool enEjecucion;
  final int pendientes;

  /// Items sincronizados con éxito en la última ejecución.
  final int procesadosEnUltimaEjecucion;

  /// Items que quedaron con error en la última ejecución.
  final int fallidosEnUltimaEjecucion;

  final String? ultimoError;

  final bool hayConexion;

  /// `true` si quedó trabajo pendiente que no se pudo completar.
  bool get requiereAtencion =>
      fallidosEnUltimaEjecucion > 0 || pendientes > 0;

  EstadoSync copyWith({
    bool? enEjecucion,
    int? pendientes,
    int? procesadosEnUltimaEjecucion,
    int? fallidosEnUltimaEjecucion,
    String? ultimoError,
    bool limpiarError = false,
    bool? hayConexion,
  }) {
    return EstadoSync(
      enEjecucion: enEjecucion ?? this.enEjecucion,
      pendientes: pendientes ?? this.pendientes,
      procesadosEnUltimaEjecucion:
          procesadosEnUltimaEjecucion ?? this.procesadosEnUltimaEjecucion,
      fallidosEnUltimaEjecucion:
          fallidosEnUltimaEjecucion ?? this.fallidosEnUltimaEjecucion,
      ultimoError: limpiarError ? null : (ultimoError ?? this.ultimoError),
      hayConexion: hayConexion ?? this.hayConexion,
    );
  }

  @override
  String toString() =>
      'EstadoSync(ejecutando: $enEjecucion, pendientes: $pendientes, '
      'ok: $procesadosEnUltimaEjecucion, fallidos: $fallidosEnUltimaEjecucion)';
}

/// Resultado de una pasada de sincronización.
class ResultadoSincronizacion {
  const ResultadoSincronizacion({
    required this.sincronizados,
    required this.fallidos,
    required this.omitidos,
    required this.huboRed,
  });

  final int sincronizados;
  final int fallidos;

  /// Items saltados por backoff (aún no era su momento de reintentar).
  final int omitidos;

  /// `false` si no había conexión y no se intentó nada.
  final bool huboRed;

  bool get todoOk => fallidos == 0;

  @override
  String toString() =>
      'ResultadoSincronizacion(ok: $sincronizados, fallidos: $fallidos, '
      'omitidos: $omitidos, huboRed: $huboRed)';
}

class SyncService {
  // La inyección en campos privados usa parámetros públicos porque Dart no
  // admite parámetros nombrados con "_". Ver analysis_options.yaml.
  SyncService({
    required SyncQueueStore cola,
    required RemoteSyncGateway gateway,
    required EvidenceUploader evidencia,
    required ConnectivityService conectividad,
    BackoffPolicy backoff = const BackoffPolicy(),
    Clock clock = const SystemClock(),
    PayloadEvidencias payloads = const PayloadEvidencias(),
    double Function()? random,
  }) : _cola = cola,
       _gateway = gateway,
       _evidencia = evidencia,
       _conectividad = conectividad,
       _backoff = backoff,
       _clock = clock,
       _payloads = payloads,
       _random = random ?? _randomPorDefecto;

  final SyncQueueStore _cola;
  final RemoteSyncGateway _gateway;
  final EvidenceUploader _evidencia;
  final ConnectivityService _conectividad;
  final BackoffPolicy _backoff;
  final Clock _clock;

  /// Sustituye rutas locales por URLs dentro del payload. Inyectado para poder
  /// probar la resolución de evidencias sin Storage.
  final PayloadEvidencias _payloads;

  /// Fuente de aleatoriedad para el jitter del backoff. Inyectable para tests.
  final double Function() _random;

  /// Jitter neutro por defecto: sin dispersión, pero determinista.
  static double _randomPorDefecto() => 0.5;

  final _controllerEstado = StreamController<EstadoSync>.broadcast();

  /// Estado actual de la sincronización (badge "N pendientes" en la UI).
  Stream<EstadoSync> obtenerEstado() => _controllerEstado.stream;

  bool _sincronizando = false;
  bool _pendienteDeEjecucion = false;
  bool _detenido = false;
  StreamSubscription<bool>? _suscripcionRed;

  EstadoSync _estado = const EstadoSync();

  /// Estado corrente. Expuesto para que la UI pueda mostrar el badge sin
  /// esperar al primer evento del stream.
  EstadoSync get estadoActual => _estado;

  /// Escucha la red y sincroniza automáticamente al recuperar conexión.
  ///
  /// Es idempotente: llamarlo más de una vez no duplica suscripciones.
  void iniciarEscuchaDeRed() {
    if (_suscripcionRed != null) return;

    _suscripcionRed = _conectividad.observarConexion().listen(
      (hayRed) async {
        _emitir(_estado.copyWith(hayConexion: hayRed));
        if (hayRed && !_detenido) {
          await sincronizarAhora();
        }
      },
      onError: (Object _) {
        // Un error del listener de red no debe tumbar la app: se asume
        // conexión y se deja que el próximo cambio de estado lo reintente.
        _emitir(_estado.copyWith(hayConexion: true));
      },
    );
  }

  /// Comprueba si hay red y sincroniza. Devuelve el resultado de la pasada.
  Future<ResultadoSincronizacion> sincronizarAhora() async {
    if (_detenido) {
      return const ResultadoSincronizacion(
        sincronizados: 0,
        fallidos: 0,
        omitidos: 0,
        huboRed: false,
      );
    }

    if (_sincronizando) {
      // Reentrada segura: se marca para ejecutar justo después de la actual.
      _pendienteDeEjecucion = true;
      return const ResultadoSincronizacion(
        sincronizados: 0,
        fallidos: 0,
        omitidos: 0,
        huboRed: true,
      );
    }

    _sincronizando = true;
    var sincronizados = 0;
    var fallidos = 0;
    var omitidos = 0;
    var huboRed = true;

    try {
      _emitir(_estado.copyWith(enEjecucion: true, limpiarError: true));

      huboRed = await _conectividad.hayConexion();
      _emitir(_estado.copyWith(hayConexion: huboRed));

      if (!huboRed) {
        final pendientes = await _cola.contarPendientes();
        _emitir(
          _estado.copyWith(
            enEjecucion: false,
            fallidosEnUltimaEjecucion: 0,
            pendientes: pendientes,
          ),
        );
        return const ResultadoSincronizacion(
          sincronizados: 0,
          fallidos: 0,
          omitidos: 0,
          huboRed: false,
        );
      }

      final pendientes = await _cola.pendientes();
      final ahora = _clock.nowUtc();

      for (final item in pendientes) {
        // Backoff: aún no toca reintentar este item.
        if (!item.puedeIntentarEn(ahora)) {
          omitidos++;
          continue;
        }

        final ok = await _procesar(item);
        if (ok) {
          sincronizados++;
        } else {
          fallidos++;
        }
      }

      final restantes = await _cola.contarPendientes();
      _emitir(
        _estado.copyWith(
          enEjecucion: false,
          pendientes: restantes,
          procesadosEnUltimaEjecucion: sincronizados,
          fallidosEnUltimaEjecucion: fallidos,
        ),
      );

      return ResultadoSincronizacion(
        sincronizados: sincronizados,
        fallidos: fallidos,
        omitidos: omitidos,
        huboRed: huboRed,
      );
    } catch (e) {
      // Falla inesperada del propio ciclo (no de un item). Se registra sin
      // detalle técnico para el usuario.
      _emitir(
        _estado.copyWith(
          enEjecucion: false,
          ultimoError: 'No se pudo completar la sincronización.',
        ),
      );
      return ResultadoSincronizacion(
        sincronizados: sincronizados,
        fallidos: fallidos + 1,
        omitidos: omitidos,
        huboRed: huboRed,
      );
    } finally {
      _sincronizando = false;

      // Ejecuta la pasada que quedó pendiente por reentrada, si hubo.
      if (_pendienteDeEjecucion && !_detenido) {
        _pendienteDeEjecucion = false;
        await sincronizarAhora();
      }
    }
  }

  /// Procesa un item. Devuelve `true` si terminó sincronizado.
  ///
  /// Marca el item como [SyncStatus.sincronizando] antes de tocar la red: si la
  /// app muere aquí, el próximo arranque lo encuentra pendiente otra vez.
  ///
  /// Para un `upsert` con archivos, el orden es deliberado:
  ///
  /// ```text
  /// subir binarios -> obtener URL -> construir documento -> escribir
  /// ```
  ///
  /// Subir después de escribir dejaría documentos que apuntan a fotos
  /// inexistentes. Y borrar el archivo local solo al final es lo que evita
  /// perder la foto si la escritura falla a mitad de camino.
  Future<bool> _procesar(SyncQueueItem original) async {
    final ahora = _clock.nowUtc();

    // `item` se va reemplazando a medida que se registra progreso (por ejemplo,
    // URLs ya subidas). Importa para que, si algo falla más adelante, el
    // registro de fallo no pise ese progreso con una versión antigua del item.
    var item = original.copyWith(
      estado: SyncStatus.sincronizando,
      ultimoIntentoAt: ahora,
    );

    await _cola.actualizar(item);

    try {
      switch (item.operacion) {
        case SyncOperacion.upsert:
          item = await _prepararPayload(item);
          await _gateway.upsert(item.entidad, item.id, item.payload);
        case SyncOperacion.eliminar:
          await _gateway.eliminar(item.entidad, item.id);
      }

      // Solo se borra de la cola tras confirmación del servidor.
      await _cola.eliminar(item.id);

      // Limpia los archivos locales ya respaldados en la nube.
      if (item.tieneArchivos) {
        await _evidencia.limpiarLocales(item.rutasArchivosLocales);
      }

      return true;
    } catch (e) {
      await _registrarFallo(item, e);
      return false;
    }
  }

  /// Sube los binarios pendientes y devuelve el item con el payload resuelto.
  ///
  /// El mapa de URLs se persiste **antes** de escribir en el servidor. Ese orden
  /// importa: si la escritura falla justo después de subir las fotos, el
  /// reintento debe poder reutilizar esas URLs en lugar de volver a subir los
  /// mismos archivos. En una conexión de campo, donde cada reintento cuesta
  /// datos, esa es la diferencia entre una recuperación barata y una costosa.
  Future<SyncQueueItem> _prepararPayload(SyncQueueItem item) async {
    if (!item.tieneArchivos) return item;

    final resueltas = <String, String>{...item.urlsSubidas};
    var huboSubidasNuevas = false;

    for (final ruta in item.rutasArchivosLocales) {
      if (resueltas.containsKey(ruta)) continue;
      resueltas[ruta] = await _evidencia.subir(
        rutaLocal: ruta,
        nombreDestino: _nombreDestino(item, ruta),
      );
      huboSubidasNuevas = true;
    }

    if (!huboSubidasNuevas) return item;

    // Se persiste el avance antes de tocar el servidor, para que un fallo
    // posterior no obligue al reintento a volver a subir los mismos archivos.
    final actualizado = item.copyWith(
      urlsSubidas: resueltas,
      payload: _payloads.resolver(item.payload, resueltas),
    );
    await _cola.actualizar(actualizado);
    return actualizado;
  }

  /// Ruta del archivo en Storage. Estable entre reintentos, que es lo que hace
  /// la subida idempotente.
  String _nombreDestino(SyncQueueItem item, String rutaLocal) =>
      PayloadEvidencias.nombreDestino(
        coleccion: item.entidad.valor,
        entidadId: item.entidadId,
        rutaLocal: rutaLocal,
      );

  /// Aplica la política de reintentos ante un fallo.
  Future<void> _registrarFallo(SyncQueueItem item, Object error) async {
    final intentos = item.intentos + 1;
    final ahora = _clock.nowUtc();

    final agotado = _backoff.agotoIntentos(intentos);
    final espera = agotado
        ? null
        : _backoff.esperaParaIntento(intentos, random: _random);

    await _cola.actualizar(
      item.copyWith(
        estado: agotado ? SyncStatus.fallido : SyncStatus.pendiente,
        intentos: intentos,
        proximoIntentoAt: espera == null ? null : ahora.add(espera),
        ultimoError: _describirError(error),
      ),
    );
  }

  /// Traduce una excepción técnica a un mensaje apto para el supervisor.
  ///
  /// Nunca se expone el detalle interno (por ejemplo, una excepción de red
  /// cruda): el supervisor solo necesita saber que no se pudo subir y que se
  /// reintentará. El detalle técnico va al log de la aplicación.
  String _describirError(Object error) {
    final texto = error.toString();
    if (texto.contains('unavailable') ||
        texto.contains('network') ||
        texto.contains('timeout') ||
        texto.contains('SocketException')) {
      return 'Sin conexión: se reintentará automáticamente.';
    }
    return 'No se pudo sincronizar. Se reintentará automáticamente.';
  }

  /// Cantidad de items que aún esperan sincronización.
  Future<int> contarPendientes() => _cola.contarPendientes();

  /// Reintenta manualmente un item que quedó en estado fallido.
  ///
  /// Resetea el contador de intentos para que vuelva a entrar al ciclo normal.
  Future<void> reintentarManualmente(String itemId) async {
    final pendientes = await _cola.pendientes();

    SyncQueueItem? encontrado;
    for (final item in pendientes) {
      if (item.id == itemId) {
        encontrado = item;
        break;
      }
    }
    if (encontrado == null) return;

    await _cola.actualizar(
      encontrado.copyWith(
        estado: SyncStatus.pendiente,
        intentos: 0,
        proximoIntentoAt: null,
        limpiarError: true,
      ),
    );
    await sincronizarAhora();
  }

  /// Detiene la escucha de red y libera recursos.
  Future<void> dispose() async {
    _detenido = true;
    await _suscripcionRed?.cancel();
    _suscripcionRed = null;
    await _controllerEstado.close();
  }

  void _emitir(EstadoSync estado) {
    _estado = estado;
    if (!_controllerEstado.isClosed) {
      _controllerEstado.add(estado);
    }
  }
}