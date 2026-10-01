/// Dobles en memoria para testear el modo offline sin Firebase.
///
/// Cada doble registra las llamadas que recibe, de modo que los tests pueden
/// afirmar sobre el comportamiento observable (qué se escribió, en qué orden y
/// cuántas veces) en lugar de inspeccionar la implementación.
library;

import 'dart:async';

import 'package:fieldcheck/data/repositories/visita_repository_impl.dart';
import 'package:fieldcheck/domain/models/centro_costo.dart';
import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/evidencia.dart';
import 'package:fieldcheck/domain/models/novedad.dart';
import 'package:fieldcheck/domain/models/sync_queue_item.dart';
import 'package:fieldcheck/domain/models/visita.dart';
import 'package:fieldcheck/domain/repositories/contracts.dart';

/// Cola de sincronización en memoria.
class FakeSyncQueueStore implements SyncQueueStore {
  FakeSyncQueueStore([List<SyncQueueItem>? inicial])
    : _items = inicial == null
          ? <String, SyncQueueItem>{}
          : {for (final i in inicial) i.id: i};

  final Map<String, SyncQueueItem> _items;
  final StreamController<int> _controlador = StreamController<int>.broadcast();

  /// Copia del estado actual, para inspeccionar desde los tests.
  Map<String, SyncQueueItem> get items => Map.unmodifiable(_items);

  /// Historial de operaciones, útil para verificar el orden FIFO.
  final List<String> registro = [];

  @override
  Future<void> encolar(SyncQueueItem item) async {
    registro.add('encolar:${item.id}');
    _items[item.id] = item;
    _notificar();
  }

  @override
  Future<List<SyncQueueItem>> pendientes() async {
    final resultado = _items.values.where((i) => i.requiereSync).toList()
      // Orden FIFO por `creadoAt`; a igualdad de fecha, por id, para que el
      // orden sea determinista en los tests.
      ..sort((a, b) {
        final porFecha = a.creadoAt.compareTo(b.creadoAt);
        return porFecha != 0 ? porFecha : a.id.compareTo(b.id);
      });
    return List.unmodifiable(resultado);
  }

  @override
  Future<void> actualizar(SyncQueueItem item) async {
    registro.add('actualizar:${item.id}:${item.estado.valor}');
    _items[item.id] = item;
    _notificar();
  }

  @override
  Future<void> eliminar(String id) async {
    registro.add('eliminar:$id');
    _items.remove(id);
    _notificar();
  }

  @override
  Future<int> contarPendientes() async =>
      _items.values.where((i) => i.requiereSync).length;

  @override
  Stream<int> observarPendientes() => _controlador.stream;

  @override
  Future<void> cerrar() async => _controlador.close();

  void _notificar() {
    if (!_controlador.isClosed) {
      _controlador.add(_items.values.where((i) => i.requiereSync).length);
    }
  }
}

/// Gateway remoto en memoria que registra las escrituras.
class FakeRemoteSyncGateway implements RemoteSyncGateway {
  /// Documentos "en el servidor", indexados por colección y luego por id.
  final Map<String, Map<String, Map<String, dynamic>>> documentos = {};

  final List<String> escrituras = [];

  /// Si se asigna, `upsert` y `eliminar` lanzan este error.
  Object? errorAlEscribir;

  /// Número de veces que se debe fallar antes de empezar a funcionar.
  int fallosRestantes = 0;

  @override
  Future<void> upsert(
    TipoEntidad entidad,
    String id,
    Map<String, dynamic> payload,
  ) async {
    _simularFallo();
    escrituras.add('upsert:${entidad.valor}/$id');
    documentos
        .putIfAbsent(entidad.valor, () => {})[id] = Map<String, dynamic>.from(payload);
  }

  @override
  Future<void> eliminar(TipoEntidad entidad, String id) async {
    _simularFallo();
    escrituras.add('eliminar:${entidad.valor}/$id');
    documentos[entidad.valor]?.remove(id);
  }

