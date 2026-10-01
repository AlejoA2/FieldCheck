/// Implementación de [VisitaRepository]: la lógica de campo del supervisor.
///
/// Este archivo concentra el patrón offline-first del proyecto. Todo lo que hace
/// aquí sigue los mismos cuatro pasos, y esa repetición deliberada es lo que
/// hace que el comportamiento sea predecible y auditable:
///
/// ```text
/// 1. validar        (geofence, estado de la visita, datos obligatorios)
/// 2. guardar local  (Hive: la UI lee de acá, nunca de la red)
/// 3. encolar        (SyncQueueStore: la subida pendiente queda registrada)
/// 4. sincronizar    (best-effort: si no hay red, no importa)
/// ```
///
/// ## Por qué la validación va primero
///
/// Validar antes de escribir evita encolar cambios que el servidor va a
/// rechazar. Un item en la cola que nunca va a aceptarse es peor que uno que
/// nunca se creó: ocupa la cola y el supervisor ve un error que no puede
/// corregir.
///
/// ## Por qué no se propaga el fallo de red
///
/// Ningún método falla por falta de conexión. El supervisor debe poder hacer
/// check-in en una zona sin cobertura: si la operación lanzara, tendría que
/// esperar a salir del sitio, que es justo lo que el reto pide evitar.
library;

import 'package:uuid/uuid.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/evidencia.dart';
import '../../domain/models/geo_point.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/sync_queue_item.dart';
import '../../domain/models/visita.dart';
import '../../domain/repositories/contracts.dart';
import '../../domain/services/geofence_service.dart';
import '../services/sync_service.dart';

class VisitaRepositoryImpl implements VisitaRepository {
  VisitaRepositoryImpl({
    required AlmacenLocal almacen,
    required SyncQueueStore cola,
    required SyncService sync,
    required GeofenceService geofence,
    required FuenteVisitasRemotas remotas,
    required String Function() supervisorActual,
    Uuid uuid = const Uuid(),
    Clock clock = const SystemClock(),
  }) : _almacen = almacen,
       _cola = cola,
       _sync = sync,
       _geofence = geofence,
       _remotas = remotas,
       _supervisorActual = supervisorActual,
       _uuid = uuid,
       _clock = clock;

  final AlmacenLocal _almacen;
  final SyncQueueStore _cola;
  final SyncService _sync;
  final GeofenceService _geofence;

  /// Descarga de asignaciones del coordinador. Solo lectura: el supervisor
  /// nunca escribe en Firestore directamente, siempre a través de la cola.
  final FuenteVisitasRemotas _remotas;

  final Uuid _uuid;
  final Clock _clock;

  /// Id del supervisor en sesión.
  ///
  /// Se resuelve por callback y no por valor porque el repositorio se construye
  /// una sola vez, al iniciar la app, cuando todavía no hay sesión. El callback
  /// lo consulta en cada uso, que es lo que permite que un cambio de usuario
  /// (cerrar sesión y entrar otro) no deje datos cruzados.
  final String Function() _supervisorActual;

  // ------------------------------------------------------------- consultas

  @override
  Stream<List<Visita>> observarVisitasAsignadas(String supervisorId) =>
      _almacen.observarVisitasDe(supervisorId);

  @override
  Future<Visita?> obtenerVisita(String visitaId) => _almacen.visitaPorId(visitaId);

  @override
  Future<void> refrescarVisitasAsignadas(String supervisorId) async {
    try {
      final remotas = await _remotas.visitasAsignadas(supervisorId);
      for (final remota in remotas) {
        // La versión local gana si tiene cambios sin sincronizar: es el caso de
        // un check-in hecho sin red que aún no ha subido.
        final local = await _almacen.visitaPorId(remota.id);
        if (local != null && local.syncStatus.requiereSync) continue;
        await _almacen.guardarVisita(remota);
      }
    } catch (e) {
      // Best-effort: la caché local ya permite trabajar. Si la red falla, el
      // supervisor simplemente ve la última versión conocida.
    }
  }

  // --------------------------------------------------------------- check-in

  @override
  Future<Visita> registrarCheckIn({
    required String visitaId,
    required GeoPoint posicion,
  }) async {
    final visita = await _exigirVisita(visitaId);

    if (visita.tieneCheckIn) {
      throw const ValidationException(
        'Esta visita ya tiene un check-in registrado.',
      );
    }
    if (visita.estado == EstadoVisita.completada) {
      throw const ValidationException(
        'Esta visita ya fue completada y no admite cambios.',
      );
    }

    final centro = await _exigirCentro(visita.centroCostoId);
    final geo = _geofence.evaluar(posicion: posicion, centroCosto: centro);
    if (!geo.dentroDelRadio) {
      throw ValidationException(geo.mensaje);
    }

    final actualizada = visita.copyWith(
      checkIn: MarcadorVisita(
        momento: _clock.nowUtc(),
        posicion: posicion,
      ),
      estado: EstadoVisita.enProgreso,
      distanciaCheckInMetros: geo.distanciaMetros,
      syncStatus: SyncStatus.pendiente,
      actualizadaAt: _clock.nowUtc(),
    );

    await _guardarYEncolar(actualizada);
    return actualizada;
  }

