/// Fuente remota de visitas asignadas: consulta a Firestore en modo solo
/// lectura.
///
/// Es la contraparte de `FuenteVisitasRemotas` del lado del supervisor. Aquí
/// solo aparecen las visitas que el coordinador asignó; las que el supervisor
/// registre en campo se crean en su dispositivo y viajan por la cola de
/// sincronización.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/app_exception.dart';
import '../../domain/models/visita.dart';
import '../repositories/visita_repository_impl.dart' show FuenteVisitasRemotas;
import 'firebase_auth_repository.dart' show Colecciones;

class FirestoreVisitasRemotas implements FuenteVisitasRemotas {
  FirestoreVisitasRemotas({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<List<Visita>> visitasAsignadas(String supervisorId) async {
    try {
      final consulta = _db
          .collection(Colecciones.visitas)
          .where('supervisorId', isEqualTo: supervisorId)
          // `serverTimestamp` no aplica aquí: el documento se escribe desde el
          // móvil. La fecha programada sí la elige el coordinador y es estable.
          .orderBy('fechaProgramada', descending: true);

      final snapshot = await consulta.get();
      return List.unmodifiable(
        snapshot.docs.map((d) => Visita.fromMap(_aMapa(d))),
      );
    } catch (e, s) {
      throw RemoteException(
        'No se pudieron actualizar las visitas asignadas.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Firestore devuelve los mapas con tipos propios (`Timestamp`, `GeoPoint`).
  /// Se normalizan a los tipos que el dominio entiende.
  static Map<String, dynamic> _aMapa(DocumentSnapshot<Map<String, dynamic>> doc) {
    final datos = doc.data();
    if (datos == null) return <String, dynamic>{'id': doc.id};
    return <String, dynamic>{...datos, 'id': datos['id'] ?? doc.id};
  }
}
