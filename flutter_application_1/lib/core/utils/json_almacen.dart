/// Serialización a JSON para el almacén local.
///
/// ## Por qué JSON y no los objetos directo
///
/// Hive puede guardar `Map` y `List` directamente, pero cada elemento debe
/// pertenecer a los adaptadores registrados. Los mapas del dominio son
/// heterogéneos (contienen listas de mapas, cadenas, números, `null`), y
/// escribirlos sinerializar exigiría un `TypeAdapter` generado por
/// `build_runner` para cada modelo. Guardar el JSON ya producido por
/// `toMap()` evita esa dependencia de generación de código y, de paso,
/// garantiza que el formato en disco coincide exactamente con el que se envía a
/// Firestore: una sola representación, no dos que puedan divergir.
///
/// El coste es `jsonEncode`/`jsonDecode` por registro, despreciable frente a la
/// foto que acompaña a cada visita.
library;

import 'dart:convert';

/// Convierte entre mapas del dominio y cadenas JSON para Hive.
abstract final class JsonAlmacen {
  /// Serializa un mapa a la cadena que se guarda en Hive.
  static String encode(Map<String, dynamic> mapa) => jsonEncode(mapa);

  /// Reconstruye el mapa desde la cadena de Hive.
  ///
  /// Devuelve `null` si el contenido está corrupto, en lugar de propagar el
  /// error: un registro ilegible no debe impedir que la app arranque y deje ver
  /// el resto de los datos.
  static Map<String, dynamic>? decode(Object? bruto) {
    if (bruto is Map) return Map<String, dynamic>.from(bruto);
    if (bruto is! String) return null;
    try {
      final decodificado = jsonDecode(bruto);
      if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      return null;
    } catch (_) {
      return null;
    }
  }
}