  void _simularFallo() {
    if (errorAlEscribir != null) throw errorAlEscribir!;
    if (fallosRestantes > 0) {
      fallosRestantes--;
      throw StateError('fallo transitorio');
    }
  }

  bool existe(TipoEntidad entidad, String id) =>
      documentos[entidad.valor]?.containsKey(id) ?? false;
}

/// Subidor de evidencias en memoria.
class FakeEvidenceUploader implements EvidenceUploader {
  final List<String> subidas = [];
  final List<String> rutasLocalesLimpias = [];

  /// Archivos "remotos" mapeados por nombre de destino.
  final Map<String, String> archivos = {};

  /// Si se asigna, `subir` lanza este error.
  Object? errorAlSubir;

  @override
  Future<String> subir({
    required String rutaLocal,
    required String nombreDestino,
  }) async {
    if (errorAlSubir != null) throw errorAlSubir!;
    subidas.add(nombreDestino);
    final url = archivos[nombreDestino] ?? 'https://fake.storage/$nombreDestino';
    archivos[nombreDestino] = url;
    return url;
  }

  @override
  Future<void> eliminar(String urlRemota) async {
    archivos.removeWhere((_, v) => v == urlRemota);
  }

  @override
  Future<void> limpiarLocales(List<String> rutasLocales) async {
    rutasLocalesLimpias.addAll(rutasLocales);
  }
}

/// Conectividad controlable por el test.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({this.conectado = true});

  bool conectado;

  /// Si se asigna, `hayConexion` lanza este error.
  Object? errorAlConsultar;

  final StreamController<bool> _controlador = StreamController<bool>.broadcast();

  void emitir(bool valor) {
    conectado = valor;
    if (!_controlador.isClosed) _controlador.add(valor);
  }

  @override
  Future<bool> hayConexion() async {
    if (errorAlConsultar != null) throw errorAlConsultar!;
    return conectado;
  }

  @override
  Stream<bool> observarConexion() => _controlador.stream;

  @override
  Stream<void> recuperarConexion() =>
      _controlador.stream.where((c) => c).map((_) {});

  Future<void> cerrar() => _controlador.close();
}

/// Fuente de visitas en memoria.
class FakeVisitaLookup implements VisitaLookup {
  final Map<String, Visita> _visitas = {};
  final Map<String, List<Evidencia>> _evidencias = {};

  void registrar(Visita visita) => _visitas[visita.id] = visita;

  void registrarEvidencias(String visitaId, List<Evidencia> evidencias) =>
      _evidencias[visitaId] = evidencias;

  @override
  Future<Visita?> obtenerPorId(String visitaId) async => _visitas[visitaId];

  @override
  Future<List<Evidencia>> obtenerEvidencias(String visitaId) async =>
      _evidencias[visitaId] ?? const [];
}

/// Almacén local en memoria: la caché de campo del supervisor.
///
/// Implementa los streams con controladores de difusión que reemiten la lista
/// completa en cada cambio. Es lo mismo que hace la implementación real sobre
/// las cajas de Hive, así que un test que pase con este doble ejercita la misma
/// secuencia de emissions que en producción.
class FakeAlmacenLocal implements AlmacenLocal {
  final Map<String, Visita> _visitas = {};
  final Map<String, List<Evidencia>> _evidencias = {};
  final Map<String, Novedad> _novedades = {};
  final Map<String, CentroCosto> _centros = {};

  final StreamController<List<Visita>> _visitasCtrl =
      StreamController<List<Visita>>.broadcast();
  final StreamController<List<Evidencia>> _evidenciasCtrl =
      StreamController<List<Evidencia>>.broadcast();

  /// Historial de escrituras, en orden, para comprobar qué se persistió.
  final List<String> escrituras = [];

  // --- Visitas ---

  @override
  Future<void> guardarVisita(Visita visita) async {
    escrituras.add('visita:${visita.id}:${visita.estado.valor}');
    _visitas[visita.id] = visita;
    _emitirVisitas(visita.supervisorId);
  }

