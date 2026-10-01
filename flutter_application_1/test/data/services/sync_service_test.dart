import 'package:fieldcheck/core/utils/clock.dart';
import 'package:fieldcheck/data/services/sync_service.dart';
import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSyncQueueStore cola;
  late FakeRemoteSyncGateway gateway;
  late FakeEvidenceUploader evidencia;
  late FakeConnectivityService conectividad;
  late FakeClock reloj;
  late SyncService servicio;

  final inicio = DateTime.utc(2026, 3, 10, 14);

  SyncQueueItem item({
    String id = 'q-1',
    TipoEntidad entidad = TipoEntidad.visita,
    DateTime? creadoAt,
    SyncOperacion operacion = SyncOperacion.upsert,
    int intentos = 0,
    DateTime? proximoIntentoAt,
    SyncStatus estado = SyncStatus.pendiente,
    List<String> rutas = const [],
    Map<String, dynamic> payload = const {'id': 'ent-q-1'},
  }) => SyncQueueItem(
    id: id,
    entidad: entidad,
    entidadId: 'ent-$id',
    payload: payload,
    creadoAt: creadoAt ?? inicio,
    operacion: operacion,
    intentos: intentos,
    proximoIntentoAt: proximoIntentoAt,
    estado: estado,
    rutasArchivosLocales: rutas,
  );

  setUp(() {
    cola = FakeSyncQueueStore();
    gateway = FakeRemoteSyncGateway();
    evidencia = FakeEvidenceUploader();
    conectividad = FakeConnectivityService();
    reloj = FakeClock(inicio);

    servicio = SyncService(
      cola: cola,
      gateway: gateway,
      evidencia: evidencia,
      conectividad: conectividad,
      // Jitter neutro: las esperas son predecibles.
      random: () => 0.5,
      clock: reloj,
    );
  });

  tearDown(() async {
    await servicio.dispose();
    await conectividad.cerrar();
  });

  group('Drenaje de la cola', () {
    test('sincroniza un item pendiente y lo elimina de la cola', () async {
      await cola.encolar(item());

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.sincronizados, 1);
      expect(resultado.fallidos, 0);
      expect(resultado.huboRed, isTrue);
      expect(await cola.contarPendientes(), 0);
      expect(gateway.existe(TipoEntidad.visita, 'q-1'), isTrue);
    });

    test('escribe usando el id del item como ID de documento (idempotencia)', () async {
      await cola.encolar(item(id: 'uuid-fijo'));

      await servicio.sincronizarAhora();

      expect(gateway.escrituras, ['upsert:visitas/uuid-fijo']);
      expect(gateway.documentos['visitas']!.containsKey('uuid-fijo'), isTrue);
    });

    test('reintentar el mismo item sobrescribe, no duplica', () async {
      await cola.encolar(item(id: 'q-1'));

      // Se fuerza un fallo tras escribir, simulando una muerte de proceso antes
      // de borrar el item de la cola.
      gateway.fallosRestantes = 0;
      await servicio.sincronizarAhora();
      expect(await cola.contarPendientes(), 0);

      // Se reencola el mismo id (por ejemplo, una edición posterior que el
      // servidor ya tenía).
      await cola.encolar(item(id: 'q-1'));
      await servicio.sincronizarAhora();

      expect(gateway.documentos['visitas'], hasLength(1));
    });

    test('procesa varios items en orden FIFO', () async {
      await cola.encolar(item(id: 'b', creadoAt: inicio.add(const Duration(minutes: 2))));
      await cola.encolar(item(id: 'a', creadoAt: inicio));
      await cola.encolar(item(id: 'c', creadoAt: inicio.add(const Duration(minutes: 1))));

      await servicio.sincronizarAhora();

      expect(gateway.escrituras, [
        'upsert:visitas/a',
        'upsert:visitas/c',
        'upsert:visitas/b',
      ]);
    });

    test('un item ya sincronizado no se vuelve a enviar', () async {
      await cola.encolar(item(estado: SyncStatus.sincronizado));

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.sincronizados, 0);
      expect(gateway.escrituras, isEmpty);
    });

    test('soporta la operación eliminar, que es idempotente', () async {
      await cola.encolar(item(operacion: SyncOperacion.eliminar));

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.sincronizados, 1);
      expect(gateway.escrituras, ['eliminar:visitas/q-1']);
      expect(await cola.contarPendientes(), 0);
    });

    test('escribe en la colección correcta según el tipo de entidad', () async {
      await cola.encolar(item(id: 'q-n', entidad: TipoEntidad.novedad));
      await cola.encolar(item(id: 'q-e', entidad: TipoEntidad.evidencia));

      await servicio.sincronizarAhora();

      expect(gateway.existe(TipoEntidad.novedad, 'q-n'), isTrue);
      expect(gateway.existe(TipoEntidad.evidencia, 'q-e'), isTrue);
    });
  });

  group('Sin conexión', () {
    test('no intenta nada y conserva la cola intacta', () async {
      await cola.encolar(item());
      conectividad.conectado = false;

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.huboRed, isFalse);
      expect(resultado.sincronizados, 0);
      expect(gateway.escrituras, isEmpty);
      expect(await cola.contarPendientes(), 1);
    });

    test('el estado reporta que no hay conexión', () async {
      conectividad.conectado = false;

      await servicio.sincronizarAhora();

      expect(servicio.estadoActual.hayConexion, isFalse);
    });
  });

  group('Manejo de fallos', () {
    test('un fallo conserva el item en la cola (nada se pierde)', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = StateError('sin red');

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.fallidos, 1);
      expect(resultado.sincronizados, 0);
      expect(await cola.contarPendientes(), 1);
    });

    test('un item fallido queda pendiente con backoff aplicado', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = StateError('sin red');

      await servicio.sincronizarAhora();

      final fallido = cola.items['q-1']!;
      expect(fallido.intentos, 1);
      expect(fallido.estado, SyncStatus.pendiente);
      expect(fallido.proximoIntentoAt, inicio.add(const Duration(seconds: 30)));
    });

    test('el backoff impide reintentar antes de tiempo', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = StateError('sin red');
      await servicio.sincronizarAhora();

      gateway.errorAlEscribir = null;
      final resultado = await servicio.sincronizarAhora();

      expect(resultado.omitidos, 1);
      expect(resultado.sincronizados, 0);
      expect(gateway.escrituras, isEmpty);
    });

    test('pasada la espera de backoff, reintenta y tiene éxito', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = StateError('sin red');
      await servicio.sincronizarAhora();

      reloj.avanzar(const Duration(seconds: 31));
      gateway.errorAlEscribir = null;

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.sincronizados, 1);
      expect(await cola.contarPendientes(), 0);
    });

    test('el error expuesto al usuario no filtra detalle técnico', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = StateError(
        'SocketException: Failed host lookup: firestore.googleapis.com',
      );

      await servicio.sincronizarAhora();

      final error = cola.items['q-1']!.ultimoError!;
      expect(error, contains('Sin conexión'));
      expect(error, isNot(contains('SocketException')));
      expect(error, isNot(contains('firestore.googleapis.com')));
    });

    test('un fallo de red se reporta como "sin conexión"', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = Exception('Firebase network error');

      await servicio.sincronizarAhora();

      expect(cola.items['q-1']!.ultimoError, contains('Sin conexión'));
    });

    test('un fallo ajeno a la red no promete reconexión', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = Exception('permiso denegado');

      await servicio.sincronizarAhora();

      expect(
        cola.items['q-1']!.ultimoError,
        'No se pudo sincronizar. Se reintentará automáticamente.',
      );
    });

    test('un item que falla no detiene a los demás', () async {
      await cola.encolar(item(id: 'a'));
      await cola.encolar(
        item(id: 'b', creadoAt: inicio.add(const Duration(seconds: 1))),
      );

      // El primer item falla una sola vez; el segundo se procesa igual.
      gateway.fallosRestantes = 1;

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.sincronizados, 1, reason: 'el segundo item sí se sube');
      expect(resultado.fallidos, 1, reason: 'el primero falló');
      expect(await cola.contarPendientes(), 1, reason: 'solo queda el fallido');
      expect(gateway.existe(TipoEntidad.visita, 'b'), isTrue);
      expect(gateway.existe(TipoEntidad.visita, 'a'), isFalse);
    });

    test('tras agotar los reintentos el item queda en estado fallido', () async {
      const maxIntentos = 8;
      var ultimo = item();
      for (var i = 0; i < maxIntentos; i++) {
        ultimo = ultimo.copyWith(intentos: i);
      }
      await cola.encolar(
        item(
          intentos: maxIntentos - 1,
          estado: SyncStatus.pendiente,
        ),
      );
      gateway.errorAlEscribir = StateError('sin red');

      await servicio.sincronizarAhora();

      expect(cola.items['q-1']!.intentos, maxIntentos);
      expect(cola.items['q-1']!.estado, SyncStatus.fallido);
      expect(cola.items['q-1']!.proximoIntentoAt, isNull);
      expect(cola.items['q-1']!.requiereIntervencionManual, isTrue);
    });
  });

  group('Reintento manual', () {
    test('resetea los intentos y vuelve a subir', () async {
      await cola.encolar(item(intentos: 8, estado: SyncStatus.fallido));

      await servicio.reintentarManualmente('q-1');

      expect(await cola.contarPendientes(), 0);
      expect(gateway.existe(TipoEntidad.visita, 'q-1'), isTrue);
    });

    test('no hace nada si el item no existe', () async {
      await servicio.reintentarManualmente('no-existe');

      expect(gateway.escrituras, isEmpty);
    });
  });

  group('Evidencias', () {
    test('sube el archivo antes de escribir el documento', () async {
      await cola.encolar(item(rutas: const ['/tmp/foto.jpg']));

      await servicio.sincronizarAhora();

      expect(evidencia.subidas, hasLength(1));
      expect(evidencia.subidas.first, contains('ent-q-1'));
      expect(evidencia.subidas.first, endsWith('foto.jpg'));
    });

    test('el documento enviado lleva la URL, no la ruta local', () async {
      await cola.encolar(
        item(
          rutas: const ['/tmp/foto.jpg'],
          payload: {
            'id': 'ent-q-1',
            'evidencias': [
              {'id': 'e-1', 'rutaLocal': '/tmp/foto.jpg'},
            ],
          },
        ),
      );

      await servicio.sincronizarAhora();

      final enviado = gateway.documentos['visitas']!['q-1']!;
      final foto = Map<String, dynamic>.from(
        (enviado['evidencias'] as List<dynamic>).first as Map,
      );
      expect(foto['urlRemota'], startsWith('https://fake.storage/'));
      expect(foto.containsKey('rutaLocal'), isFalse);
    });

    test('limpia los archivos locales solo tras confirmar la subida', () async {
      await cola.encolar(item(rutas: const ['/tmp/foto.jpg']));

      await servicio.sincronizarAhora();

      expect(evidencia.rutasLocalesLimpias, ['/tmp/foto.jpg']);
    });

    test('no borra el archivo local si la escritura falla', () async {
      await cola.encolar(item(rutas: const ['/tmp/foto.jpg']));
      gateway.errorAlEscribir = StateError('sin red');

      await servicio.sincronizarAhora();

      expect(evidencia.rutasLocalesLimpias, isEmpty);
      expect(await cola.contarPendientes(), 1);
    });

    test('conserva la URL ya subida y no vuelve a subir el archivo', () async {
      await cola.encolar(item(rutas: const ['/tmp/foto.jpg']));
      gateway.errorAlEscribir = StateError('sin red');
      await servicio.sincronizarAhora();

      // Primer reintento: el archivo sí se sube (aún no se había subido).
      evidencia.subidas.clear();
      reloj.avanzar(const Duration(seconds: 31));
      gateway.errorAlEscribir = StateError('sin red');
      await servicio.sincronizarAhora();

      // La URL quedó registrada en el item, así que el segundo reintento no
      // vuelve a gastar ancho de banda subiendo la misma foto.
      evidencia.subidas.clear();
      reloj.avanzar(const Duration(minutes: 2));
      gateway.errorAlEscribir = null;
      await servicio.sincronizarAhora();

      expect(evidencia.subidas, isEmpty);
      expect(await cola.contarPendientes(), 0);
    });
  });

  group('Escucha de red', () {
    test('sincroniza automáticamente al recuperar la conexión', () async {
      await cola.encolar(item());

      servicio.iniciarEscuchaDeRed();
      conectividad.emitir(false);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.escrituras, isEmpty);

      conectividad.emitir(true);
      // Dos vueltas del event loop para que el listener asíncrono termine.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.existe(TipoEntidad.visita, 'q-1'), isTrue);
    });

    test('es idempotente: llamar dos veces no duplica suscripciones', () async {
      servicio.iniciarEscuchaDeRed();
      servicio.iniciarEscuchaDeRed();
      servicio.iniciarEscuchaDeRed();

      await cola.encolar(item());
      conectividad.emitir(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.escrituras, hasLength(1));
    });
  });

  group('Concurrencia', () {
    test('una sincronización en curso no se solapa consigo misma', () async {
      await cola.encolar(item());

      // Dos llamadas simultáneas: la segunda debe ser no-op.
      final resultados = await Future.wait([
        servicio.sincronizarAhora(),
        servicio.sincronizarAhora(),
      ]);

      // Solo una pasada efectiva: una sola escritura.
      expect(gateway.escrituras, hasLength(1));
      expect(
        resultados.where((r) => r.sincronizados == 1),
        hasLength(1),
      );
    });

    test('un fallo inesperado no deja el servicio colgado', () async {
      await cola.encolar(item());
      conectividad.errorAlConsultar = StateError('boom');

      final resultado = await servicio.sincronizarAhora();

      expect(resultado.fallidos, 1);
      expect(servicio.estadoActual.enEjecucion, isFalse);

      // Y sigue funcionando al normalizarse la siguiente llamada.
      conectividad.errorAlConsultar = null;
      await servicio.sincronizarAhora();
      expect(await cola.contarPendientes(), 0);
    });
  });

  group('Observabilidad', () {
    test('el estado refleja los pendientes y los exitosos', () async {
      await cola.encolar(item(id: 'a'));
      await cola.encolar(item(id: 'b', creadoAt: inicio.add(const Duration(seconds: 1))));

      await servicio.sincronizarAhora();

      expect(servicio.estadoActual.pendientes, 0);
      expect(servicio.estadoActual.procesadosEnUltimaEjecucion, 2);
      expect(servicio.estadoActual.enEjecucion, isFalse);
    });

    test('el estado marca que requiere atención si quedan fallidos', () async {
      await cola.encolar(item());
      gateway.errorAlEscribir = StateError('sin red');

      await servicio.sincronizarAhora();

      expect(servicio.estadoActual.fallidosEnUltimaEjecucion, 1);
      expect(servicio.estadoActual.requiereAtencion, isTrue);
    });

    test('el stream de estado emite durante la sincronización', () async {
      await cola.encolar(item());

      final eventos = <EstadoSync>[];
      final suscripcion = servicio.obtenerEstado().listen(eventos.add);

      await servicio.sincronizarAhora();
      await Future<void>.delayed(Duration.zero);
      await suscripcion.cancel();

      expect(eventos, isNotEmpty);
      expect(eventos.any((e) => e.enEjecucion), isTrue);
    });
  });
}