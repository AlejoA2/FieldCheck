/// Registro de diagnóstico de la aplicación.
///
/// ## Por qué existe
///
/// `analysis_options.yaml` prohíbe `print` en `lib/` (`avoid_print`). La razón
/// no es estética: en un dispositivo de campo el log es la única traza que
/// sobrevive a un cierre abrupto, y hace falta un punto único donde escribir el
/// detalle técnico de un error que la UI nunca debe mostrar.
///
/// ## Qué se registra y qué no
///
/// Se registra el detalle técnico (excepciones, trazas, identificadores). Los
/// mensajes que ve el supervisor nunca salen de aquí: viajan en el campo
/// `message` de `AppException`, que ya está redactado en lenguaje claro.
///
/// ## Por qué `debugPrint` y no `developer.log`
///
/// `developer.log` escribe en el log del sistema y en web se pierde; además
/// exige niveles de severidad que en un flujo offline son casi todos errores
/// esperados. `debugPrint` funciona igual en todas las plataformas de destino
/// (móvil y web) y trunca las líneas largas, que es el problema real del logging
/// en Flutter.
library;

import 'package:flutter/foundation.dart';

/// Niveles de severidad del log.
enum NivelLog {
  /// Detalle de ejecución normal.
  info,

  /// Situación anómala que la app maneja (reintento, falta de red).
  aviso,

  /// Fallo que la app no pudo resolver.
  error,
}

/// Logger de la aplicación.
abstract final class Log {
  /// Etiqueta por defecto cuando el llamador no indica otra.
  static const String _porDefecto = 'FieldCheck';

  static void info(String mensaje, {String? etiqueta}) =>
      _escribir(mensaje, NivelLog.info, etiqueta);

  static void aviso(String mensaje, {String? etiqueta}) =>
      _escribir(mensaje, NivelLog.aviso, etiqueta);

  /// Registra un error con su causa.
  ///
  /// Se usa sobre todo en el punto donde una `AppException` se convierte en
  /// estado de UI: ahí es donde se pierde el detalle técnico y conviene
  /// conservarlo antes de descartar la excepción.
  static void error(
    String mensaje,
    Object causa, [
    StackTrace? traza,
    String? etiqueta,
  ]) {
    _escribir('$mensaje -> $causa', NivelLog.error, etiqueta, traza);
  }

  static void _escribir(
    String mensaje,
    NivelLog nivel,
    String? etiqueta, [
    StackTrace? traza,
  ]) {
    final prefijo = '${etiqueta ?? _porDefecto}/${nivel.name}';
    debugPrint('[$prefijo] $mensaje');
    if (traza != null) {
      debugPrintStack(stackTrace: traza, maxFrames: 12);
    }
  }
}
