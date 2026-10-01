/// Item de la cola de sincronización offline.
///
/// Cada mutación local que deba llegar a Firestore se encola aquí como un
/// [SyncQueueItem]. El `SyncService` la drena cuando hay red.
///
/// Decisiones de diseño que resuelven los puntos que el reto pide explícitamente:
///
///  * **Integridad de la información**: el item conserva el payload completo
///    serializado. Nunca se encola "referencia a un objeto que podría mutar".
///  * **Prevención de duplicidad**: [id] es un UUID generado en el cliente y
///    además se usa como ID del documento en Firestore, de modo que reintentar
///    sobrescribe en vez de crear un duplicado.
///  * **Manejo de errores durante la sincronización**: [intentos] y
///    [proximoIntentoAt] implementan backoff exponencial para no martillar al
///    servidor cuando falla por intermitencia.
///  * **Control de registros pendientes**: [estado] es la fuente de verdad que
///    la UI muestra al supervisor como "N registros por sincronizar".
library;

import 'enums.dart';

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entidad,
    required this.entidadId,
    required this.payload,
    required this.creadoAt,
    this.operacion = SyncOperacion.upsert,
    this.estado = SyncStatus.pendiente,
    this.intentos = 0,
    this.ultimoIntentoAt,
    this.proximoIntentoAt,
    this.ultimoError,
    this.rutasArchivosLocales = const [],
    this.urlsSubidas = const {},
  });

  /// Clave de idempotencia. Se genera en el cliente y viaja como ID de documento.
  final String id;

  final TipoEntidad entidad;

  /// Id de la entidad afectada (visita, novedad o evidencia).
  final String entidadId;

  /// `upsert` crea o sobrescribe. `eliminar` es idempotente por naturaleza:
  /// borrar dos veces un documento inexistente no es un error.
  final SyncOperacion operacion;

  /// Documento serializado listo para escribirse en Firestore.
  final Map<String, dynamic> payload;

  final DateTime creadoAt;

  final SyncStatus estado;

  /// Número de intentos de sincronización ya realizados.
  final int intentos;

  final DateTime? ultimoIntentoAt;

  /// Instante a partir del cual se permite reintentar (backoff exponencial).
  final DateTime? proximoIntentoAt;

  /// Último error, truncado y sin detalle técnico.
  final String? ultimoError;

  /// Archivos locales que deben subirse a Storage antes de escribir el
  /// documento (fotografías de evidencia).
  ///
  /// Van dentro del payload de la visita, pero se listan aquí para que el
  /// `SyncService` sepa que debe subir binaries antes de confirmar el item.
  final List<String> rutasArchivosLocales;

  /// Archivos ya subidos, indexados por su ruta local.
  ///
  /// El `SyncService` lo rellena a medida que sube cada binario y lo persiste en
  /// el item. Sin este mapa, un reintento tras un fallo de red volvería a
  /// subir fotos que ya estaban en Storage: desperdicio de datos del usuario en
  /// una conexión de campo, que es exactamente el recurso escaso del escenario.
  final Map<String, String> urlsSubidas;

  bool get requiereSync => estado.requiereSync;

  /// `true` si este item tiene archivos pendientes de subir.
  bool get tieneArchivos => rutasArchivosLocales.isNotEmpty;

  /// `true` si ya se agotaron los reintentos automáticos y requiere que el
  /// usuario lo reintente manualmente.
  bool get requiereIntervencionManual => estado == SyncStatus.fallido;

  /// `true` si ya puede intentarse de nuevo según el backoff.
  bool puedeIntentarEn(DateTime ahora) {
    final proximo = proximoIntentoAt;
    if (proximo == null) return true;
    return !ahora.isBefore(proximo);
  }

  SyncQueueItem copyWith({
    SyncStatus? estado,
    int? intentos,
    DateTime? ultimoIntentoAt,
    DateTime? proximoIntentoAt,
    String? ultimoError,
    bool limpiarError = false,
    Map<String, dynamic>? payload,
    List<String>? rutasArchivosLocales,
    Map<String, String>? urlsSubidas,
    SyncOperacion? operacion,
  }) {
    return SyncQueueItem(
      id: id,
      entidad: entidad,
      entidadId: entidadId,
      payload: payload ?? this.payload,
      creadoAt: creadoAt,
      operacion: operacion ?? this.operacion,
      estado: estado ?? this.estado,
      intentos: intentos ?? this.intentos,
      ultimoIntentoAt: ultimoIntentoAt ?? this.ultimoIntentoAt,
      proximoIntentoAt: proximoIntentoAt ?? this.proximoIntentoAt,
      ultimoError: limpiarError ? null : (ultimoError ?? this.ultimoError),
      rutasArchivosLocales: rutasArchivosLocales ?? this.rutasArchivosLocales,
      urlsSubidas: urlsSubidas ?? this.urlsSubidas,
    );
  }

  /// Serializa a un mapa plano para Hive (Hive no admite mapas con valores anidados
  /// arbitrarios en todas las plataformas, y normalizar aquí mantiene el formato
  /// estable entre versiones).
  Map<String, dynamic> toMap() => {
    'id': id,
    'entidad': entidad.valor,
    'entidadId': entidadId,
    'operacion': operacion.valor,
    'payload': payload,
    'creadoAt': creadoAt.toIso8601String(),
    'estado': estado.valor,
    'intentos': intentos,
    'ultimoIntentoAt': ultimoIntentoAt?.toIso8601String(),
    'proximoIntentoAt': proximoIntentoAt?.toIso8601String(),
    'ultimoError': ultimoError,
    'rutasArchivosLocales': rutasArchivosLocales,
    'urlsSubidas': urlsSubidas,
  };

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) => SyncQueueItem(
    id: map['id'] as String? ?? '',
    entidad: TipoEntidad.desdeValor(map['entidad'] as String?),
    entidadId: map['entidadId'] as String? ?? '',
    payload: Map<String, dynamic>.from(
      (map['payload'] as Map?) ?? const <String, dynamic>{},
    ),
    creadoAt: DateTime.tryParse(map['creadoAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    operacion: SyncOperacion.desdeValor(map['operacion'] as String?),
    estado: SyncStatus.desdeValor(map['estado'] as String?),
    intentos: (map['intentos'] as num?)?.toInt() ?? 0,
    ultimoIntentoAt: DateTime.tryParse(map['ultimoIntentoAt'] as String? ?? '')?.toUtc(),
    proximoIntentoAt: DateTime.tryParse(map['proximoIntentoAt'] as String? ?? '')?.toUtc(),
    ultimoError: map['ultimoError'] as String?,
    rutasArchivosLocales: (map['rutasArchivosLocales'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
    urlsSubidas: _urlsDesde(map['urlsSubidas']),
  );

  /// Reconstruye el mapa de URLs ya subidas, tolerando formatos previos donde
  /// venía como lista de pares.
  static Map<String, String> _urlsDesde(Object? valor) {
    if (valor is Map) {
      return <String, String>{
        for (final entrada in valor.entries)
          entrada.key.toString(): entrada.value.toString(),
      };
    }
    if (valor is List) {
      // Formato legado: ["ruta|url", ...].
      final resultado = <String, String>{};
      for (final elemento in valor) {
        final partes = elemento.toString().split('|');
        if (partes.length == 2) {
          resultado[partes[0]] = partes[1];
        }
      }
      return resultado;
    }
    return const {};
  }

  @override
  String toString() =>
      'SyncQueueItem(${entidad.valor}/$entidadId, ${estado.valor}, intentos: $intentos)';
}

/// Tipo de operación encolada.
enum SyncOperacion {
  /// Crea el documento si no existe o lo sobrescribe si ya existe.
  upsert('upsert'),

  /// Elimina el documento. Idempotente.
  eliminar('eliminar');

  const SyncOperacion(this.valor);

  final String valor;

  static SyncOperacion desdeValor(String? valor) {
    return SyncOperacion.values.firstWhere(
      (o) => o.valor == valor,
      orElse: () => SyncOperacion.upsert,
    );
  }
}

/// Política de reintentos con backoff exponencial y jitter.
///
/// Sin jitter, varios supervisores que reconectan en el mismo instante golpean
/// el servidor a la vez justo cuando más frágil está. El jitter los dispersa.
///
/// ```text
/// intento 1 -> 30 s
/// intento 2 ->  1 min
/// intento 3 ->  2 min
/// intento 4 ->  4 min  (tope de 30 min, más jitter aleatorio)
/// ```
class BackoffPolicy {
  const BackoffPolicy({
    this.esperaInicial = const Duration(seconds: 30),
    this.esperaMaxima = const Duration(minutes: 30),
    this.factor = 2,
    this.maxIntentosAutomaticos = 8,
  });

  final Duration esperaInicial;
  final Duration esperaMaxima;
  final double factor;

  /// Tras esta cantidad de intentos fallidos el item queda en
  /// [SyncStatus.fallido] y espera intervención manual.
  final int maxIntentosAutomaticos;

  /// Calcula cuánto esperar tras el fallo número [intentoActual] (base 1).
  ///
  /// La secuencia es `esperaInicial * factor^(intento - 1)`, acotada por
  /// [esperaMaxima] y con un jitter de ±20 % para dispersar a los supervisores
  /// que reconectan en el mismo instante.
  ///
  /// [random] se inyecta para que los tests sean deterministas.
  Duration esperaParaIntento(int intentoActual, {required double Function() random}) {
    if (intentoActual <= 1) return esperaInicial;

    final exponente = intentoActual - 1;
    final milis = esperaInicial.inMilliseconds * _potencia(factor, exponente);
    final acotado = milis.clamp(0, esperaMaxima.inMilliseconds).toInt();

    // Jitter de ±20 %: dispersa sin volver la espera impredecible.
    final jitter = 1 + (random() * 0.4 - 0.2);
    final conJitter = (acotado * jitter).round();

    return Duration(milliseconds: conJitter.clamp(0, esperaMaxima.inMilliseconds));
  }

  /// `true` si ya se agotaron los reintentos automáticos.
  bool agotoIntentos(int intentosRealizados) =>
      intentosRealizados >= maxIntentosAutomaticos;

  static double _potencia(double base, int exponente) {
    var resultado = 1.0;
    for (var i = 0; i < exponente; i++) {
      resultado *= base;
    }
    return resultado;
  }
}