  // -------------------------------------------------------------- check-out

  @override
  Future<Visita> registrarCheckOut({
    required String visitaId,
    required GeoPoint posicion,
    String observaciones = '',
  }) async {
    final visita = await _exigirVisita(visitaId);

    if (!visita.tieneCheckIn) {
      throw const ValidationException(
        'Debes hacer check-in antes de registrar la salida.',
      );
    }
    if (visita.tieneCheckOut) {
      throw const ValidationException('Esta visita ya tiene un check-out.');
    }

    final centro = await _exigirCentro(visita.centroCostoId);
    final geo = _geofence.evaluar(posicion: posicion, centroCosto: centro);
    if (!geo.dentroDelRadio) {
      throw ValidationException(geo.mensaje);
    }

    final actualizada = visita.copyWith(
      checkOut: MarcadorVisita(
        momento: _clock.nowUtc(),
        posicion: posicion,
      ),
      // El texto del supervisor se concatena al que ya hubiera: puede haber
      // escrito observaciones durante el checklist y no debe perderlas.
      observaciones: _combinarObservaciones(visita.observaciones, observaciones),
      estado: EstadoVisita.completada,
      distanciaCheckOutMetros: geo.distanciaMetros,
      syncStatus: SyncStatus.pendiente,
      actualizadaAt: _clock.nowUtc(),
    );

    await _guardarYEncolar(actualizada);
    return actualizada;
  }

  // ------------------------------------------------------------- checklist

  @override
  Future<Visita> guardarActividades({
    required String visitaId,
    required List<RegistroActividad> actividades,
  }) async {
    final visita = await _exigirVisita(visitaId);

    if (!visita.tieneCheckIn) {
      throw const ValidationException(
        'Debes hacer check-in antes de registrar las actividades.',
      );
    }
    if (visita.tieneCheckOut) {
      throw const ValidationException(
        'La visita ya se cerró: no se pueden modificar las actividades.',
      );
    }

    final actualizada = visita.copyWith(
      actividades: actividades,
      syncStatus: SyncStatus.pendiente,
      actualizadaAt: _clock.nowUtc(),
    );

    await _guardarYEncolar(actualizada);
    return actualizada;
  }

  // ------------------------------------------------------------- evidencias

  @override
  Future<Evidencia> adjuntarEvidencia({
    required String visitaId,
    required String rutaLocal,
    String? actividadId,
    GeoPoint? ubicacion,
    String comentario = '',
  }) async {
    await _exigirVisita(visitaId);

    final evidencia = Evidencia(
      id: _uuid.v4(),
      visitaId: visitaId,
      actividadId: actividadId,
      tipo: TipoEvidencia.foto,
      capturadaAt: _clock.nowUtc(),
      rutaLocal: rutaLocal,
      ubicacion: ubicacion,
      syncStatus: SyncStatus.pendiente,
      comentario: comentario,
    );

    // La evidencia se guarda primero en la caché: el supervisor tiene que ver
    // su foto de inmediato, aunque todavía no haya red.
    await _almacen.guardarEvidencia(evidencia);
    await _encolar(
      entidad: TipoEntidad.evidencia,
      entidadId: evidencia.id,
      payload: evidencia.toMap(),
      archivosLocales: [rutaLocal],
    );

    await _sincronizarSiHayRed();
    return evidencia;
  }

  @override
  Future<void> eliminarEvidencia(String evidenciaId) async {
    final visitaId = await _buscarVisitaDeEvidencia(evidenciaId);
    if (visitaId == null) return;

    final evidencia = await _buscarEvidencia(evidenciaId);
    // Una evidencia ya subida no se borra desde el móvil: el coordinador
    // podría estar revisándola. Solo se permite retirar lo que está pendiente.
    if (evidencia != null && evidencia.estaSincronizada) {
      throw const ValidationException(
        'Esta evidencia ya fue enviada y no se puede eliminar.',
      );
    }

    await _encolar(
      entidad: TipoEntidad.evidencia,
      entidadId: evidenciaId,
      payload: <String, dynamic>{},
      archivosLocales: const [],
      operacion: SyncOperacion.eliminar,
    );
    await _almacen.eliminarEvidencia(evidenciaId);

    await _sincronizarSiHayRed();
  }

  // --------------------------------------------------------------- novedades

