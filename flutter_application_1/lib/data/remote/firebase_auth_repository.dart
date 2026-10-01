/// Implementación de [AuthRepository] sobre Firebase Auth + Firestore.
///
/// ## Por qué el rol se lee de Firestore y no de las claims del token
///
/// Guardar el rol en el documento `usuarios/{uid}` permite que el coordinador
/// desactive una cuenta o cambie su rol sin emitir un token nuevo. La
/// consecuencia es que el rol se resuelve en cada lectura y no en el login: por
/// eso [observarSesion] vuelve a consultar el perfil cuando cambia la sesión,
/// en lugar de confiar solo en lo que devolvió `signIn`.
///
/// ## Seguridad
///
/// El nombre y el email se leen del documento de perfil, nunca de las claims:
/// [UserProfile.displayName] es texto libre que cualquier usuario puede
/// escribir, así que usarlo como nombre oficial abriría la puerta a suplantar a
/// otra persona en el panel del coordinador.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../domain/models/app_user.dart';
import '../../domain/repositories/contracts.dart';

/// Nombres de las colecciones de identidad.
abstract final class Colecciones {
  static const String usuarios = 'usuarios';
  static const String visitas = 'visitas';
  static const String novedades = 'novedades';
  static const String evidencias = 'evidencias';
  static const String centrosCosto = 'centros_costo';
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    Clock clock = const SystemClock(),
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance,
       _clock = clock;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final Clock _clock;

  AppUser? _actual;

  /// Último error de resolución de perfil, para que el login pueda explicar por
  /// qué volvió a la pantalla inicial.
  String? _ultimoError;

  @override
  AppUser? get usuarioActual => _actual;

  /// Mensaje del último fallo al resolver el perfil, o `null` si no hubo.
  ///
  /// La UI debe consumirlo antes de limpiar la sesión: si se pierde, el
  /// supervisor ve volver al login sin explicación.
  String? tomarUltimoError() {
    final error = _ultimoError;
    _ultimoError = null;
    return error;
  }

  @override
  Stream<AppUser?> observarSesion() async* {
    yield _actual;
    await for (final firebaseUser in _auth.authStateChanges()) {
      if (firebaseUser == null) {
        _actual = null;
        yield null;
        continue;
      }
      // Un error aquí (red caída, cuenta desactivada) no debe tumbar el stream:
      // se emite `null` para que la UI vuelva al login mostrando el mensaje, en
      // lugar de dejar al supervisor en una pantalla a medio cargar.
      AppUser? usuario;
      String? error;
      try {
        usuario = await _leerPerfil(firebaseUser);
      } on AppException catch (e) {
        error = e.message;
      } catch (_) {
        error = 'No se pudo verificar tu cuenta. Intenta de nuevo.';
      }

      _actual = usuario;
      if (usuario == null && error != null) _ultimoError = error;
      yield usuario;
    }
  }

  @override
  Future<AppUser> iniciarSesion({
    required String email,
    required String password,
  }) async {
    try {
      final firebaseUser = _auth.currentUser;
      final credencial = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // `signInWithEmailAndPassword` devuelve `User?`: la sesión puede quedar
      // cerrada si el plugin falla justo después de autenticar.
      final usuarioFirebase = credencial.user ?? firebaseUser;
      if (usuarioFirebase == null) {
        throw const AuthException('No se pudo iniciar sesión. Intenta de nuevo.');
      }

      final usuario = await _leerPerfil(usuarioFirebase);
      _actual = usuario;
      return usuario;
    } on FirebaseAuthException catch (e) {
      throw _traducir(e);
    } on FirebaseException catch (e, s) {
      throw RemoteException(
        'No se pudo iniciar sesión. Intenta de nuevo.',
        cause: e,
        stackTrace: s,
      );
    } catch (e, s) {
      throw AuthException(
        'No se pudo iniciar sesión. Intenta de nuevo.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<void> cerrarSesion() async {
    await _auth.signOut();
    _actual = null;
  }

  @override
  Future<void> actualizarPerfil(AppUser usuario) async {
    try {
      await _db
          .collection(Colecciones.usuarios)
          .doc(usuario.id)
          .set(usuario.toMap(), SetOptions(merge: true));
      _actual = usuario;
    } catch (e, s) {
      throw RemoteException(
        'No se pudo guardar el perfil.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Crea el documento de perfil la primera vez que un usuario entra.
  ///
  /// Se ejecuta tras un login exitoso para que un supervisor creado a mano en
  /// la consola de Firebase no quede sin rol y sin visitas asignadas.
  Future<void> asegurarPerfil(User firebaseUser) async {
    final referencia = _db
        .collection(Colecciones.usuarios)
        .doc(firebaseUser.uid);

    final existente = await referencia.get();
    if (existente.exists) return;

    await referencia.set(<String, dynamic>{
      'id': firebaseUser.uid,
      'nombre': (firebaseUser.displayName ?? '').isNotEmpty
          ? firebaseUser.displayName
          : firebaseUser.email?.split('@').first ?? 'Usuario',
      'email': firebaseUser.email ?? '',
      // Por defecto supervisor: es el rol de menor privilegio. El coordinador
      // sube al usuario desde el panel, nunca la app.
      'rol': 'supervisor',
      'estado': 'activo',
      'createdAt': _clock.nowUtc().toIso8601String(),
    });
  }

  /// Lee el perfil y resuelve el rol y el estado de la cuenta.
  Future<AppUser> _leerPerfil(User firebaseUser) async {
    await asegurarPerfil(firebaseUser);

    final doc = await _db
        .collection(Colecciones.usuarios)
        .doc(firebaseUser.uid)
        .get();

    final datos = <String, dynamic>{...(doc.data() ?? <String, dynamic>{})};
    // El email verificado por Auth es la fuente confiable; el del documento
    // podría estar desactualizado.
    datos['email'] = firebaseUser.email ?? datos['email'];
    datos['id'] = firebaseUser.uid;

    final usuario = AppUser.fromMap(datos);

    if (!usuario.estaActivo) {
      // Cuenta desactivada: se cierra la sesión en lugar de dejarla entrar con
      // un error más adelante, para que el mensaje sea claro.
      await _auth.signOut();
      _actual = null;
      throw const AuthException(
        'Tu cuenta está desactivada. Contacta al coordinador.',
      );
    }

    return usuario;
  }

  /// Traduce los códigos de Firebase Auth a mensajes en español.
  ///
  /// Se evita exponer el texto original porque los mensajes del SDK están
  /// en inglés y a veces mencionan el proveedor (por ejemplo, "sign in with
  /// Google"), lo que confunde al supervisor de campo.
  AppException _traducir(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-email' => const AuthException('El correo no tiene un formato válido.'),
      'user-disabled' => const AuthException(
        'Tu cuenta está desactivada. Contacta al coordinador.',
      ),
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        const AuthException('Correo o contraseña incorrectos.'),
      'too-many-requests' => const AuthException(
        'Demasiados intentos. Espera un momento e intenta de nuevo.',
      ),
      'network-request-failed' => const AuthException(
        'Sin conexión. Revisa tu red e intenta de nuevo.',
      ),
      _ => const AuthException('No se pudo iniciar sesión. Intenta de nuevo.'),
    };
  }
}
