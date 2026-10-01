/// Implementación de [AlmacenLocal] sobre Hive.
///
/// Es la caché de campo del supervisor. Reglas que respeta:
///
///  * **Nunca lanza por contenido ilegible.** Si una entrada está corrupta se
///    salta y el resto de la app sigue funcionando; una caché que tumba la app
///    al arrancar es peor que una caché con un registro menos.
///  * **Los registros locales mandan.** Cuando hay una visita en Firestore y una
///    versión local con cambios sin sincronizar, gana la local. Si perdiera la
///    local, el supervisor vería su check-in desaparecer al recuperar la red,
///    que es la pérdida de información que el reto prohíbe.
///  * **Las emisiones son reactivas.** `observarVisitasDe` emite en cada
///    escritura, para que la UI refleje el check-in al instante sin esperar al
///    siguiente build.
library;

import 'dart:async';

import 'package:hive_ce/hive.dart';

import '../../core/utils/json_almacen.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/evidencia.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/visita.dart';
import '../../domain/repositories/contracts.dart';
import 'hive_cajas.dart';

/// Implementación concreta de la caché local.
class HiveAlmacenLocal implements AlmacenLocal {
  HiveAlmacenLocal({
    Box<dynamic>? visitas,
    Box<dynamic>? evidencias,
    Box<dynamic>? novedades,
    Box<dynamic>? centrosCosto,
  }) : _visitas = visitas ?? caja(Cajas.visitas),
       _evidencias = evidencias ?? caja(Cajas.evidencias),
       _novedades = novedades ?? caja(Cajas.novedades),
       _centros = centrosCosto ?? caja(Cajas.centrosCosto);

  final Box<dynamic> _visitas;
  final Box<dynamic> _evidencias;
  final Box<dynamic> _novedades;
  final Box<dynamic> _centros;

  // ---------------------------------------------------------------- visitas

  @override
  Future<void> guardarVisita(Visita visita) =>
      _visitas.put(visita.id, JsonAlmacen.encode(visita.toMap()));

  @override
  Future<Visita?> visitaPorId(String visitaId) async =>
      _aVisita(_visitas.get(visitaId));

  @override
  Future<List<Visita>> visitasDe(String supervisorId) async {
    final resultado = <Visita>[];
    for (final valor in _visitas.values) {
      final v = _aVisita(valor);
      if (v != null && v.supervisorId == supervisorId) resultado.add(v);
    }
    // Más próxima primero: es el orden en el que el supervisor trabaja.
    resultado.sort((a, b) => b.fechaProgramada.compareTo(a.fechaProgramada));
    return List.unmodifiable(resultado);
  }

  @override
  Stream<List<Visita>> observarVisitasDe(String supervisorId) async* {
    yield await visitasDe(supervisorId);
    await for (final _ in _visitas.watch()) {
      yield await visitasDe(supervisorId);
    }
  }

  @override
  Future<void> eliminarVisita(String visitaId) => _visitas.delete(visitaId);

  // ------------------------------------------------------------- evidencias

  @override
  Future<void> guardarEvidencia(Evidencia evidencia) =>
      _evidencias.put(evidencia.id, JsonAlmacen.encode(evidencia.toMap()));

  @override
  Future<List<Evidencia>> evidenciasDe(String visitaId) async {
    final resultado = <Evidencia>[];
    for (final valor in _evidencias.values) {
      final e = _aEvidencia(valor);
      if (e != null && e.visitaId == visitaId) resultado.add(e);
    }
    resultado.sort((a, b) => a.capturadaAt.compareTo(b.capturadaAt));
    return List.unmodifiable(resultado);
  }

  @override
  Stream<List<Evidencia>> observarEvidenciasDe(String visitaId) async* {
    yield await evidenciasDe(visitaId);
    await for (final _ in _evidencias.watch()) {
      yield await evidenciasDe(visitaId);
    }
  }

  @override
  Future<void> eliminarEvidencia(String evidenciaId) =>
      _evidencias.delete(evidenciaId);

  // --------------------------------------------------------------- novedades

  @override
  Future<void> guardarNovedad(Novedad novedad) =>
      _novedades.put(novedad.id, JsonAlmacen.encode(novedad.toMap()));

  @override
  Future<Novedad?> novedadPorId(String novedadId) async =>
      _aNovedad(_novedades.get(novedadId));

  @override
  Future<List<Novedad>> novedadesDe(String visitaId) async {
    final resultado = <Novedad>[];
    for (final valor in _novedades.values) {
      final n = _aNovedad(valor);
      if (n != null && n.visitaId == visitaId) resultado.add(n);
    }
    resultado.sort((a, b) => b.reportadaAt.compareTo(a.reportadaAt));
    return List.unmodifiable(resultado);
  }

  // -------------------------------------------------------- centros de costo

  @override
  Future<void> guardarCentroCosto(CentroCosto centro) =>
      _centros.put(centro.id, JsonAlmacen.encode(centro.toMap()));

  @override
  Future<CentroCosto?> centroCostoPorId(String id) async =>
      _aCentro(_centros.get(id));

  @override
  Future<List<CentroCosto>> centrosActivos() async {
    final resultado = <CentroCosto>[];
    for (final valor in _centros.values) {
      final c = _aCentro(valor);
      if (c != null && c.activo) resultado.add(c);
    }
    resultado.sort((a, b) => a.nombre.compareTo(b.nombre));
    return List.unmodifiable(resultado);
  }

  @override
  Future<void> cerrar() async {
    for (final c in [_visitas, _evidencias, _novedades, _centros]) {
      if (c.isOpen) await c.close();
    }
  }

  // ------------------------------------------------------------- decodificar

  static Visita? _aVisita(Object? valor) => _a(valor, Visita.fromMap);
  static Evidencia? _aEvidencia(Object? valor) => _a(valor, Evidencia.fromMap);
  static Novedad? _aNovedad(Object? valor) => _a(valor, Novedad.fromMap);
  static CentroCosto? _aCentro(Object? valor) => _a(valor, CentroCosto.fromMap);

  /// Decodifica y convierte, devolviendo `null` ante cualquier dato ilegible.
  static T? _a<T>(Object? valor, T Function(Map<String, dynamic>) construir) {
    final mapa = JsonAlmacen.decode(valor);
    if (mapa == null) return null;
    try {
      return construir(mapa);
    } catch (_) {
      return null;
    }
  }
}

/// Implementación de [VisitaLookup] sobre el mismo almacén, para que el
/// `SyncService` resuelva el contenido completo de una visita al construir el
/// documento remoto.
class HiveVisitaLookup implements VisitaLookup {
  HiveVisitaLookup(this._almacen);

  final AlmacenLocal _almacen;

  @override
  Future<Visita?> obtenerPorId(String visitaId) => _almacen.visitaPorId(visitaId);

  @override
  Future<List<Evidencia>> obtenerEvidencias(String visitaId) =>
      _almacen.evidenciasDe(visitaId);
}
