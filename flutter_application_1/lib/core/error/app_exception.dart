/// Jerarquía de errores de la aplicación.
///
/// El dominio lanza estas excepciones; las capas superiores (ViewModels,
/// repositorios) las capturan y las convierten en estado de UI. Ninguna
/// excepción debe llegar al usuario con detalle técnico.
///
/// Los subtipos solo aceptan un mensaje legible por el usuario. La causa
/// técnica original se registra en el punto de captura (`log`) en lugar de
/// viajarla dentro de la excepción, para no filtrar detalle interno a la UI.
library;

/// Error de dominio o de aplicación.
///
/// Permite pattern matching mediante `switch` sobre el tipo, así que no hace
/// falta una clase de "código de error" aparte.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  /// Mensaje apto para mostrar al usuario final (en español, sin trazas).
  final String message;

  /// Causa original, útil solo para logging.
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// La operación requiere conexión y no hay red disponible.
final class OfflineException extends AppException {
  const OfflineException([
    super.message = 'Sin conexión a Internet. Los datos se guardarán localmente.',
  ]);
}

/// Fallas de autenticación (credenciales inválidas, sesión expirada, etc.).
final class AuthException extends AppException {
  const AuthException(super.message);
}

/// El usuario no tiene permiso para la operación solicitada.
final class PermissionException extends AppException {
  const PermissionException([
    super.message = 'No tienes permisos para realizar esta acción.',
  ]);
}

/// No se encontró el recurso solicitado.
final class NotFoundException extends AppException {
  const NotFoundException([super.message = 'El recurso no existe.']);
}

/// Falló una validación de negocio (por ejemplo, geofence: check-in fuera del radio).
final class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Falla en la capa remota (Firestore, Storage, Auth).
final class RemoteException extends AppException {
  const RemoteException(super.message);
}

/// Falla al operar con el almacenamiento local (Hive, sistema de archivos).
final class LocalStorageException extends AppException {
  const LocalStorageException(super.message);
}

/// Falla al adquirir permisos del dispositivo (cámara, ubicación).
final class DevicePermissionException extends AppException {
  const DevicePermissionException(super.message);
}