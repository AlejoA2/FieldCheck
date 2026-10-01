/// Apertura y nombre de las cajas de Hive.
///
/// Se centraliza aquí para que ningún otro archivo tenga que recordar el nombre
/// exacto de una caja: un error en el nombre crearía una caja vacía en
/// silencio, que es la peor forma de fallar en un almacén local.
library;

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/error/app_exception.dart';

/// Nombres de las cajas. Siempre en minúsculas: Hive exige ese nombre.
abstract final class Cajas {
  /// Cola de sincronización pendiente.
  static const String colaSync = 'cola_sync';

  /// Visitas (caché de campo).
  static const String visitas = 'visitas';

  /// Evidencias (caché de campo).
  static const String evidencias = 'evidencias';

  /// Novedades (caché de campo).
  static const String novedades = 'novedades';

  /// Centros de costo (caché de solo lectura).
  static const String centrosCosto = 'centros_costo';

  /// Todos los nombres, para abrir y cerrar en un solo punto.
  static const List<String> todas = [
    colaSync,
    visitas,
    evidencias,
    novedades,
    centrosCosto,
  ];
}

/// Inicializa Hive y abre todas las cajas de la aplicación.
///
/// Falla con [LocalStorageException] si Hive no puede inicializarse, para que
/// el error llegue a la capa superior ya como excepción de la aplicación y no
/// como un error técnico crudo.
Future<void> inicializarAlmacenamientoLocal() async {
  try {
    await Hive.initFlutter();
  } catch (e, s) {
    throw LocalStorageException(
      'No se pudo preparar el almacenamiento local del dispositivo.',
      cause: e,
      stackTrace: s,
    );
  }

  for (final nombre in Cajas.todas) {
    if (Hive.isBoxOpen(nombre)) continue;
    await Hive.openBox<dynamic>(nombre);
  }
}

/// Cierra todas las cajas abiertas.
Future<void> cerrarCajas() async {
  for (final nombre in Cajas.todas) {
    if (Hive.isBoxOpen(nombre)) {
      await Hive.box<dynamic>(nombre).close();
    }
  }
}

/// Devuelve una caja abierta, o lanza [LocalStorageException] si no lo está.
///
/// Evita el error crudo de Hive ("Box not found") y lo convierte en una
/// excepción con mensaje apto para la UI.
Box<dynamic> caja(String nombre) {
  if (!Hive.isBoxOpen(nombre)) {
    throw const LocalStorageException(
      'El almacenamiento local no está disponible en este momento.',
    );
  }
  return Hive.box<dynamic>(nombre);
}