  @override
  Future<Visita?> visitaPorId(String visitaId) async => _visitas[visitaId];

  @override
  Future<List<Visita>> visitasDe(String supervisorId) async {
    final lista = _visitas.values
        .where((v) => v.supervisorId == supervisorId)
        .toList()
      ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
    return List.unmodifiable(lista);
  }

  @override
  Stream<List<Visita>> observarVisitasDe(String supervisorId) => _visitasCtrl.stream;

  @override
  Future<void> eliminarVisita(String visitaId) async {
    _visitas.remove(visitaId);
    _emitirVisitas('');
  }

  // --- Evidencias ---

  @override
  Future<void> guardarEvidencia(Evidencia evidencia) async {
    escrituras.add('evidencia:${evidencia.id}');
    final lista = _evidencias.putIfAbsent(evidencia.visitaId, () => [])
      ..removeWhere((e) => e.id == evidencia.id)
      ..add(evidencia);
    _evidenciasCtrl.add(List.unmodifiable(lista));
  }

  @override
  Future<List<Evidencia>> evidenciasDe(String visitaId) async =>
      List.unmodifiable(_evidencias[visitaId] ?? const <Evidencia>[]);

  @override
  Stream<List<Evidencia>> observarEvidenciasDe(String visitaId) =>
      _evidenciasCtrl.stream;

  @override
  Future<void> eliminarEvidencia(String evidenciaId) async {
    for (final lista in _evidencias.values) {
      lista.removeWhere((e) => e.id == evidenciaId);
    }
  }

  // --- Novedades ---

  @override
  Future<void> guardarNovedad(Novedad novedad) async {
    escrituras.add('novedad:${novedad.id}:${novedad.prioridad.valor}');
    _novedades[novedad.id] = novedad;
  }

  @override
  Future<Novedad?> novedadPorId(String novedadId) async => _novedades[novedadId];

  @override
  Future<List<Novedad>> novedadesDe(String visitaId) async => List.unmodifiable(
    _novedades.values.where((n) => n.visitaId == visitaId).toList(),
  );

  // --- Centros de costo ---

  @override
  Future<void> guardarCentroCosto(CentroCosto centro) async => _centros[centro.id] = centro;

  @override
  Future<CentroCosto?> centroCostoPorId(String id) async => _centros[id];

  @override
  Future<List<CentroCosto>> centrosActivos() async =>
      List.unmodifiable(_centros.values.where((c) => c.activo).toList());

  @override
  Future<void> cerrar() async {
    await _visitasCtrl.close();
    await _evidenciasCtrl.close();
  }

  void _emitirVisitas(String supervisorId) {
    if (_visitasCtrl.isClosed) return;
    final lista = supervisorId.isEmpty
        ? _visitas.values.toList()
        : _visitas.values.where((v) => v.supervisorId == supervisorId).toList()
          ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
    _visitasCtrl.add(List.unmodifiable(lista));
  }
}

/// Fuente remota de visitas asignadas, en memoria.
///
/// Simula el Firestore donde el coordinador publica las asignaciones. El test
/// decide qué hay "en el servidor" con [agregar].
class FakeFuenteVisitasRemotas implements FuenteVisitasRemotas {
  FakeFuenteVisitasRemotas([List<Visita>? asignadas])
    : _asignadas = [...?asignadas];

  final List<Visita> _asignadas;

  /// Si se asigna, `visitasAsignadas` lanza este error (para simular sin red).
  Object? errorAlConsultar;

  /// Añade una visita al "servidor".
  void agregar(Visita visita) => _asignadas.add(visita);

  @override
  Future<List<Visita>> visitasAsignadas(String supervisorId) async {
    if (errorAlConsultar != null) throw errorAlConsultar!;
    return List.unmodifiable(
      _asignadas.where((v) => v.supervisorId == supervisorId),
    );
  }
}