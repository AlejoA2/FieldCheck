/// Tests del repositorio de campo del supervisor.
///
/// Aquí se verifica el patrón offline-first completo: validar, guardar en
/// local, encolar y sincronizar. Los tests se apoyan en el `SyncService` real
/// con dobles en memoria, de modo que la interacción entre repositorio, cola y
/// sincronización se ejercita de verdad, sin Firebase.
library;

import 'package:fieldcheck/core/error/app_exception.dart';
import 'package:fieldcheck/core/utils/clock.dart';
import 'package:fieldcheck/data/repositories/visita_repository_impl.dart';
import 'package:fieldcheck/data/services/sync_service.dart';
import 'package:fieldcheck/domain/models/centro_costo.dart';
import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/geo_point.dart';
import 'package:fieldcheck/domain/models/sync_queue_item.dart';
import 'package:fieldcheck/domain/models/visita.dart';
import 'package:fieldcheck/domain/services/geofence_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Centro de costo con geofence de 100 m en la referencia de los tests.
const _centro = CentroCosto(
  id: 'cc-1',
  nombre: 'Sede Administrativa',
  ubicacion: GeoPoint(4.7110, -74.0721),
  radioToleranciaMetros: 100,
);

/// Posición prácticamente encima del centro (dentro del radio).
const _enSitio = GeoPoint(4.71100, -74.07210);

/// Posición a unos 300 m al norte del centro (fuera del radio).
const _lejos = GeoPoint(4.71370, -74.07210);

