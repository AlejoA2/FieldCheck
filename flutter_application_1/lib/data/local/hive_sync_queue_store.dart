/// Implementación de [SyncQueueStore] sobre Hive.
///
/// ## Decisión clave: la cola se indexa por `creadoAt`
///
/// Hive ordena las claves de una caja alfabéticamente, y un UUID no tiene orden
/// temporal. Por eso el item se guarda bajo una clave compuesta
/// `"{microsDesdeEpoch}-{id}"`: el `watch()` de la caja emite en ese orden, lo
/// que hace que el orden FIFO se cumpla también en los tests y no solo por el
/// `sort` del `SyncService`.
///
/// Se usa además el índice `indiceId` para recuperar un item por su UUID sin
/// recorrer la caja, que es lo que necesita `reintentarManualmente`.
library;

import 'dart:async';

import 'package:hive_ce/hive.dart';

import '../../core/utils/json_almacen.dart';
import '../../domain/models/sync_queue_item.dart';
import '../../domain/repositories/contracts.dart';
import 'hive_cajas.dart';

class HiveSyncQueueStore implements SyncQueueStore {
  HiveSyncQueueStore({Box<dynamic>? cajaOverride})
    : _caja = cajaOverride ?? caja(Cajas.colaSync);

  final Box<dynamic> _caja;

  /// Clave secundaria `id de item -> clave de almacenamiento`.
  static const String _indiceId = 'indiceId';

  /// Compone la clave de almacenamiento. El prefijo numérico de longitud fija
  /// mantiene el orden lexicográfico igual al cronológico.
  static String _claveDe(SyncQueueItem item) =>
      '${item.creadoAt.toUtc().microsecondsSinceEpoch.toString().padLeft(20, '0')}'
      '-${item.id}';

  @override
  Future<void> encolar(SyncQueueItem item) async {
    await _escribir(item);
  }

  @override
  Future<void> actualizar(SyncQueueItem item) async {
    if (!_caja.containsKey(_claveDe(item))) {
      throw StateError(
        'No se puede actualizar un item de la cola que no existe: ${item.id}',
      );
    }
    await _escribir(item);
  }

  @override
  Future<void> eliminar(String id) async {
    final clave = _claveDeItem(id);
    if (clave == null) return;
    await _caja.delete(clave);
    await _caja.delete(_claveIndice(id));
  }

  @override
  Future<List<SyncQueueItem>> pendientes() async {
    // `values` sale en el orden de las claves, que ya es cronológico por diseño
    // de `_claveDe`. Aun así se filtra por estado: un item ya sincronizado que
    // quedara en la caja (por un cierre abrupto justo tras confirmar) no debe
    // volver a subirse.
    final resultado = <SyncQueueItem>[];
    for (final valor in _caja.values) {
      final item = _aItem(valor);
      if (item != null && item.requiereSync) {
        resultado.add(item);
      }
    }
    resultado.sort((a, b) => a.creadoAt.compareTo(b.creadoAt));
    return List.unmodifiable(resultado);
  }

  @override
  Future<int> contarPendientes() async {
    var total = 0;
    for (final valor in _caja.values) {
      final item = _aItem(valor);
      if (item != null && item.requiereSync) total++;
    }
    return total;
  }

  @override
  Stream<int> observarPendientes() async* {
    yield await contarPendientes();
    await for (final _ in _caja.watch()) {
      yield await contarPendientes();
    }
  }

  @override
  Future<void> cerrar() async => _caja.close();

  /// Escribe el item y mantiene el índice por id.
  Future<void> _escribir(SyncQueueItem item) async {
    final clave = _claveDe(item);
    await _caja.put(clave, JsonAlmacen.encode(item.toMap()));
    await _caja.put(_claveIndice(item.id), clave);
  }

  String _claveIndice(String id) => '$_indiceId/$id';

  /// Busca la clave de almacenamiento de un item por su id.
  String? _claveDeItem(String id) {
    final indice = _caja.get(_claveIndice(id));
    if (indice is String) return indice;

    // Respaldo para colas escritas antes de que existiera el índice, o si el
    // índice se perdió: recorre las claves buscando el sufijo del id.
    final sufijo = '-$id';
    for (final clave in _caja.keys) {
      if (clave is String && clave.endsWith(sufijo)) return clave;
    }
    return null;
  }

  /// Convierte un valor crudo de la caja en un item, o `null` si está corrupto.
  static SyncQueueItem? _aItem(Object? valor) {
    final mapa = JsonAlmacen.decode(valor);
    if (mapa == null) return null;
    try {
      return SyncQueueItem.fromMap(mapa);
    } catch (_) {
      return null;
    }
  }
}
