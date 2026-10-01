/// Implementación de [RemoteSyncGateway] sobre Cloud Firestore.
///
/// ## Idempotencia
///
/// El `SyncService` llama a `upsert` con el **id del item de la cola** como id
/// de documento. Como ese id es un UUID generado en el cliente y nunca se
/// reutiliza, reintentar una subida sobrescribe el mismo documento en lugar de
/// crear otro. Es la garantía que el reto pide como "prevención de duplicidad":
/// no depende de consultar antes de escribir.
///
/// ## Marca de sincronización
///
/// Cada documento se escribe con `syncStatus: 'sincronizado'` y `actualizadaAt`,
/// aunque el payload local diga `pendiente`. Si se guardara el valor local, el
/// coordinador vería en su panel registros que en realidad sí llegaron, y el
/// filtro "pendientes de sincronizar" mentiría.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../domain/models/enums.dart';
import '../../domain/repositories/contracts.dart';

class FirestoreSyncGateway implements RemoteSyncGateway {
  FirestoreSyncGateway({FirebaseFirestore? firestore, Clock clock = const SystemClock()})
    : _db = firestore ?? FirebaseFirestore.instance,
      _clock = clock;

  final FirebaseFirestore _db;
  final Clock _clock;

  @override
  Future<void> upsert(
    TipoEntidad entidad,
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _db
          .collection(entidad.valor)
          .doc(id)
          .set(_conMarcaDeSincronizacion(payload), SetOptions(merge: true));
    } catch (e, s) {
      throw RemoteException(
        'No se pudo guardar el registro en el servidor.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<void> eliminar(TipoEntidad entidad, String id) async {
    try {
      // `delete` no falla si el documento no existe, así que la operación ya
      // es idempotente sin ninguna comprobación previa.
      await _db.collection(entidad.valor).doc(id).delete();
    } catch (e, s) {
      throw RemoteException(
        'No se pudo eliminar el registro del servidor.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Añade los campos de trazabilidad al documento antes de escribirlo.
  Map<String, dynamic> _conMarcaDeSincronizacion(Map<String, dynamic> payload) {
    return <String, dynamic>{
      ...payload,
      'syncStatus': SyncStatus.sincronizado.valor,
      'actualizadaAt': _clock.nowUtc().toIso8601String(),
    };
  }
}