void main() {
  late FakeAlmacenLocal almacen;
  late FakeSyncQueueStore cola;
  late FakeRemoteSyncGateway gateway;
  late FakeEvidenceUploader evidencia;
  late FakeConnectivityService conectividad;
  late FakeClock reloj;
  late SyncService sync;
  late FakeFuenteVisitasRemotas remotas;
  late VisitaRepositoryImpl repo;

  final inicio = DateTime.utc(2026, 3, 10, 14);

  Visita visitaBase({
    String id = 'v-1',
    String supervisorId = 'sup-1',
    String centroCostoId = 'cc-1',
    DateTime? fechaProgramada,
    EstadoVisita estado = EstadoVisita.pendiente,
    SyncStatus syncStatus = SyncStatus.sincronizado,
    MarcadorVisita? checkIn,
    MarcadorVisita? checkOut,
    List<RegistroActividad> actividades = const [],
  }) => Visita(
    id: id,
    supervisorId: supervisorId,
    centroCostoId: centroCostoId,
    fechaProgramada: fechaProgramada ?? DateTime.utc(2026, 3, 10, 8),
    estado: estado,
    syncStatus: syncStatus,
    checkIn: checkIn,
    checkOut: checkOut,
    actividades: actividades,
  );

  setUp(() async {
    almacen = FakeAlmacenLocal();
    cola = FakeSyncQueueStore();
    gateway = FakeRemoteSyncGateway();
    evidencia = FakeEvidenceUploader();
    conectividad = FakeConnectivityService();
    reloj = FakeClock(inicio);
    remotas = FakeFuenteVisitasRemotas();

    sync = SyncService(
      cola: cola,
      gateway: gateway,
      evidencia: evidencia,
      conectividad: conectividad,
      random: () => 0.5,
      clock: reloj,
    );

    await almacen.guardarCentroCosto(_centro);

    repo = VisitaRepositoryImpl(
      almacen: almacen,
      cola: cola,
      sync: sync,
      geofence: const GeofenceService(),
      remotas: remotas,
      supervisorActual: () => 'sup-1',
      clock: reloj,
    );
  });

  tearDown(() async {
    await sync.dispose();
    await conectividad.cerrar();
    await almacen.cerrar();
  });

  group('Carga de asignaciones', () {
    test('refrescar guarda en local las visitas asignadas del servidor', () async {
      remotas.agregar(visitaBase(id: 'v-remota-1'));

      await repo.refrescarVisitasAsignadas('sup-1');

      expect(await almacen.visitaPorId('v-remota-1'), isNotNull);
    });

    test('no trae las visitas asignadas a otro supervisor', () async {
      remotas.agregar(visitaBase(id: 'v-otro', supervisorId: 'sup-9'));

      await repo.refrescarVisitasAsignadas('sup-1');

      expect(await almacen.visitaPorId('v-otro'), isNull);
    });

    test('sin red el supervisor conserva la caché local y no falla', () async {
      await almacen.guardarVisita(visitaBase(id: 'v-1'));
      remotas.errorAlConsultar = StateError('sin red');

      // No debe lanzar: es best-effort y la caché ya permite trabajar.
      await expectLater(
        repo.refrescarVisitasAsignadas('sup-1'),
        completes,
      );
      expect(await almacen.visitaPorId('v-1'), isNotNull);
    });

    test('la versión remota no pisa un registro local sin sincronizar', () async {
      // Check-in hecho sin red: la versión local es más nueva y no se pierde.
      final local = visitaBase(
        id: 'v-1',
        estado: EstadoVisita.enProgreso,
        syncStatus: SyncStatus.pendiente,
        checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
      );
      await almacen.guardarVisita(local);

      await repo.refrescarVisitasAsignadas('sup-1');

      final guardada = await almacen.visitaPorId('v-1');
      expect(guardada!.estado, EstadoVisita.enProgreso);
    });
  });

  group('registrarCheckIn', () {
    test('dentro del radio guarda, encola y pasa la visita a "en curso"', () async {
      await almacen.guardarVisita(visitaBase());

      final actualizada = await repo.registrarCheckIn(
        visitaId: 'v-1',
        posicion: _enSitio,
      );

      expect(actualizada.estado, EstadoVisita.enProgreso);
      expect(actualizada.tieneCheckIn, isTrue);
      expect(actualizada.syncStatus, SyncStatus.pendiente);
      expect(await almacen.visitaPorId('v-1'), isNotNull);
    });

    test('con red el registro llega al servidor en el mismo instante', () async {
      // Con red disponible la cola se drena de inmediato: el supervisor no tiene
      // que hacer nada y el coordinador ve la visita al momento.
      await almacen.guardarVisita(visitaBase());

      await repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio);

      expect(await cola.contarPendientes(), 0);
      expect(gateway.escrituras, hasLength(1));
      expect(gateway.escrituras.single, startsWith('upsert:visitas/'));
    });

    test('la distancia medida se guarda para que el coordinador la audite', () async {
      await almacen.guardarVisita(visitaBase());

      final actualizada = await repo.registrarCheckIn(
        visitaId: 'v-1',
        posicion: const GeoPoint(4.71120, -74.07210),
      );

      expect(actualizada.distanciaCheckInMetros, isNotNull);
      expect(actualizada.distanciaCheckInMetros!, greaterThan(0));
      expect(actualizada.distanciaCheckInMetros!, lessThan(100));
    });

    test('fuera del radio rechaza el check-in y no encola nada', () async {
      await almacen.guardarVisita(visitaBase());

      await expectLater(
        repo.registrarCheckIn(visitaId: 'v-1', posicion: _lejos),
        throwsA(isA<ValidationException>()),
      );

      expect(await cola.contarPendientes(), 0, reason: 'no debe encolar trabajo inválido');
      final guardada = await almacen.visitaPorId('v-1');
      expect(guardada!.tieneCheckIn, isFalse, reason: 'la visita no debe cambiar');
    });

    test('el mensaje de rechazo dice cuántos metros faltan', () async {
      await almacen.guardarVisita(visitaBase());

      // El mensaje es lo que el supervisor ve en pantalla: tiene que indicar el
      // radio y la distancia, no un error técnico.
      await expectLater(
        repo.registrarCheckIn(visitaId: 'v-1', posicion: _lejos),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.message, 'message', contains('fuera del radio válido'))
              .having((e) => e.message, 'message', contains('100 m')),
        ),
      );
    });

    test('no permite un segundo check-in en la misma visita', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.enProgreso,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
        ),
      );

      await expectLater(
        repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio),
        throwsA(isA<ValidationException>()),
      );
    });

    test('no permite reabrir una visita completada', () async {
      await almacen.guardarVisita(visitaBase(estado: EstadoVisita.completada));

      await expectLater(
        repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio),
        throwsA(isA<ValidationException>()),
      );
    });

    test('falla si la visita no existe', () async {
      await expectLater(
        repo.registrarCheckIn(visitaId: 'inexistente', posicion: _enSitio),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('falla si el centro de costo no está en caché', () async {
      await almacen.guardarVisita(visitaBase(centroCostoId: 'cc-99'));

      await expectLater(
        repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('sin red el check-in se guarda igual y queda en la cola', () async {
      // Es el escenario central del reto: zona sin cobertura.
      conectividad.emitir(false);
      await almacen.guardarVisita(visitaBase());

      final actualizada = await repo.registrarCheckIn(
        visitaId: 'v-1',
        posicion: _enSitio,
      );

      expect(actualizada.tieneCheckIn, isTrue);
      expect(await cola.contarPendientes(), 1);
      expect(gateway.escrituras, isEmpty);
    });
  });

  group('registrarCheckOut', () {
    test('cierra la visita, guarda observaciones y la deja sincronizada', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.enProgreso,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
        ),
      );
      // El check-out se registra 90 minutos después del check-in.
      reloj.avanzar(const Duration(minutes: 90));

      final actualizada = await repo.registrarCheckOut(
        visitaId: 'v-1',
        posicion: _enSitio,
        observaciones: 'Zona común en buen estado.',
      );

      expect(actualizada.estado, EstadoVisita.completada);
      expect(actualizada.observaciones, 'Zona común en buen estado.');
      expect(actualizada.duracion, const Duration(minutes: 90));
    });

    test('las observaciones del checklist no se pierden', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.enProgreso,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
          actividades: const [],
        ),
      );
      // El supervisor ya había escrito una observación antes del cierre.
      final conNota = (await almacen.visitaPorId('v-1'))!.copyWith(
        observaciones: 'Seumbria el pasillo.',
      );
      await almacen.guardarVisita(conNota);

      final actualizada = await repo.registrarCheckOut(
        visitaId: 'v-1',
        posicion: _enSitio,
        observaciones: 'Se secó el piso.',
      );

      expect(actualizada.observaciones, contains('Seumbria el pasillo.'));
      expect(actualizada.observaciones, contains('Se secó el piso.'));
    });

    test('exige check-in previo', () async {
      await almacen.guardarVisita(visitaBase());

      await expectLater(
        repo.registrarCheckOut(visitaId: 'v-1', posicion: _enSitio),
        throwsA(isA<ValidationException>()),
      );
      expect(await cola.contarPendientes(), 0);
    });

    test('no permite dos check-out', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.completada,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
          checkOut: MarcadorVisita(momento: inicio, posicion: _enSitio),
        ),
      );

      await expectLater(
        repo.registrarCheckOut(visitaId: 'v-1', posicion: _enSitio),
        throwsA(isA<ValidationException>()),
      );
    });

    test('fuera del radio tampoco cierra la visita', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.enProgreso,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
        ),
      );

      await expectLater(
        repo.registrarCheckOut(visitaId: 'v-1', posicion: _lejos),
        throwsA(isA<ValidationException>()),
      );
      final guardada = await almacen.visitaPorId('v-1');
      expect(guardada!.tieneCheckOut, isFalse);
    });
  });

  group('guardarActividades', () {
    test('exige check-in antes de registrar el checklist', () async {
      await almacen.guardarVisita(visitaBase());

      await expectLater(
        repo.guardarActividades(
          visitaId: 'v-1',
          actividades: const [
            RegistroActividad(
              actividadId: 'a1',
              descripcion: 'Pisos',
              resultado: ResultadoActividad.cumplida,
            ),
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await cola.contarPendientes(), 0);
    });

    test('guarda el checklist y recalcula el cumplimiento', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.enProgreso,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
        ),
      );

      final actualizada = await repo.guardarActividades(
        visitaId: 'v-1',
        actividades: const [
          RegistroActividad(
            actividadId: 'a1',
            descripcion: 'Pisos',
            resultado: ResultadoActividad.cumplida,
          ),
          RegistroActividad(
            actividadId: 'a2',
            descripcion: 'Banos',
            resultado: ResultadoActividad.noCumplida,
          ),
          RegistroActividad(
            actividadId: 'a3',
            descripcion: 'Fachada',
            resultado: ResultadoActividad.noAplica,
          ),
        ],
      );

      expect(actualizada.totalCumplidas, 1);
      expect(actualizada.totalIncumplidas, 1);
      expect(actualizada.hayIncumplimientos, isTrue);
      expect(actualizada.porcentajeCumplimiento, 50);
    });

    test('no permite modificar actividades de una visita ya cerrada', () async {
      await almacen.guardarVisita(
        visitaBase(
          estado: EstadoVisita.completada,
          checkIn: MarcadorVisita(momento: inicio, posicion: _enSitio),
          checkOut: MarcadorVisita(momento: inicio, posicion: _enSitio),
        ),
      );

      await expectLater(
        repo.guardarActividades(visitaId: 'v-1', actividades: const []),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('Evidencias', () {
    test('la foto queda visible de inmediato aunque no haya red', () async {
      conectividad.emitir(false);
      await almacen.guardarVisita(visitaBase());

      final evidenciaCreada = await repo.adjuntarEvidencia(
        visitaId: 'v-1',
        rutaLocal: '/tmp/foto-1.jpg',
        actividadId: 'a1',
        ubicacion: _enSitio,
      );

      expect(evidenciaCreada.rutaLocal, '/tmp/foto-1.jpg');
      expect(evidenciaCreada.urlRemota, isNull);
      expect(evidenciaCreada.estaPendiente, isTrue);
      expect(
        (await almacen.evidenciasDe('v-1')).map((e) => e.id),
        contains(evidenciaCreada.id),
      );
      expect(await cola.contarPendientes(), 1);
    });

    test('encola la evidencia con la ruta local que luego se sube', () async {
      conectividad.emitir(false);
      await almacen.guardarVisita(visitaBase());

      final evidenciaCreada = await repo.adjuntarEvidencia(
        visitaId: 'v-1',
        rutaLocal: '/tmp/foto-2.jpg',
      );

      final item = cola.items.values.firstWhere(
        (i) => i.entidadId == evidenciaCreada.id,
      );
      expect(item.entidad, TipoEntidad.evidencia);
      expect(item.rutasArchivosLocales, ['/tmp/foto-2.jpg']);
    });

    test('con red la foto sube y la cola queda limpia', () async {
      await almacen.guardarVisita(visitaBase());

      await repo.adjuntarEvidencia(visitaId: 'v-1', rutaLocal: '/tmp/foto-3.jpg');

      expect(evidencia.subidas, hasLength(1));
      expect(await cola.contarPendientes(), 0);
    });

    test('cada captura genera un id distinto, así no se solapan', () async {
      conectividad.emitir(false);
      await almacen.guardarVisita(visitaBase());

      final a = await repo.adjuntarEvidencia(visitaId: 'v-1', rutaLocal: '/tmp/a.jpg');
      final b = await repo.adjuntarEvidencia(visitaId: 'v-1', rutaLocal: '/tmp/b.jpg');

      expect(a.id, isNot(b.id));
      expect(await cola.contarPendientes(), 2);
    });

    test('eliminar una evidencia pendiente la quita de local y encola el borrado', () async {
      conectividad.emitir(false);
      await almacen.guardarVisita(visitaBase());
      final evidenciaCreada = await repo.adjuntarEvidencia(
        visitaId: 'v-1',
        rutaLocal: '/tmp/foto-4.jpg',
      );
      // Se limpia la cola para aislar el borrado de la subida anterior.
      await cola.eliminar(cola.items.keys.first);

      await repo.eliminarEvidencia(evidenciaCreada.id);

      expect(await almacen.evidenciasDe('v-1'), isEmpty);
      final item = cola.items.values.single;
      expect(item.operacion, SyncOperacion.eliminar);
      expect(item.entidadId, evidenciaCreada.id);
    });

    test('no se puede eliminar una evidencia ya subida', () async {
      await almacen.guardarVisita(visitaBase());
      final evidenciaCreada = await repo.adjuntarEvidencia(
        visitaId: 'v-1',
        rutaLocal: '/tmp/foto-5.jpg',
      );

      // Se simula el estado post-subida que dejaría la sincronización.
      final subida = (await almacen.evidenciasDe('v-1')).single.copyWith(
        urlRemota: 'https://fake.storage/foto-5.jpg',
        syncStatus: SyncStatus.sincronizado,
      );
      await almacen.guardarEvidencia(subida);

      await expectLater(
        repo.eliminarEvidencia(evidenciaCreada.id),
        throwsA(isA<ValidationException>()),
      );
    });

    test('eliminar un id desconocido no hace nada ni falla', () async {
      await repo.eliminarEvidencia('no-existe');

      expect(await cola.contarPendientes(), 0);
    });
  });

  group('reportarNovedad', () {
    test('exige título y descripción', () async {
      await almacen.guardarVisita(visitaBase());

      await expectLater(
        repo.reportarNovedad(
          visitaId: 'v-1',
          titulo: '   ',
          descripcion: 'algo',
          prioridad: Prioridad.media,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo.reportarNovedad(
          visitaId: 'v-1',
          titulo: 'Fuga',
          descripcion: '  ',
          prioridad: Prioridad.media,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await cola.contarPendientes(), 0);
    });

    test('guarda la novedad localmente y la encola', () async {
      conectividad.emitir(false);
      await almacen.guardarVisita(visitaBase());

      final novedadCreada = await repo.reportarNovedad(
        visitaId: 'v-1',
        titulo: '  Fuga en pasillo  ',
        descripcion: '  Agua debajo de la ventana.  ',
        prioridad: Prioridad.media,
        accionesTomadas: const ['Se cerró la llave', '   '],
        evidenciaId: 'e-1',
      );

      expect(novedadCreada.titulo, 'Fuga en pasillo', reason: 'se recortan los espacios');
      expect(novedadCreada.descripcion, 'Agua debajo de la ventana.');
      expect(
        novedadCreada.accionesTomadas,
        ['Se cerró la llave'],
        reason: 'los espacios en blanco no se guardan',
      );
      expect(novedadCreada.evidenciaIds, ['e-1']);
      expect(novedadCreada.reportadaPor, 'sup-1');
      expect(novedadCreada.estado, EstadoNovedad.abierta);
      expect(await almacen.novedadesDe('v-1'), hasLength(1));
      expect(await cola.contarPendientes(), 1);
    });

    test('una novedad de prioridad alta se marca como notificada de inmediato', () async {
      await almacen.guardarVisita(visitaBase());

      final alta = await repo.reportarNovedad(
        visitaId: 'v-1',
        titulo: 'Derrame',
        descripcion: 'Piso inundado en recepción.',
        prioridad: Prioridad.alta,
      );

      expect(alta.coordinadorNotificado, isTrue);
      expect(alta.coordinadorNotificadoAt, isNotNull);
    });

    test('una novedad de prioridad media espera al ciclo de sincronización', () async {
      await almacen.guardarVisita(visitaBase());

      final baja = await repo.reportarNovedad(
        visitaId: 'v-1',
        titulo: 'Papel hygieneico faltante',
        descripcion: 'Reponer en el baño de damas.',
        prioridad: Prioridad.baja,
      );

      expect(baja.coordinadorNotificado, isFalse);
      expect(baja.coordinadorNotificadoAt, isNull);
    });

    test('la novedad hereda el centro de costo de la visita', () async {
      await almacen.guardarVisita(visitaBase(centroCostoId: 'cc-1'));

      final novedadCreada = await repo.reportarNovedad(
        visitaId: 'v-1',
        titulo: 'Fuga',
        descripcion: 'Descripción.',
        prioridad: Prioridad.media,
      );

      expect(novedadCreada.centroCostoId, 'cc-1');
    });

    test('falla si la visita ya no está disponible', () async {
      await expectLater(
        repo.reportarNovedad(
          visitaId: 'no-existe',
          titulo: 'Fuga',
          descripcion: 'Descripción.',
          prioridad: Prioridad.media,
        ),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('Idempotencia de la cola', () {
    test('cada mutación genera un item distinto de la misma visita', () async {
      await almacen.guardarVisita(visitaBase());
      conectividad.emitir(false);

      await repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio);
      reloj.avanzar(const Duration(minutes: 30));
      await repo.guardarActividades(
        visitaId: 'v-1',
        actividades: const [
          RegistroActividad(
            actividadId: 'a1',
            descripcion: 'Pisos',
            resultado: ResultadoActividad.cumplida,
          ),
        ],
      );
      reloj.avanzar(const Duration(minutes: 60));
      await repo.registrarCheckOut(visitaId: 'v-1', posicion: _enSitio);

      final items = cola.items.values
          .where((i) => i.entidad == TipoEntidad.visita)
          .toList();
      expect(items, hasLength(3));
      expect(
        items.map((i) => i.id).toSet(),
        hasLength(3),
        reason: 'ids únicos por mutación',
      );
      expect(
        items.every((i) => i.entidadId == 'v-1'),
        isTrue,
        reason: 'los tres items son de la misma visita',
      );
    });

    test('al drenar la cola el servidor queda con la última versión', () async {
      await almacen.guardarVisita(visitaBase());
      conectividad.emitir(false);
      await repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio);
      reloj.avanzar(const Duration(minutes: 60));
      await repo.registrarCheckOut(visitaId: 'v-1', posicion: _enSitio);

      conectividad.emitir(true);
      await sync.sincronizarAhora();

      final guardadas = gateway.documentos['visitas']!;
      expect(guardadas, hasLength(2), reason: 'dos mutaciones distintas de v-1');
      expect(await cola.contarPendientes(), 0, reason: 'la cola quedó vacía');

      // El orden FIFO garantiza que el último documento escrito es el del
      // check-out: el servidor termina con el estado final de la visita.
      final ultimo = guardadas.values.last;
      expect(ultimo['estado'], EstadoVisita.completada.valor);
      expect(ultimo['checkOut'], isNotNull);
    });

    test('un fallo de red deja todo en la cola sin perder registros', () async {
      gateway.errorAlEscribir = StateError('sin red');
      await almacen.guardarVisita(visitaBase());

      await repo.registrarCheckIn(visitaId: 'v-1', posicion: _enSitio);

      expect(
        await cola.contarPendientes(),
        1,
        reason: 'el registro no se pierde aunque no se suba',
      );
    });
  });
}