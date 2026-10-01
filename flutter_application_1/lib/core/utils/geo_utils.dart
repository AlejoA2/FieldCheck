/// Utilidades geográficas puras (sin dependencias de Flutter ni de Firebase).
///
/// Se mantienen en el dominio para poder testearlas de forma aislada y para
/// que la lógica de validación de visita no dependa de la capa de datos.
library;

import 'dart:math' as math;

/// Radio medio de la Tierra en metros (IUGN). Suficiente para precisión de
/// geofencing (~0,5 % de error, irrelevante frente a radios de 50-200 m).
const double _radioTierraMetros = 6371008.8;

/// Distancia en metros entre dos puntos geográficos usando la fórmula de Haversine.
///
/// Devuelve la distancia de superficie (great-circle). Para validar que un
/// supervisor está dentro de un centro de costo esto es más que suficiente y
/// evita depender de un servicio de mapas externo (que fallaría sin conexión).
///
/// Referencias:
///  - [Haversine](https://en.wikipedia.org/wiki/Haversine_formula)
double distanciaMetros({
  required double latitud1,
  required double longitud1,
  required double latitud2,
  required double longitud2,
}) {
  _assertCoordenadaValida(latitud1, longitud1, 'latitud1/longitud1');
  _assertCoordenadaValida(latitud2, longitud2, 'latitud2/longitud2');

  final lat1 = _aRadianes(latitud1);
  final lat2 = _aRadianes(latitud2);
  final deltaLat = _aRadianes(latitud2 - latitud1);
  final deltaLng = _aRadianes(longitud2 - longitud1);

  final a =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLng / 2), 2);

  // clamp evita valores ligeramente > 1 por error de punto flotante, que
  // harían que sqrt() devolviera NaN.
  final c = 2 * math.atan2(math.sqrt(a.clamp(0.0, 1.0)), math.sqrt(1 - a.clamp(0.0, 1.0)));

  return _radioTierraMetros * c;
}

/// Convierte una distancia en metros a una descripción legible para el usuario.
String formatearDistancia(double metros) {
  if (!metros.isFinite || metros < 0) return 'distancia desconocida';
  if (metros < 1000) return '${metros.round()} m';
  return '${(metros / 1000).toStringAsFixed(2)} km';
}

double _aRadianes(double grados) => grados * math.pi / 180.0;

void _assertCoordenadaValida(double latitud, double longitud, String nombres) {
  if (latitud.isNaN || longitud.isNaN) {
    throw ArgumentError('$nombres no puede ser NaN');
  }
  if (latitud < -90 || latitud > 90) {
    throw RangeError.range(latitud, -90, 90, nombres);
  }
  if (longitud < -180 || longitud > 180) {
    throw RangeError.range(longitud, -180, 180, nombres);
  }
}