import 'package:fieldcheck/domain/models/centro_costo.dart';
import 'package:fieldcheck/domain/models/geo_point.dart';
import 'package:fieldcheck/domain/services/geofence_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Centro de costo de referencia: Torre de Columbus, Bogotá.
const _centro = CentroCosto(
  id: 'cc-1',
  nombre: 'Torre de Columbus',
  ubicacion: GeoPoint(4.7110, -74.0721),
  radioToleranciaMetros: 100,
);

void main() {
  const servicio = GeofenceService();

  group('GeofenceService', () {
    test('acepta una posición dentro del radio', () {
      // ~0.0005 grados de latitud ≈ 55 m al norte.
      final resultado = servicio.evaluar(
        posicion: const GeoPoint(4.7115, -74.0721),
        centroCosto: _centro,
      );

      expect(resultado.dentroDelRadio, isTrue);
      expect(resultado.distanciaMetros, lessThan(100));
      expect(resultado.margenMetros, greaterThan(0));
      expect(resultado.mensaje, 'Ubicación verificada');
    });

    test('rechaza una posición fuera del radio', () {
      // ~0.003 grados ≈ 333 m al norte.
      final resultado = servicio.evaluar(
        posicion: const GeoPoint(4.7140, -74.0721),
        centroCosto: _centro,
      );

      expect(resultado.dentroDelRadio, isFalse);
      expect(resultado.distanciaMetros, greaterThan(100));
      expect(resultado.margenMetros, lessThan(0));
      expect(resultado.mensaje, contains('fuera del radio válido'));
    });

    test('acepta exactamente en el borde del radio', () {
      // Un grado de latitud son 111194.9 m; 100 m son 0.000899 grados.
      final resultado = servicio.evaluar(
        posicion: const GeoPoint(4.7110 + 0.000899, -74.0721),
        centroCosto: _centro,
      );

      // El borde es inclusivo; una diferencia de un metro por redondeo no
      // debe rechazar la visita.
      expect(resultado.distanciaMetros, closeTo(100, 1.5));
      expect(resultado.dentroDelRadio, isTrue);
    });

    test('respeta un radio de tolerancia mayor', () {
      final centroAmplio = _centro.copyWith(radioToleranciaMetros: 500);
      const posicion = GeoPoint(4.7140, -74.0721); // ~333 m

      expect(
        servicio.evaluar(posicion: posicion, centroCosto: centroAmplio)
            .dentroDelRadio,
        isTrue,
      );
    });

    test('un radio de cero solo acepta la coincidencia exacta', () {
      final centroExacto = _centro.copyWith(radioToleranciaMetros: 0);

      final resultado = servicio.evaluar(
        posicion: _centro.ubicacion,
        centroCosto: centroExacto,
      );

      expect(resultado.dentroDelRadio, isTrue);
      expect(resultado.distanciaMetros, 0);
    });

    test('el mensaje de error indica cuánto falta', () {
      final resultado = servicio.evaluar(
        posicion: const GeoPoint(4.7140, -74.0721),
        centroCosto: _centro,
      );

      // 0.003° de latitud ≈ 333.6 m, que se redondea a 334.
      expect(resultado.mensaje, contains('334 m'));
      expect(resultado.mensaje, contains('100 m'));
      expect(resultado.mensaje, isNot(contains('.0')));
    });
  });
}