/// Servicio de validación geográfica (geofencing).
///
/// Resuelve el primer problema del reto: comprobar que el supervisor
/// realmente se encontraba en el centro de costo. Solo depende de [CentroCosto]
/// y del punto reportado por el GPS, así que funciona sin conexión: la
/// validación ocurre en el dispositivo y el resultado viaja al servidor como
/// parte de la visita.
library;

import '../../core/utils/geo_utils.dart';
import '../models/centro_costo.dart';
import '../models/geo_point.dart';
import '../models/visita.dart';

class GeofenceService {
  const GeofenceService();

  /// Evalúa una posición contra el geofence de un centro de costo.
  ///
  /// Devuelve siempre un resultado (no lanza): la UI necesita mostrar
  /// "estás a X metros" incluso cuando la validación falla.
  ResultadoGeofence evaluar({
    required GeoPoint posicion,
    required CentroCosto centroCosto,
  }) {
    final distancia = distanciaMetros(
      latitud1: posicion.latitud,
      longitud1: posicion.longitud,
      latitud2: centroCosto.ubicacion.latitud,
      longitud2: centroCosto.ubicacion.longitud,
    );

    return ResultadoGeofence(
      dentroDelRadio: distancia <= centroCosto.radioToleranciaMetros,
      distanciaMetros: distancia,
      radioToleranciaMetros: centroCosto.radioToleranciaMetros,
    );
  }

  /// Evalúa la posición de un marcador de check-in o check-out ya construido.
  ResultadoGeofence evaluarMarcador({
    required MarcadorVisita marcador,
    required CentroCosto centroCosto,
  }) => evaluar(posicion: marcador.posicion, centroCosto: centroCosto);
}