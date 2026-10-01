/// Tests del filtro del coordinador.
///
/// El filtro es la pieza que garantiza que el reporte exportado y lo que se ve
/// en pantalla sean el mismo conjunto de datos. Por eso se prueban tanto las
/// reglas de coincidencia como los bordes del rango de fechas, que es donde un
/// filtro mal implementado se nota (un día de más o de menos).
library;

import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/filtro_consulta.dart';
import 'package:fieldcheck/domain/models/novedad.dart';
import 'package:fieldcheck/domain/models/visita.dart';
import 'package:flutter_test/flutter_test.dart';

Visita visita({
  String id = 'v-1',
  String supervisorId = 'sup-1',
  String centroCostoId = 'cc-1',
  DateTime? fechaProgramada,
  EstadoVisita estado = EstadoVisita.pendiente,
  SyncStatus syncStatus = SyncStatus.sincronizado,
  List<RegistroActividad> actividades = const [],
}) => Visita(
  id: id,
  supervisorId: supervisorId,
  centroCostoId: centroCostoId,
  fechaProgramada: fechaProgramada ?? DateTime.utc(2026, 3, 10, 8),
  estado: estado,
  syncStatus: syncStatus,
  actividades: actividades,
);

Novedad novedad({
  String id = 'n-1',
  String centroCostoId = 'cc-1',
  DateTime? reportadaAt,
  EstadoNovedad estado = EstadoNovedad.abierta,
  Prioridad prioridad = Prioridad.media,
  SyncStatus syncStatus = SyncStatus.sincronizado,
}) => Novedad(
  id: id,
  visitaId: 'v-1',
  centroCostoId: centroCostoId,
  titulo: 'Fuga en tuberia',
  descripcion: 'Se observa agua en el pasillo.',
  prioridad: prioridad,
  reportadaPor: 'sup-1',
  reportadaAt: reportadaAt ?? DateTime.utc(2026, 3, 10, 9),
  estado: estado,
  syncStatus: syncStatus,
);

