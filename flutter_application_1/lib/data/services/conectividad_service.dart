/// Implementación de [ConnectivityService] sobre `connectivity_plus`.
///
/// ## Por qué la información se normaliza a un solo booleano
///
/// `connectivity_plus` 7.x devuelve una **lista** de interfaces activas
/// (`[wifi, cellular]`) porque un dispositivo puede estar conectado a varias a
/// la vez. El dominio solo necesita "¿hay red?", así que esta capa reduce la
/// lista a un booleano y es el único punto del proyecto que conoce ese detalle.
///
/// ## Lo que este servicio NO puede hacer
///
/// Detectar que hay Internet. Un WiFi conectado a un router sin salida reporta
/// `wifi` igual que uno funcional. Por eso el `SyncService` trata un fallo de
/// subida por red como estado offline y programa un reintento, en lugar de
/// marcar el item como fallido de inmediato. Esa decisión está documentada en
/// `sync_service.dart`.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/repositories/contracts.dart';

class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Último valor conocido, para responder sin una llamada asíncrona al stream.
  bool _ultimo = true;

  @override
  Future<bool> hayConexion() async {
    try {
      final resultados = await _connectivity.checkConnectivity();
      return _interpretar(resultados);
    } catch (_) {
      // Si el propio plugin falla, se asume conexión: el `SyncService` igual
      // reintenta y programa backoff ante el error real. Asumir "sin red"
      // dejaría al supervisor con registros atascados para siempre.
      return true;
    }
  }

  @override
  Stream<bool> observarConexion() => _normalizado;

  @override
  Stream<void> recuperarConexion() =>
      _normalizado.where((conectado) => conectado).map((_) {});

  /// Stream único y normalizado. Ambos métodos públicos se apoyan en él para no
  /// abrir dos suscripciones al canal del plugin.
  Stream<bool> get _normalizado => _connectivity.onConnectivityChanged
      .map(_interpretar)
      .distinct()
      .map((valor) {
        _ultimo = valor;
        return valor;
      });

  /// `true` si hay al menos una interfaz de red utilizable.
  ///
  /// `bluetooth` y `other` se excluyen a propósito: no implican acceso a
  /// Internet en un caso normal de uso en campo.
  static bool _interpretar(List<ConnectivityResult> resultados) {
    if (resultados.isEmpty) return false;
    if (resultados.contains(ConnectivityResult.none)) {
      // `none` puede venir acompañado de otras entradas en algunas plataformas;
      // si viene sola, no hay red.
      return resultados.length > 1 &&
          resultados.any((r) => _esRedUtilizable(r));
    }
    return resultados.any(_esRedUtilizable);
  }

  static bool _esRedUtilizable(ConnectivityResult r) =>
      r == ConnectivityResult.wifi ||
      r == ConnectivityResult.ethernet ||
      r == ConnectivityResult.mobile ||
      r == ConnectivityResult.vpn ||
      r == ConnectivityResult.satellite;

  /// Último valor observado. Útil para pintar el indicador de red sin esperar al
  /// primer evento del stream.
  bool get ultimoConocido => _ultimo;
}
