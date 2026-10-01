/// Implementación de [ConsultaRepository] sobre Firestore, para el panel del
/// coordinador.
///
/// ## Diseño: filtrar en el cliente, no en la consulta
///
/// Todos los filtros ([FiltroConsulta]) se aplican en memoria sobre el snapshot
/// completo, en vez de traducirse a `where`/`orderBy` de Firestore.
///
/// El motivo es concreto: el panel necesita combinar fecha, supervisor, centro
/// de costo, estado y cumplimiento a la vez. Cada criterio adicional en la
/// consulta exige un índice compuesto, y los índices compuestos en Firestore
/// están limitados y se crean desde la consola. Con el histórico de un hackathon
/// (decenas o cientos de visitas) el snapshot completo entra de sobra en
/// memoria, y a cambio el filtro funciona sin ninguna configuración previa.
///
/// El punto en contra —traer documentos que luego se descartan— es aceptable a
/// esta escala, y está anotado aquí para que no se lea como descuido cuando el
/// histórico crezca.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/filtro_consulta.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/visita.dart';
import '../../domain/repositories/contracts.dart';
import '../remote/firebase_auth_repository.dart' show Colecciones;

class FirestoreConsultaRepository implements ConsultaRepository {
  FirestoreConsultaRepository({
    FirebaseFirestore? firestore,
    Clock clock = const SystemClock(),
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _clock = clock;

  final FirebaseFirestore _db;
  final Clock _clock;

  // ---------------------------------------------------------------- visitas

  @override
  Stream<List<Visita>> observarVisitas(FiltroConsulta filtro) {
    return _db
        .collection(Colecciones.visitas)
        .orderBy('fechaProgramada', descending: true)
        .snapshots()
        .map((s) => _visitasDe(s, filtro));
  }

  @override
  Future<List<Visita>> visitas(FiltroConsulta filtro) async {
    try {
      final s = await _db
          .collection(Colecciones.visitas)
          .orderBy('fechaProgramada', descending: true)
          .get();
      return _visitasDe(s, filtro);
    } catch (e, stack) {
      throw RemoteException(
        'No se pudo cargar el historial de visitas.',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  List<Visita> _visitasDe(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    FiltroConsulta filtro,
  ) {
    final resultado = snapshot.docs
        .map((d) => Visita.fromMap(_aMapa(d)))
        .where(filtro.coincideVisita)
        .toList();
    return List.unmodifiable(resultado);
  }

  // -------------------------------------------------------------- novedades

  @override
  Stream<List<Novedad>> observarNovedades(FiltroConsulta filtro) {
    return _db
        .collection(Colecciones.novedades)
        .orderBy('reportadaAt', descending: true)
        .snapshots()
        .map((s) => _novedadesDe(s, filtro));
  }

  @override
  Future<List<Novedad>> novedades(FiltroConsulta filtro) async {
    try {
      final s = await _db
          .collection(Colecciones.novedades)
          .orderBy('reportadaAt', descending: true)
          .get();
      return _novedadesDe(s, filtro);
    } catch (e, stack) {
      throw RemoteException(
        'No se pudieron cargar las novedades.',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  List<Novedad> _novedadesDe(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    FiltroConsulta filtro,
  ) {
    final resultado = snapshot.docs
        .map((d) => Novedad.fromMap(_aMapa(d)))
        .where(filtro.coincideNovedad)
        .toList();

    // Orden de urgencia, no solo de fecha: una novedad alta de hace tres días
    // sigue siendo más relevante que una baja de hace una hora.
    resultado.sort((a, b) {
      final porUrgencia = b.prioridad.pesoUrgencia.compareTo(
        a.prioridad.pesoUrgencia,
      );
      if (porUrgencia != 0) return porUrgencia;
      return b.reportadaAt.compareTo(a.reportadaAt);
    });

    return List.unmodifiable(resultado);
  }

  // ------------------------------------------------------- centros de costo

  @override
  Stream<List<CentroCosto>> observarCentros() {
    return _db
        .collection(Colecciones.centrosCosto)
        .snapshots()
        .map((s) {
          final lista = s.docs.map((d) => CentroCosto.fromMap(_aMapa(d))).toList()
            ..sort((a, b) => a.nombre.compareTo(b.nombre));
          return List.unmodifiable(lista);
        });
  }

  // -------------------------------------------------- escritura del coordinador

  @override
  Future<void> resolverNovedad({
    required String novedadId,
    required String comentario,
    required String resueltoPor,
  }) async {
    if (comentario.trim().isEmpty) {
      throw const ValidationException(
        'Escribe el cierre de la novedad para dejar registro de la solución.',
      );
    }
    await _db.collection(Colecciones.novedades).doc(novedadId).update(
      <String, dynamic>{
        'estado': EstadoNovedad.resuelta.valor,
        'resolucion': comentario.trim(),
        'resueltaAt': _clock.nowUtc().toIso8601String(),
        'resueltaPor': resueltoPor,
        'actualizadaAt': _clock.nowUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> marcarNovedadEnRevision(String novedadId) {
    return _db.collection(Colecciones.novedades).doc(novedadId).update(
      <String, dynamic>{
        'estado': EstadoNovedad.enRevision.valor,
        'actualizadaAt': _clock.nowUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<Visita> asignarVisita({
    required String supervisorId,
    required String centroCostoId,
    required DateTime fechaProgramada,
  }) async {
    final visita = Visita(
      id: _idVisita(),
      supervisorId: supervisorId,
      centroCostoId: centroCostoId,
      fechaProgramada: fechaProgramada,
      estado: EstadoVisita.pendiente,
      // Una visita asignada desde el servidor nace ya sincronizada: el
      // coordinador está conectado y no hay nada en la cola del móvil.
      syncStatus: SyncStatus.sincronizado,
      actualizadaAt: _clock.nowUtc(),
    );

    await _db
        .collection(Colecciones.visitas)
        .doc(visita.id)
        .set(visita.toMap());

    return visita;
  }

  /// Id de visita para el coordinador.
  ///
  /// No usa UUID: la generación aleatoria vive en `VisitaRepositoryImpl` (lado
  /// supervisor) y el id se construye aquí con marca de tiempo, lo que además
  /// deja los documentos ordenables por id.
  String _idVisita() =>
      'v_${_clock.nowUtc().millisecondsSinceEpoch.toRadixString(36)}';

  /// Normaliza el documento de Firestore al mapa que espera el dominio.
  static Map<String, dynamic> _aMapa(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final datos = doc.data();
    if (datos == null) return <String, dynamic>{'id': doc.id};
    return <String, dynamic>{...datos, 'id': datos['id'] ?? doc.id};
  }
}
