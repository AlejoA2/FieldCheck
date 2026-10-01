/// Controlador de sesión: la fuente de verdad del usuario en la UI.
///
/// ## Por qué un `ChangeNotifier` y no leer `AuthRepository` en cada pantalla
///
/// El routing depende del rol. Si cada pantalla consultara el usuario por su
/// cuenta, habría dos verdades y un momento en que no coinciden: la app ya
/// navigated al panel del coordinador mientras otra pantalla aún cree que es
/// supervisor. Centralizando aquí, el rol se resuelve una vez.
///
/// ## El arranque en tres estados
///
/// `AuthRepository.observarSesion` puede tardar (lee el perfil de Firestore), y
/// durante ese tiempo no se sabe si hay sesión o no. Por eso [SesionController]
/// distingue `cargando` de `sinSesion`: sin ese tercer estado, el splash
/// parpadearía al login aunque haya sesión guardada.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/models/app_user.dart';
import '../../domain/repositories/contracts.dart';

/// Estado de la sesión, tal como lo ve la UI.
class SesionController extends ChangeNotifier {
  SesionController({required AuthRepository auth, required this.onSesionResuelta})
    : _auth = auth {
    _suscripcion = _auth.observarSesion().listen(
      _alEmitirUsuario,
      onError: (Object _) => _terminarCarga(),
    );
  }

  final AuthRepository _auth;

  /// Se invoca cuando la sesión se resuelve con un usuario o sin él.
  ///
  /// Sirve para que el contenedor de la app dispare la carga de visitas
  /// asignadas, que solo tiene sentido si ya hay supervisor identificado.
  final void Function(AppUser? usuario) onSesionResuelta;

  StreamSubscription<AppUser?>? _suscripcion;

  AppUser? _usuario;
  bool _cargando = true;

  /// `true` mientras no se sabe si hay sesión.
  bool get cargando => _cargando;

  /// Usuario en sesión, o `null`.
  AppUser? get usuario => _usuario;

  bool get haySesion => _usuario != null;

  /// `true` si el usuario en sesión es coordinador.
  bool get esCoordinador => _usuario?.esCoordinador ?? false;

  /// `true` si el usuario en sesión es supervisor.
  bool get esSupervisor => _usuario?.esSupervisor ?? false;

  /// Id del supervisor en sesión, o cadena vacía.
  ///
  /// Es exactamente el valor que `VisitaRepositoryImpl` recibe por callback:
  /// ambos leen la misma fuente.
  String get supervisorId => _usuario?.id ?? '';

  /// Inicia sesión con correo y contraseña.
  ///
  /// Devuelve el mensaje de error en vez de lanzar, porque el login necesita
  /// distinguir "credenciales malas" (mensaje junto a los campos) de "cuenta
  /// desactivada" (mensaje general) y no quiere try/catch en el widget.
  ///
  /// `null` significa éxito.
  Future<String?> iniciarSesion({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.iniciarSesion(email: email, password: password);
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (e, s) {
      Log.error('Fallo inesperado al iniciar sesión', e, s);
      return 'No se pudo iniciar sesión. Intenta de nuevo.';
    }
  }

  /// Cierra la sesión.
  ///
  /// No borra nada local a propósito: los registros de campo pendientes de
  /// subir deben sobrevivir al cierre para poder sincronizarse después.
  Future<void> cerrarSesion() async {
    await _auth.cerrarSesion();
    _usuario = null;
    notifyListeners();
  }

  /// Motivo por el que la sesión terminó sin usuario, o `null`.
  String? tomarMotivoDeCierre() => _auth.tomarMotivoDeCierre();

  void _alEmitirUsuario(AppUser? usuario) {
    final cambio = _usuario?.id != usuario?.id;
    _usuario = usuario;
    _terminarCarga();
    onSesionResuelta(usuario);
    if (cambio) notifyListeners();
  }

  void _terminarCarga() {
    if (!_cargando) return;
    _cargando = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}