  @override
  Future<Novedad> reportarNovedad({
    required String visitaId,
    required String titulo,
    required String descripcion,
    required Prioridad prioridad,
    List<String> accionesTomadas = const [],
    String? evidenciaId,
  }) async {
    await _exigirVisita(visitaId);

    if (titulo.trim().isEmpty) {
      throw const ValidationException('Escribe un título para la novedad.');
    }
    if (descripcion.trim().isEmpty) {
      throw const ValidationException(
        'Describe lo que encontraste para que el coordinador pueda actuar.',
      );
    }

    final visita = await _exigirVisita(visitaId);
    final ahora = _clock.nowUtc();

    final novedad = Novedad(
      id: _uuid.v4(),
      visitaId: visitaId,
      centroCostoId: visita.centroCostoId,
      titulo: titulo.trim(),
      descripcion: descripcion.trim(),
      prioridad: prioridad,
      reportadaPor: visita.supervisorId,
      reportadaAt: ahora,
      evidenciaIds: evidenciaId == null ? const [] : [evidenciaId],
      accionesTomadas: accionesTomadas
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList(),
      // Una novedad de prioridad alta se marca como notificada de inmediato:
      // el coordinator dashboard la ordena por urgencia y la muestra sin
      // importar si ya se sincronizó.
      coordinadorNotificado: prioridad.requiereAtencionInmediata,
      coordinadorNotificadoAt: prioridad.requiereAtencionInmediata ? ahora : null,
      syncStatus: SyncStatus.pendiente,
    );

    await _almacen.guardarNovedad(novedad);
    await _encolar(
      entidad: TipoEntidad.novedad,
      entidadId: novedad.id,
      payload: novedad.toMap(),
    );

    await _sincronizarSiHayRed();
    return novedad;
  }

  @override
  Future<List<Novedad>> novedadesDe(String visitaId) =>
      _almacen.novedadesDe(visitaId);

  // ------------------------------------------------------------------helpers

  /// Guarda en la caché local y encola para el servidor.
  Future<void> _guardarYEncolar(Visita visita) async {
    await _almacen.guardarVisita(visita);
    await _encolar(
      entidad: TipoEntidad.visita,
      entidadId: visita.id,
      payload: visita.toMap(),
    );
    await _sincronizarSiHayRed();
  }

  /// Crea el item de la cola con un id propio.
  ///
  /// El id del item **no** es el id de la entidad a propósito: cada mutación
  /// genera un item nuevo. Así, si la misma visita se sincroniza tres veces
  /// (check-in, checklist, check-out), el servidor recibe tres escrituras
  /// ordenadas de la misma versión completa, y el estado final es el correcto
  /// aunque una de ellas falle y se reintente.
  Future<void> _encolar({
    required TipoEntidad entidad,
    required String entidadId,
    required Map<String, dynamic> payload,
    List<String> archivosLocales = const [],
    SyncOperacion operacion = SyncOperacion.upsert,
  }) async {
    await _cola.encolar(
      SyncQueueItem(
        id: _uuid.v4(),
        entidad: entidad,
        entidadId: entidadId,
        payload: payload,
        creadoAt: _clock.nowUtc(),
        operacion: operacion,
        rutasArchivosLocales: archivosLocales,
      ),
    );
  }

  /// Intenta sincronizar. Nunca propaga el error: sin red es el caso normal.
  Future<void> _sincronizarSiHayRed() async {
    try {
      await _sync.sincronizarAhora();
    } catch (_) {
      // El item queda en la cola; `SyncService` ya aplicó el backoff y dejó
      // el error registrado para mostrarlo en la UI.
    }
  }

  Future<Visita> _exigirVisita(String visitaId) async {
    final visita = await _almacen.visitaPorId(visitaId);
    if (visita == null) {
      throw const NotFoundException('La visita ya no está disponible.');
    }
    return visita;
  }

  Future<CentroCosto> _exigirCentro(String centroCostoId) async {
    final centro = await _almacen.centroCostoPorId(centroCostoId);
    if (centro == null) {
      throw const NotFoundException(
        'No se pudo cargar la ubicación del centro de costo.',
      );
    }
    return centro;
  }

  /// Busca la visita a la que pertenece una evidencia recorriendo las evidencias
  /// conocidas de cada visita.
  ///
  /// Es O(n) pero sobre datos locales de un solo supervisor (decenas de
  /// registros), y evita mantener un índice inverso que se desincronizaría.
  Future<String?> _buscarVisitaDeEvidencia(String evidenciaId) async {
    final supervisorId = _supervisorActual();
    if (supervisorId.isEmpty) return null;

    for (final visita in await _almacen.visitasDe(supervisorId)) {
      for (final e in await _almacen.evidenciasDe(visita.id)) {
        if (e.id == evidenciaId) return visita.id;
      }
    }
    return null;
  }

  Future<Evidencia?> _buscarEvidencia(String evidenciaId) async {
    final visitaId = await _buscarVisitaDeEvidencia(evidenciaId);
    if (visitaId == null) return null;
    final lista = await _almacen.evidenciasDe(visitaId);
    for (final e in lista) {
      if (e.id == evidenciaId) return e;
    }
    return null;
  }

  static String _combinarObservaciones(String previa, String nueva) {
    final a = previa.trim();
    final b = nueva.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a\n$b';
  }
}

/// Fuente remota de visitas asignadas.
///
/// Es una interfaz y no un `RemoteSyncGateway`: el supervisor solo **lee**
/// asignaciones del servidor, nunca escribe directamente. Mantenerlo separado
/// deja explícito ese límite de permisos y evita que un descuido termine
/// haciendo que datos de campo salten la cola de sincronización.
abstract class FuenteVisitasRemotas {
  Future<List<Visita>> visitasAsignadas(String supervisorId);
}
