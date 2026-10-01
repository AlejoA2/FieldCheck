/// Contratos de la capa de datos.
///
/// Las implementaciones reales viven en `lib/data/` (Firestore, Storage, Hive).
/// El `SyncService` y los repositorios dependen solo de estas interfaces, lo
/// que permite testear toda la lógica offline con dobles en memoria, sin
/// emulador ni credenciales.
///
/// La separación tiene un motivo concreto: toda la lógica offline (geofence,
/// cola, reintentos, idempotencia) se ejercita en tests sin necesidad de red.
/// Firebase queda reducido a adaptadores delgados que traducen estas
/// interfaces a Firestore, Storage y Auth.
library;

import '../models/app_user.dart';
import '../models/centro_costo.dart';
import '../models/enums.dart';
import '../models/evidencia.dart';
import '../models/filtro_consulta.dart';
import '../models/geo_point.dart';
import '../models/novedad.dart';
import '../models/sync_queue_item.dart';
import '../models/visita.dart';

/// Almacén persistente de la cola de sincronización.
abstract class SyncQueueStore {
  /// Añade un item a la cola.
  Future<void> encolar(SyncQueueItem item);

  /// Devuelve los items pendientes de forma ordenada (más antiguos primero).
  ///
  /// El orden importa: las mutaciones de una misma visita deben aplicarse en
  /// secuencia para no perder la última versión.
  Future<List<SyncQueueItem>> pendientes();

  /// Actualiza un item existente.
  Future<void> actualizar(SyncQueueItem item);

  /// Elimina un item (solo tras confirmar que el servidor lo aceptó).
  Future<void> eliminar(String id);

  /// Cantidad de items que aún requieren sincronización.
  Future<int> contarPendientes();

  /// Emite los cambios del conteo de pendientes para alimentar el badge de la UI.
  Stream<int> observarPendientes();

  /// Libera recursos (cerrar Hive).
  Future<void> cerrar();
}

/// Sincroniza un documento contra el servidor.
///
/// La implementación real escribe en Firestore usando el [id] como ID de
/// documento, lo que hace la operación idempotente.
abstract class RemoteSyncGateway {
  /// Escribe (o sobrescribe) el documento en la colección correspondiente.
  ///
  /// Debe ser idempotente respecto a [SyncQueueItem.id].
  Future<void> upsert(TipoEntidad entidad, String id, Map<String, dynamic> payload);

  /// Elimina el documento. No debe fallar si ya no existe.
  Future<void> eliminar(TipoEntidad entidad, String id);
}

/// Sube archivos binarios (evidencias) y devuelve su URL pública.
abstract class EvidenceUploader {
  /// Sube [rutaLocal] y devuelve la URL remota.
  ///
  /// Debe ser idempotente: subir dos veces el mismo [nombreDestino] debe
  /// devolver la misma URL y no crear un archivo duplicado.
  Future<String> subir({
    required String rutaLocal,
    required String nombreDestino,
  });

  /// Elimina un archivo ya subido. Best-effort: no debe propagar el error.
  Future<void> eliminar(String urlRemota);

  /// Borra del dispositivo los archivos locales ya sincronizados.
  Future<void> limpiarLocales(List<String> rutasLocales);
}

/// Estado de la conexión del dispositivo.
abstract class ConnectivityService {
  /// `true` si el dispositivo tiene una interfaz de red activa.
  ///
  /// OJO: esto no garantiza que haya Internet real (p. ej. conectado a un WiFi
  /// sin salida a internet). Por eso el `SyncService` trata un fallo de red
  /// durante la subida igual que un estado offline.
  Future<bool> hayConexion();

  /// Emite los cambios de estado de conexión.
  Stream<bool> observarConexion();

  /// Emite `true` cuando se recupera la conexión.
  Stream<void> recuperarConexion();
}

/// Fuente de los registros de visita, que además pueden tener novedades.
///
/// Permite al `SyncService` resolver, al drenar la cola, el contenido completo
/// de una visita (con sus evidencias ya subidas) sin conocer el detalle de
/// almacenamiento.
abstract class VisitaLookup {
  Future<Visita?> obtenerPorId(String visitaId);

  /// Evidencias asociadas a una visita, incluidas las que aún son solo locales.
  Future<List<Evidencia>> obtenerEvidencias(String visitaId);
}

/// Autenticación y resolución de rol.
///
/// El rol vive en Firestore (`usuarios/{uid}`), no en las claims del token: así
/// el coordinador puede desactivar a alguien o cambiar su rol sin que tenga que
/// volver a iniciar sesión.
abstract class AuthRepository {
  /// Emite el usuario autenticado actual, o `null` si no hay sesión.
  Stream<AppUser?> observarSesion();

  /// Usuario de la sesión en curso. `null` si no hay sesión activa.
  AppUser? get usuarioActual;

  /// Inicia sesión y devuelve el perfil con su rol resuelto.
  Future<AppUser> iniciarSesion({
    required String email,
    required String password,
  });

  /// Cierra la sesión. Los datos locales del usuario no se borran: son su
  /// evidencia de campo y deben sobrevivir al cierre para poder sincronizar.
  Future<void> cerrarSesion();

  /// Guarda cambios del perfil del usuario autenticado.
  Future<void> actualizarPerfil(AppUser usuario);
}

