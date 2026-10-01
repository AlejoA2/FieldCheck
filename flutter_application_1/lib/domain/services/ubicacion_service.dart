/// Contrato del servicio de ubicación del dispositivo.
///
/// ## Por qué es una interfaz y no una llamada directa a `geolocator`
///
/// Toda la lógica de geofencing ya es testeable sin Firebase ([GeofenceService]),
/// pero el punto que la alimenta —obtener la posición del GPS— es un plugin del
/// sistema, con permisos y timeouts que no existen en un test.
///
/// Aislarlo detrás de un contrato permite que los ViewModel de campo se
/// prueben con una posición fija, y concentra en una sola implementación todo lo
/// que puede fallar por permisos, GPS apagado o señal débil.
///
/// ## Por qué devuelve un resultado sellado y no una excepción
///
/// No obtener una posición es un caso **esperado** en campo: dentro de un túnel,
/// con el GPS apagado, o simplemente sin cobertura. Si eso fuera una excepción,
/// cada pantalla tendría querodearla y el mensaje técnico terminaría filtrándose
/// a la UI.
///
/// Con [LecturaPosicion] hay dos desenlaces explícitos y cada motivo lleva su
/// propia sugerencia para el supervisor, sin detalle técnico del plugin.
///
/// ## Por qué NO usa `GeoPoint` de Firebase
///
/// El dominio define su propio `GeoPoint` con unidades neutras. `geolocator`
/// devuelve grados y una precisión en metros que esta capa descarta: el
/// repositorio no debe conocer el plugin.
library;

import '../models/geo_point.dart';

/// Resultado de intentar leer la posición del dispositivo.
sealed class LecturaPosicion {
  const LecturaPosicion();

  /// `true` si se obtuvo una posición usable.
  bool get tienePosicion => this is PosicionObtenida;

  /// Devuelve la posición, o `null` si no se pudo obtener.
  ///
  /// Permite a la UI hacer `final posicion = lectura.posicion; if (posicion !=
  /// null) ...` sin un `switch` sobre el tipo sellado.
  GeoPoint? get posicion => switch (this) {
    PosicionObtenida(:final valor) => valor,
    PosicionNoObtenida() => null,
  };
}

/// Posición leída correctamente.
final class PosicionObtenida extends LecturaPosicion {
  const PosicionObtenida(this.valor);

  final GeoPoint valor;
}

/// No se pudo obtener la posición, por una razón conocida.
final class PosicionNoObtenida extends LecturaPosicion {
  const PosicionNoObtenida(this.motivo, {this.sugerencia});

  /// Motivo legible, sin detalle técnico del plugin.
  final String motivo;

  /// Acción sugerida al supervisor, si la hay.
  final String? sugerencia;
}

/// Fuente de la posición del supervisor en el dispositivo.
abstract class UbicacionService {
  /// Intenta leer la posición actual.
  ///
  /// Nunca lanza: cualquier fallo se traduce a [PosicionNoObtenida] con un
  /// mensaje apto para mostrar.
  Future<LecturaPosicion> leerPosicion();
}

/// Modo de captura de imágenes para evidencias.
///
/// ## Restricción del reto
///
/// Solo [CapturaFoto.fotografiar]. No se ofrece elegir de la galería: una foto
/// de la galería puede ser de otro día o de otro lugar, y el valor del reto es
/// probar que el supervisor estuvo en el centro de costo. La enumeración existe
/// para dejar el límite explícito en el código, y no como una puerta abierta a
/// "elegir archivo" más adelante.
enum CapturaFoto {
  /// Toma una foto nueva con la cámara.
  fotografiar,
}

/// Contrato de captura de fotografías.
abstract class CamaraService {
  /// Abre la cámara y devuelve la ruta local del archivo, o `null` si el
  /// supervisor canceló.
  Future<String?> capturar(CapturaFoto modo);
}