void main() {
  group('RangoFechas', () {
    final rango = RangoFechas(
      desde: DateTime(2026, 3, 10),
      hasta: DateTime(2026, 3, 12),
    );

    test('incluye los dos extremos del rango', () {
      expect(rango.contiene(DateTime(2026, 3, 10)), isTrue);
      expect(rango.contiene(DateTime(2026, 3, 12)), isTrue);
    });

    test('excluye los días inmediatamente anterior y posterior', () {
      expect(rango.contiene(DateTime(2026, 3, 9)), isFalse);
      expect(rango.contiene(DateTime(2026, 3, 13)), isFalse);
    });

    test('ignora la hora: el ultimo dia del rango incluye todo el dia', () {
      expect(rango.contiene(DateTime(2026, 3, 12, 23, 59, 59)), isTrue);
    });

    test('no depende del huso horario al comparar por dia', () {
      // Un instante UTC de la una de la madrugada es del dia anterior en hora
      // local negativa; comparar solo la parte de fecha evita sorpresas.
      expect(rango.contiene(DateTime.utc(2026, 3, 10, 1)), isTrue);
    });

    test('la etiqueta es legible y en formato dd/MM/yyyy', () {
      expect(rango.etiqueta, '10/03/2026 - 12/03/2026');
    });

    test('rango de un solo dia contiene solo ese dia', () {
      final unDia = RangoFechas(
        desde: DateTime(2026, 5, 4),
        hasta: DateTime(2026, 5, 4),
      );
      expect(unDia.contiene(DateTime(2026, 5, 4)), isTrue);
      expect(unDia.contiene(DateTime(2026, 5, 5)), isFalse);
    });
  });

  group('FiltroConsulta.estaVacio', () {
    test('sin filtros está vacío', () {
      expect(const FiltroConsulta.sinFiltros().estaVacio, isTrue);
    });

    test('cualquier criterio activo lo hace no vacío', () {
      const filtros = <FiltroConsulta>[
        FiltroConsulta(supervisorId: 'sup-1'),
        FiltroConsulta(centroCostoId: 'cc-1'),
        FiltroConsulta(estadoVisita: EstadoVisita.completada),
        FiltroConsulta(estadoNovedad: EstadoNovedad.abierta),
        FiltroConsulta(prioridad: Prioridad.alta),
        FiltroConsulta(soloPendientesDeSync: true),
        FiltroConsulta(soloConIncumplimientos: true),
      ];
      for (final f in filtros) {
        expect(f.estaVacio, isFalse, reason: 'no debería estar vacío: $f');
      }
    });
  });

  group('FiltroConsulta.copyWith y limpiar', () {
    test('copyWith sustituye un criterio y conserva el resto', () {
      const original = FiltroConsulta(
        centroCostoId: 'cc-1',
        prioridad: Prioridad.alta,
      );

      final copia = original.copyWith(prioridad: Prioridad.baja);

      expect(copia.prioridad, Prioridad.baja);
      expect(copia.centroCostoId, 'cc-1');
    });

    test('copyWith no puede borrar un criterio (null significa conservar)', () {
      const original = FiltroConsulta(centroCostoId: 'cc-1');

      final copia = original.copyWith();

      expect(copia.centroCostoId, 'cc-1');
      expect(copia.estaVacio, isFalse);
    });

    test('limpiar devuelve un filtro sin restricciones', () {
      const original = FiltroConsulta(
        supervisorId: 'sup-1',
        estadoVisita: EstadoVisita.completada,
        soloConIncumplimientos: true,
      );

      expect(original.limpiar().estaVacio, isTrue);
    });
  });

  group('coincideVisita', () {
    test('un filtro vacío coincide con cualquier visita', () {
      expect(const FiltroConsulta.sinFiltros().coincideVisita(visita()), isTrue);
    });

    test('filtra por supervisor', () {
      const filtro = FiltroConsulta(supervisorId: 'sup-2');

      expect(filtro.coincideVisita(visita(supervisorId: 'sup-2')), isTrue);
      expect(filtro.coincideVisita(visita(supervisorId: 'sup-1')), isFalse);
    });

    test('filtra por centro de costo', () {
      const filtro = FiltroConsulta(centroCostoId: 'cc-9');

      expect(filtro.coincideVisita(visita(centroCostoId: 'cc-9')), isTrue);
      expect(filtro.coincideVisita(visita(centroCostoId: 'cc-1')), isFalse);
    });

    test('filtra por estado de visita', () {
      const filtro = FiltroConsulta(estadoVisita: EstadoVisita.completada);

      expect(
        filtro.coincideVisita(visita(estado: EstadoVisita.completada)),
        isTrue,
      );
      expect(
        filtro.coincideVisita(visita(estado: EstadoVisita.enProgreso)),
        isFalse,
      );
    });

    test('soloPendientesDeSync excluye lo ya sincronizado', () {
      const filtro = FiltroConsulta(soloPendientesDeSync: true);

      expect(
        filtro.coincideVisita(visita(syncStatus: SyncStatus.pendiente)),
        isTrue,
        reason: 'un registro pendiente sí es lo que el coordinador busca',
      );
      expect(
        filtro.coincideVisita(visita(syncStatus: SyncStatus.sincronizado)),
        isFalse,
      );
    });

    test('soloConIncumplimientos exige al menos una actividad no cumplida', () {
      const filtro = FiltroConsulta(soloConIncumplimientos: true);

      expect(
        filtro.coincideVisita(
          visita(
            actividades: const [
              RegistroActividad(
                actividadId: 'a1',
                descripcion: 'Limpieza de pisos',
                resultado: ResultadoActividad.noCumplida,
              ),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        filtro.coincideVisita(
          visita(
            actividades: const [
              RegistroActividad(
                actividadId: 'a1',
                descripcion: 'Limpieza de pisos',
                resultado: ResultadoActividad.cumplida,
              ),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('las actividades "no aplica" no cuentan como incumplimiento', () {
      expect(
        const FiltroConsulta(
          soloConIncumplimientos: true,
        ).coincideVisita(
          visita(
            actividades: const [
              RegistroActividad(
                actividadId: 'a1',
                descripcion: 'Lavado de Fachada',
                resultado: ResultadoActividad.noAplica,
              ),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('filtra por la fecha programada, no por la de check-in', () {
      final filtro = FiltroConsulta(
        rango: RangoFechas(
          desde: DateTime(2026, 4, 1),
          hasta: DateTime(2026, 4, 30),
        ),
      );

      expect(
        filtro.coincideVisita(
          visita(fechaProgramada: DateTime.utc(2026, 4, 15)),
        ),
        isTrue,
      );
      expect(
        filtro.coincideVisita(
          visita(fechaProgramada: DateTime.utc(2026, 5, 15)),
        ),
        isFalse,
      );
    });

    test('los criterios se combinan con Y', () {
      const filtro = FiltroConsulta(
        supervisorId: 'sup-1',
        centroCostoId: 'cc-2',
        estadoVisita: EstadoVisita.enProgreso,
      );

      expect(
        filtro.coincideVisita(
          visita(
            supervisorId: 'sup-1',
            centroCostoId: 'cc-2',
            estado: EstadoVisita.enProgreso,
          ),
        ),
        isTrue,
      );
      expect(
        filtro.coincideVisita(
          visita(
            supervisorId: 'sup-1',
            centroCostoId: 'cc-2',
            estado: EstadoVisita.pendiente,
          ),
        ),
        isFalse,
        reason: 'falla un solo criterio y debe quedar fuera',
      );
    });
  });

  group('coincideNovedad', () {
    test('un filtro vacío coincide con cualquier novedad', () {
      expect(const FiltroConsulta.sinFiltros().coincideNovedad(novedad()), isTrue);
    });

    test('filtra por estado', () {
      const filtro = FiltroConsulta(estadoNovedad: EstadoNovedad.resuelta);

      expect(
        filtro.coincideNovedad(novedad(estado: EstadoNovedad.resuelta)),
        isTrue,
      );
      expect(
        filtro.coincideNovedad(novedad(estado: EstadoNovedad.enRevision)),
        isFalse,
      );
    });

    test('filtro por estado nulo incluye abiertas y resueltas', () {
      const filtro = FiltroConsulta(estadoNovedad: null);

      expect(filtro.coincideNovedad(novedad(estado: EstadoNovedad.abierta)), isTrue);
      expect(
        filtro.coincideNovedad(novedad(estado: EstadoNovedad.resuelta)),
        isTrue,
      );
    });

    test('filtra por prioridad', () {
      const filtro = FiltroConsulta(prioridad: Prioridad.alta);

      expect(filtro.coincideNovedad(novedad(prioridad: Prioridad.alta)), isTrue);
      expect(filtro.coincideNovedad(novedad(prioridad: Prioridad.baja)), isFalse);
    });

    test('filtra por la fecha en que se reportó', () {
      final filtro = FiltroConsulta(
        rango: RangoFechas(
          desde: DateTime(2026, 3, 10),
          hasta: DateTime(2026, 3, 10),
        ),
      );

      expect(
        filtro.coincideNovedad(novedad(reportadaAt: DateTime.utc(2026, 3, 10, 23))),
        isTrue,
      );
      expect(
        filtro.coincideNovedad(novedad(reportadaAt: DateTime.utc(2026, 3, 11, 1))),
        isFalse,
      );
    });

    test('los criterios de novedad ignoran los que no le aplican', () {
      // `supervisorId` y `estadoVisita` son criterios de visita: un filtro que los
      // fija no debe dejar sin novedades al coordinador.
      const filtro = FiltroConsulta(
        supervisorId: 'sup-99',
        estadoVisita: EstadoVisita.completada,
      );

      expect(filtro.coincideNovedad(novedad()), isTrue);
    });
  });
}