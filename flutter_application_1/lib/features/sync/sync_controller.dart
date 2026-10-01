/// Vista del estado de sincronización para la UI del supervisor.
///
/// ## Por qué un `ChangeNotifier` propio y no leer `SyncService` directamente
///
/// `SyncService` expone un `Stream<EstadoSync>`, pero la UI necesita tres cosas
/// que un stream no da solo:
///
///  1. **El valor inicial sin esperar al primer evento.** Si el supervisor entra
///     a la app sin conexión, el banner se dibujaría con "0 pendientes" durante
///     un instante y luego saltaría a 7. Un badge que miente un segundo genera
///     desconfianza justamente en el momento en que más importa.
///  2. **Una acción de reintento.** El botón del banner llama a un método, no a
///     una construcción de stream.
///  3. **Separar "reintento manual" de "sincronización automática".** Un toque
///     del usuario debe tener efecto inmediato, aunque `SyncService` esté a mitad
///     de una pasada por la guarda de reentrada.
///
/// [SyncController] resuelve las tres cosas con la misma fuente de verdad.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/services/sync_service.dart';

/// Puente entre [SyncService] y los widgets.
class SyncController extends ChangeNotifier {
  SyncController({required SyncService sync, required int pendientesIniciales})
    : _sync = sync,
      _estadoInicial = sync.estadoActual.copyWith(
        pendientes: pendientesIniciales,
      ) {
    _estado = _estadoInicial;
    _suscripcion = _sync.obtenerEstado().listen(
      (estado) {
        _estado = estado;
        notifyListeners();
      },
      onError: (Object _) {
        // Un fallo del stream de estado no debe quitar el banner: se mantiene
        // el último valor conocido, que sigue siendo válido.
      },
    );
  }

  final SyncService _sync;

  /// Estado con el conteo de pendientes leído del almacén.
  ///
  /// `SyncService.estadoActual` arranca en 0 aunque la cola tenga registros de
  /// una sesión anterior, porque el servicio aún no la ha contado.
  final EstadoSync _estadoInicial;

  StreamSubscription<EstadoSync>? _suscripcion;
  late EstadoSync _estado;

  bool get hayConexion => _estado.hayConexion;
  int get pendientes => _estado.pendientes;
  bool get enEjecucion => _estado.enEjecucion;
  bool get hayFallidos => _estado.fallidosEnUltimaEjecucion > 0;
  String? get ultimoError => _estado.ultimoError;

  /// Lanza una sincronización.
  ///
  /// Con [manual] en `true` limpia el error previo: el usuario acaba de pedir
  /// reintentar, y dejar el mensaje del intento anterior sobre el banner
  /// mientras se intenta de nuevo sería confuso.
  Future<void> sincronizar({bool manual = false}) async {
    if (manual) {
      _estado = _estado.copyWith(limpiarError: true);
      notifyListeners();
    }
    await _sync.sincronizarAhora();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}
