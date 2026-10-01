/// Contratos de la capa de datos.
///
/// Las implementaciones reales viven en `lib/data/` (Firestore, Storage, Hive).
/// El `SyncService` y los repositorios dependen solo de estas interfaces, lo
/// que permite testear toda la lógica offline con dobles en memoria, sin
/// emulador ni credenciales.
library;

import '../models/enums.dart';
import '../models/evidencia.dart';
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