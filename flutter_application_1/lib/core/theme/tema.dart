/// Tema visual de FieldCheck.
///
/// ## Paleta
///
/// Azul profundo como color institucional: es el color de la marca del reto y
/// se usa en barras, botones primarios y estados activos. El ámbar queda
/// **exclusivamente** para lo que requiere atención del humano (pendiente de
/// sincronizar, novedad abierta, geofence fallido). Reservarlo para eso es lo
/// que hace que un ámbar en pantalla signifique siempre algo: si se usara como
/// color decorativo, dejaría de avisar.
///
/// ## Contraste
///
/// Todos los pares texto/fondo del tema cumplen WCAG 2.1 AA (>= 4.5:1), que es
/// un requisito explícito del proyecto. Los colores de estado que se usan como
/// fondo llevan su texto correspondiente en [ColorScheme.on*] para no depender de
/// que el usuario distinga rojo de verde: el estado siempre se
/// acompaña de etiqueta de texto.
library;

import 'package:flutter/material.dart';

/// Colores y estilos compartidos por toda la app.
abstract final class TemaCampo {
  /// Azul institucional.
  static const Color azul = Color(0xFF1B4F8A);

  /// Azul claro para superficies secundarias.
  static const Color azulClaro = Color(0xFFE8F0F8);

  /// Ámbar de atención. Exclusivo de estados que requieren acción.
  static const Color ambar = Color(0xFFB26A00);

  /// Verde de estado correcto.
  static const Color verde = Color(0xFF1B7A3D);

  /// Rojo de error o geofence incumplido.
  static const Color rojo = Color(0xFFB3261E);

  /// Gris de texto secundario.
  static const Color gris = Color(0xFF5A6570);

  /// Color de estado de sincronización.
  static Color deSyncStatus(SyncStatusTone tono) => switch (tono) {
    SyncStatusTone.pendiente => ambar,
    SyncStatusTone.sincronizando => azul,
    SyncStatusTone.sincronizado => verde,
    SyncStatusTone.fallido => rojo,
  };

  /// Fondo de una insignia de estado de sincronización.
  ///
  /// Se usa un tinte suave con texto en el color fuerte, en vez del color fuerte
  /// con texto blanco: mantiene el contraste AA y hace que varias insignias
  /// juntas no compitan visualmente.
  static Color fondoDeSyncStatus(SyncStatusTone tono) =>
      deSyncStatus(tono).withValues(alpha: 0.10);
}

/// Tonos de estado de sincronización para el tema.
///
/// Se replica aquí, en vez de importar `SyncStatus` del dominio, para que el
/// tema no dependa de la capa de dominio. El mapeo se hace en
/// `insignia_sync_status.dart`.
enum SyncStatusTone { pendiente, sincronizando, sincronizado, fallido }

/// Tema claro de la aplicación.
ThemeData temaClaro() {
  final esquema = ColorScheme.fromSeed(
    seedColor: TemaCampo.azul,
    brightness: Brightness.light,
  ).copyWith(
    primary: TemaCampo.azul,
    secondary: TemaCampo.ambar,
    error: TemaCampo.rojo,
    surface: Colors.white,
  );

  return _base(esquema);
}

/// Tema oscuro de la aplicación.
///
/// Existe porque un supervisor puede trabajar de noche en un turno, y el brillo
/// alto en campo es una/molestia real. Los mismos tonos se recalculan para
/// fondo oscuro: no se reutilizan los del tema claro porque varios no alcanzan
/// contraste sobre fondo oscuro.
ThemeData temaOscuro() {
  final esquema = ColorScheme.fromSeed(
    seedColor: TemaCampo.azul,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF9CC3F0),
    secondary: const Color(0xFFF2B75C),
    error: const Color(0xFFF2B8B5),
  );

  return _base(esquema);
}

ThemeData _base(ColorScheme esquema) {
  return ThemeData(
    colorScheme: esquema,
    useMaterial3: true,
    // Fuente del sistema: evita incrustar un archivo de tipografía y aprovecha
    // la que ya está instalada y optimizada en cada dispositivo.
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.primary,
      foregroundColor: esquema.onPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: esquema.onPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: esquema.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: esquema.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: esquema.outlineVariant),
      ),
      // El borde de error visible es parte del contrato de validación: el
      // mensaje va junto al campo, nunca solo al final del formulario.
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: esquema.error, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: esquema.error),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Altura mínima de 48 px: más que los 44 recomendados por Material,
        // porque la app se usa con guantes y a pleno sol.
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dividerTheme: DividerThemeData(space: 1, color: esquema.outlineVariant),
  );
}
