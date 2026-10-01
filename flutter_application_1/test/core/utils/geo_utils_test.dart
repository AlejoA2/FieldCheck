import 'package:fieldcheck/core/utils/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distanciaMetros', () {
    test('un grado de longitud en el ecuador son ~111.19 km', () {
      final d = distanciaMetros(
        latitud1: 0,
        longitud1: 0,
        latitud2: 0,
        longitud2: 1,
      );

      expect(d, closeTo(111194.9, 1));
    });

    test('un grado de latitud es ~111.19 km en cualquier lugar', () {
      final d = distanciaMetros(
        latitud1: 45,
        longitud1: 0,
        latitud2: 46,
        longitud2: 0,
      );

      expect(d, closeTo(111194.9, 1));
    });

    test('el mismo punto tiene distancia cero', () {
      final d = distanciaMetros(
        latitud1: 4.7110,
        longitud1: -74.0721,
        latitud2: 4.7110,
        longitud2: -74.0721,
      );

      expect(d, 0);
    });

    test('es simétrica', () {
      final a = distanciaMetros(
        latitud1: 4.7110,
        longitud1: -74.0721,
        latitud2: 6.2442,
        longitud2: -75.5812,
      );
      final b = distanciaMetros(
        latitud1: 6.2442,
        longitud1: -75.5812,
        latitud2: 4.7110,
        longitud2: -74.0721,
      );

      expect(a, closeTo(b, 0.0001));
    });

    test('Bogotá a Medellín son ~239 km de distancia aérea (great-circle)', () {
      final d = distanciaMetros(
        latitud1: 4.7110,
        longitud1: -74.0721,
        latitud2: 6.2442,
        longitud2: -75.5812,
      );

      // OJO: esta es la distancia en línea recta (lo que calcula Haversine), no
      // la ruta por carretera (~385 km). El geofence compara en línea recta.
      expect(d, closeTo(238675, 100));
    });

    test('antipodales: la mitad de la circunferencia terrestre', () {
      final d = distanciaMetros(
        latitud1: 0,
        longitud1: 0,
        latitud2: 0,
        longitud2: 180,
      );

      // Tolerancia amplia: en el punto antipodal la fórmula de Haversine pierde
      // precisión por el `atan2` cerca de asin(1). El error relativo (~1e-6) es
      // irrelevante para geofencing, donde los radios son de decenas de metros.
      expect(d, closeTo(20015114, 50));
    });

    test('rechaza latitudes fuera de rango', () {
      expect(
        () => distanciaMetros(
          latitud1: 91,
          longitud1: 0,
          latitud2: 0,
          longitud2: 0,
        ),
        throwsRangeError,
      );
    });

    test('rechaza longitudes fuera de rango', () {
      expect(
        () => distanciaMetros(
          latitud1: 0,
          longitud1: 181,
          latitud2: 0,
          longitud2: 0,
        ),
        throwsRangeError,
      );
    });

    test('rechaza NaN', () {
      expect(
        () => distanciaMetros(
          latitud1: double.nan,
          longitud1: 0,
          latitud2: 0,
          longitud2: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('formatearDistancia', () {
    test('usa metros por debajo de 1 km', () {
      expect(formatearDistancia(84.4), '84 m');
    });

    test('usa kilómetros por encima de 1 km', () {
      expect(formatearDistancia(15400), '15.40 km');
    });

    test('maneja valores no finitos sin romperse', () {
      expect(formatearDistancia(double.nan), 'distancia desconocida');
    });
  });
}