/// Almacén local de lectura y escritura del supervisor.
///
/// Es la caché de campo: debe poder responder siempre, con o sin red. El
/// `SyncService` escribe en Firestore, pero esta caché es la que la UI del
/// supervisor lee siempre, de modo que lo que ve en pantalla es exactamente lo
/// que está por subir.
abstract class AlmacenLocal {
  // --- Visitas ---

  Future<void> guardarVisita(Visita visita);
  Future<Visita?> visitaPorId(String visitaId);

  /// Visitas de un supervisor, ordenadas por fecha programada.
  Future<List<Visita>> visitasDe(String supervisorId);

  /// Emite las visitas de un supervisor cada vez que cambian.
  Stream<List<Visita>> observarVisitasDe(String supervisorId);

  Future<void> eliminarVisita(String visitaId);

  // --- Evidencias ---

  Future<void> guardarEvidencia(Evidencia evidencia);
  Future<List<Evidencia>> evidenciasDe(String visitaId);
  Stream<List<Evidencia>> observarEvidenciasDe(String visitaId);
  Future<void> eliminarEvidencia(String evidenciaId);

  // --- Novedades ---

  Future<void> guardarNovedad(Novedad novedad);
  Future<Novedad?> novedadPorId(String novedadId);
  Future<List<Novedad>> novedadesDe(String visitaId);

  // --- Centros de costo (caché de solo lectura) ---

  Future<void> guardarCentroCosto(CentroCosto centro);
  Future<CentroCosto?> centroCostoPorId(String id);
  Future<List<CentroCosto>> centrosActivos();

  Future<void> cerrar();
}

/// Lecturas del coordinador sobre el histórico completo.
///
/// A diferencia del supervisor, el coordinador trabaja con conexión (es un panel
/// de escritorio), así que lee directamente de Firestore mediante streams.
abstract class ConsultaRepository {
  /// Visitas que cumplen el filtro.
  Stream<List<Visita>> observarVisitas(FiltroConsulta filtro);

  /// Novedades que cumplen el filtro, priorizando las de mayor urgencia.
  Stream<List<Novedad>> observarNovedades(FiltroConsulta filtro);

  /// Centros de costo, para el mapa de cobertura y los filtros.
  Stream<List<CentroCosto>> observarCentros();

  /// Visitas que cumplen el filtro, como lista concreta (para exportar).
  Future<List<Visita>> visitas(FiltroConsulta filtro);

  /// Novedades que cumplen el filtro, como lista concreta (para exportar).
  Future<List<Novedad>> novedades(FiltroConsulta filtro);

  /// Cierra una novedad con el comentario del coordinador.
  ///
  /// Es la única escritura del coordinador sobre contenido de campo, y solo
  /// avanza el estado: nunca modifica lo que reportó el supervisor.
  Future<void> resolverNovedad({
    required String novedadId,
    required String comentario,
    required String resueltoPor,
  });

  /// Marca una novedad como revisada (en curso, sin cerrarla).
  Future<void> marcarNovedadEnRevision(String novedadId);

  /// Crea una visita asignada a un supervisor.
  Future<Visita> asignarVisita({
    required String supervisorId,
    required String centroCostoId,
    required DateTime fechaProgramada,
  });
}

/// Operación de campo del supervisor sobre una visita.
///
/// Cada método sigue el mismo patrón offline-first:
///  1. valida (incluido el geofence, cuando aplica),
///  2. escribe en [AlmacenLocal],
///  3. encola en [SyncQueueStore],
///  4. intenta sincronizar si hay red.
///
/// Ninguno falla por falta de conexión: en ese caso el registro queda en la
/// cola y el supervisor puede seguir trabajando.
abstract class VisitaRepository {
  /// Visitas asignadas al supervisor. Responde desde la caché local.
  Stream<List<Visita>> observarVisitasAsignadas(String supervisorId);

  Future<Visita?> obtenerVisita(String visitaId);

  /// Descarga del servidor la lista de visitas asignadas.
  ///
  /// Es best-effort: si no hay red, se queda con la caché local sin error.
  Future<void> refrescarVisitasAsignadas(String supervisorId);

  /// Registra el check-in validando el geofence.
  ///
  /// Lanza [ValidationException] si la posición está fuera del radio.
  Future<Visita> registrarCheckIn({
    required String visitaId,
    required GeoPoint posicion,
  });

  /// Registra el check-out validando el geofence y cerrando la visita.
  Future<Visita> registrarCheckOut({
    required String visitaId,
    required GeoPoint posicion,
    String observaciones = '',
  });

  /// Guarda el resultado de las actividades del checklist.
  Future<Visita> guardarActividades({
    required String visitaId,
    required List<RegistroActividad> actividades,
  });

  /// Adjunta una foto tomada en el momento como evidencia de una actividad.
  Future<Evidencia> adjuntarEvidencia({
    required String visitaId,
    required String rutaLocal,
    String? actividadId,
    GeoPoint? ubicacion,
    String comentario = '',
  });

  /// Elimina una evidencia que todavía no se ha subido.
  Future<void> eliminarEvidencia(String evidenciaId);

  /// Reporta una novedad. Si [prioridad] es alta, se notifica al coordinador de
  /// inmediato en lugar de esperar al ciclo de sincronización.
  Future<Novedad> reportarNovedad({
    required String visitaId,
    required String titulo,
    required String descripcion,
    required Prioridad prioridad,
    List<String> accionesTomadas = const [],
    String? evidenciaId,
  });

  /// Novedades reportadas en una visita.
  Future<List<Novedad>> novedadesDe(String visitaId);
}