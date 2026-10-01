import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/geo_point.dart';
import 'package:fieldcheck/domain/models/visita.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inicio = DateTime.utc(2026, 3, 10, 14);

  Visita construirVisita({
    List<RegistroActividad> actividades = const [],
    MarcadorVisita? checkIn,
    MarcadorVisita? checkOut,
    EstadoVisita estado = EstadoVisita.pendiente,
  }) => Visita(
    id: 'v-1',
    supervisorId: 's-1',
    centroCostoId: 'cc-1',
    fechaProgramada: inicio,
    actividades: actividades,
    checkIn: checkIn,
    checkOut: checkOut,
    estado: estado,
  );

  RegistroActividad actividad(
    String id,
    ResultadoActividad resultado,
  ) => RegistroActividad(
    actividadId: id,
    descripcion: 'Actividad $id',
    resultado: resultado,
  );

  group('Visita - métricas de cumplimiento', () {
    test('sin actividades evalúa al 100 % (no penaliza al supervisor)', () {
      expect(construirVisita().porcentajeCumplimiento, 100);
    });

    test('todas cumplidas da 100 %', () {
      final visita = construirVisita(
        actividades: [
          actividad('a1', ResultadoActividad.cumplida),
          actividad('a2', ResultadoActividad.cumplida),
        ],
      );

      expect(visita.porcentajeCumplimiento, 100);
      expect(visita.totalCumplidas, 2);
      expect(visita.totalIncumplidas, 0);
    });

    test('la mitad cumplidas da 50 %', () {
      final visita = construirVisita(
        actividades: [
          actividad('a1', ResultadoActividad.cumplida),
          actividad('a2', ResultadoActividad.noCumplida),
        ],
      );

      expect(visita.porcentajeCumplimiento, 50);
      expect(visita.hayIncumplimientos, isTrue);
    });

    test('"no aplica" queda fuera del denominador', () {
      final visita = construirVisita(
        actividades: [
          actividad('a1', ResultadoActividad.cumplida),
          actividad('a2', ResultadoActividad.noAplica),
          actividad('a3', ResultadoActividad.noCumplida),
        ],
      );

      // Solo a1 y a3 cuentan: 1 de 2 cumplidas.
      expect(visita.actividadesEvaluadas, hasLength(2));
      expect(visita.porcentajeCumplimiento, 50);
      expect(visita.totalCumplidas, 1);
      expect(visita.totalIncumplidas, 1);
    });

    test('todas "no aplica" no reporta cumplimiento positivo ni negativo', () {
      final visita = construirVisita(
        actividades: [
          actividad('a1', ResultadoActividad.noAplica),
          actividad('a2', ResultadoActividad.noAplica),
        ],
      );

      expect(visita.actividadesEvaluadas, isEmpty);
      expect(visita.porcentajeCumplimiento, 100);
      expect(visita.hayIncumplimientos, isFalse);
    });
  });

  group('Visita - duración', () {
    test('es null si no hay check-in', () {
      expect(construirVisita().duracion, isNull);
    });

    test('es null si solo hay check-in (visita en curso)', () {
      final visita = construirVisita(
        checkIn: MarcadorVisita(momento: inicio, posicion: const GeoPoint(0, 0)),
      );

      expect(visita.duracion, isNull);
      expect(visita.tieneCheckIn, isTrue);
      expect(visita.tieneCheckOut, isFalse);
    });

    test('calcula la duración entre check-in y check-out', () {
      final visita = construirVisita(
        checkIn: MarcadorVisita(
          momento: inicio,
          posicion: const GeoPoint(4.7110, -74.0721),
        ),
        checkOut: MarcadorVisita(
          momento: inicio.add(const Duration(minutes: 47, seconds: 30)),
          posicion: const GeoPoint(4.7110, -74.0721),
        ),
        estado: EstadoVisita.completada,
      );

      expect(visita.duracion, const Duration(minutes: 47, seconds: 30));
      expect(visita.estado.esTerminal, isTrue);
    });

    test('un check-out anterior al check-in produce null en vez de negativo', () {
      final visita = construirVisita(
        checkIn: MarcadorVisita(momento: inicio, posicion: const GeoPoint(0, 0)),
        checkOut: MarcadorVisita(
          momento: inicio.subtract(const Duration(hours: 1)),
          posicion: const GeoPoint(0, 0),
        ),
      );

      expect(visita.duracion, isNull);
    });
  });

  group('Visita - copyWith', () {
    test('no pierde campos al actualizar el estado', () {
      final original = construirVisita(
        actividades: [actividad('a1', ResultadoActividad.cumplida)],
        checkIn: MarcadorVisita(momento: inicio, posicion: const GeoPoint(0, 0)),
        estado: EstadoVisita.enProgreso,
      );

      final actualizada = original.copyWith(estado: EstadoVisita.completada);

      expect(actualizada.estado, EstadoVisita.completada);
      expect(actualizada.actividades, hasLength(1));
      expect(actualizada.checkIn, isNotNull);
      expect(actualizada.supervisorId, original.supervisorId);
      expect(actualizada.id, original.id);
    });
  });

  group('RegistroActividad', () {
    test('serializa y deserializa sin pérdida', () {
      const original = RegistroActividad(
        actividadId: 'a1',
        descripcion: 'Limpieza de áreas comunes',
        resultado: ResultadoActividad.noCumplida,
        comentario: 'Faltaron dos puntos',
      );

      final restaurado = RegistroActividad.fromMap(original.toMap());

      expect(restaurado.actividadId, original.actividadId);
      expect(restaurado.descripcion, original.descripcion);
      expect(restaurado.resultado, original.resultado);
      expect(restaurado.comentario, original.comentario);
      expect(restaurado.fueIncumplida, isTrue);
      expect(restaurado.fueCumplida, isFalse);
    });
  });
}