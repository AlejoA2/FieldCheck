import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ahora = DateTime.utc(2026, 3, 10, 14);

  SyncQueueItem construirItem({
    String id = 'q-1',
    int intentos = 0,
    DateTime? proximoIntentoAt,
    SyncStatus estado = SyncStatus.pendiente,
    List<String> rutas = const [],
  }) => SyncQueueItem(
    id: id,
    entidad: TipoEntidad.visita,
    entidadId: 'v-1',
    payload: const {'id': 'v-1', 'estado': 'en_progreso'},
    creadoAt: ahora,
    intentos: intentos,
    proximoIntentoAt: proximoIntentoAt,
    estado: estado,
    rutasArchivosLocales: rutas,
  );

  group('Serialización', () {
    test('sobrevive a un viaje completo por Map', () {
      final original = construirItem(
        intentos: 3,
        proximoIntentoAt: ahora.add(const Duration(minutes: 8)),
        rutas: const ['/tmp/foto1.jpg'],
      );

      final restaurado = SyncQueueItem.fromMap(original.toMap());

      expect(restaurado.id, original.id);
      expect(restaurado.entidad, TipoEntidad.visita);
      expect(restaurado.entidadId, 'v-1');
      expect(restaurado.payload['estado'], 'en_progreso');
      expect(restaurado.intentos, 3);
      expect(restaurado.proximoIntentoAt, ahora.add(const Duration(minutes: 8)));
      expect(restaurado.rutasArchivosLocales, ['/tmp/foto1.jpg']);
    });

    test('tolera un item con campos ausentes', () {
      final restaurado = SyncQueueItem.fromMap(const {'id': 'q-x'});

      expect(restaurado.id, 'q-x');
      expect(restaurado.estado, SyncStatus.pendiente);
      expect(restaurado.intentos, 0);
      expect(restaurado.rutasArchivosLocales, isEmpty);
    });

    test('conserva `payload` como mapa mutable', () {
      final original = construirItem();
      final mapa = original.toMap();
      mapa['payload'] = <String, dynamic>{'id': 'otro'};

      expect(SyncQueueItem.fromMap(mapa).payload['id'], 'otro');
    });
  });

  group('Control de reintentos', () {
    test('sin proximoIntentoAt, siempre puede intentarse', () {
      expect(construirItem().puedeIntentarEn(ahora), isTrue);
    });

    test('antes del backoff, no puede intentarse', () {
      final item = construirItem(
        proximoIntentoAt: ahora.add(const Duration(seconds: 30)),
      );

      expect(item.puedeIntentarEn(ahora), isFalse);
    });

    test('justo en el instante del backoff, ya puede', () {
      final item = construirItem(
        proximoIntentoAt: ahora.add(const Duration(seconds: 30)),
      );

      expect(item.puedeIntentarEn(ahora.add(const Duration(seconds: 30))), isTrue);
    });

    test('copyWith puede limpiar el error previo', () {
      final conError = construirItem().copyWith(ultimoError: 'falló');
      expect(conError.ultimoError, 'falló');

      final limpio = conError.copyWith(limpiarError: true);
      expect(limpio.ultimoError, isNull);
    });

    test('solo fallido requiere intervención manual', () {
      expect(construirItem().requiereIntervencionManual, isFalse);
      expect(
        construirItem(estado: SyncStatus.fallido).requiereIntervencionManual,
        isTrue,
      );
      expect(construirItem(estado: SyncStatus.sincronizado).requiereSync, isFalse);
      expect(construirItem(estado: SyncStatus.sincronizando).requiereSync, isTrue);
    });

    test('detecta si el item tiene archivos que subir', () {
      expect(construirItem().tieneArchivos, isFalse);
      expect(construirItem(rutas: ['/tmp/a.jpg']).tieneArchivos, isTrue);
    });
  });

  group('BackoffPolicy', () {
    const politica = BackoffPolicy();
    const sinJitter = 0.5; // jitter neutro

    test('el primer fallo espera la espera inicial', () {
      expect(
        politica.esperaParaIntento(1, random: () => sinJitter),
        const Duration(seconds: 30),
      );
    });

    test('cada intento duplica la espera', () {
      expect(
        politica.esperaParaIntento(2, random: () => sinJitter),
        const Duration(seconds: 60),
      );
      expect(
        politica.esperaParaIntento(3, random: () => sinJitter),
        const Duration(minutes: 2),
      );
      expect(
        politica.esperaParaIntento(4, random: () => sinJitter),
        const Duration(minutes: 4),
      );
    });

    test('nunca supera la espera máxima', () {
      expect(
        politica.esperaParaIntento(50, random: () => sinJitter),
        const Duration(minutes: 30),
      );
    });

    test('el jitter dispersa pero mantiene la orden de magnitud', () {
      final minimo = politica.esperaParaIntento(2, random: () => 0.0);
      final maximo = politica.esperaParaIntento(2, random: () => 1.0);

      // ±20 % sobre 60 s: 48 s a 72 s.
      expect(minimo, const Duration(seconds: 48));
      expect(maximo, const Duration(seconds: 72));
      expect(minimo.inMilliseconds, lessThan(maximo.inMilliseconds));
    });

    test('el jitter no puede superar el tope', () {
      final espera = politica.esperaParaIntento(40, random: () => 1.0);

      expect(espera, const Duration(minutes: 30));
    });

    test('agota los intentos automáticos en el límite', () {
      expect(politica.agotoIntentos(7), isFalse);
      expect(politica.agotoIntentos(8), isTrue);
      expect(politica.agotoIntentos(9), isTrue);
    });

    test('una política más agresiva reintenta más rápido', () {
      const agresiva = BackoffPolicy(esperaInicial: Duration(seconds: 5));

      expect(
        agresiva.esperaParaIntento(1, random: () => sinJitter),
        const Duration(seconds: 5),
      );
    });
  });
}