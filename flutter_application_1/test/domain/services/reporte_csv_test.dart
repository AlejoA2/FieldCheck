/// Tests del generador de reportes CSV.
///
/// Lo que se verifica aquí no es solo que el archivo "se abra", sino que sea
/// interpretable por la herramienta que el coordinador realmente usa: Excel en
/// configuración regional española. De ahí las aserciones sobre el separador
/// `;` y el BOM UTF-8; sin ellos, los acentos de "Gestión" o "Distancia" se
/// verían rotos y las columnas numéricas se partirían en dos.
library;

import 'package:fieldcheck/domain/models/centro_costo.dart';
import 'package:fieldcheck/domain/models/enums.dart';
import 'package:fieldcheck/domain/models/geo_point.dart';
import 'package:fieldcheck/domain/models/novedad.dart';
import 'package:fieldcheck/domain/models/visita.dart';
import 'package:fieldcheck/domain/services/reporte_csv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Primer caracter de un archivo UTF-8 con BOM.
const String _bom = '\uFEFF';

Visita visita({
  String id = 'v-1',
  String supervisorId = 'sup-1',
  String centroCostoId = 'cc-1',
  DateTime? fechaProgramada,
  MarcadorVisita? checkIn,
  MarcadorVisita? checkOut,
  List<RegistroActividad> actividades = const [],
  String observaciones = '',
  EstadoVisita estado = EstadoVisita.enProgreso,
  SyncStatus syncStatus = SyncStatus.sincronizado,
  double? distanciaCheckIn,
  double? distanciaCheckOut,
}) => Visita(
  id: id,
  supervisorId: supervisorId,
  centroCostoId: centroCostoId,
  fechaProgramada: fechaProgramada ?? DateTime.utc(2026, 3, 10, 8),
  checkIn: checkIn,
  checkOut: checkOut,
  actividades: actividades,
  observaciones: observaciones,
  estado: estado,
  syncStatus: syncStatus,
  distanciaCheckInMetros: distanciaCheckIn,
  distanciaCheckOutMetros: distanciaCheckOut,
);

MarcadorVisita marcador(DateTime momento, {double lat = 4.7110, double lng = -74.0721}) =>
    MarcadorVisita(momento: momento, posicion: GeoPoint(lat, lng));

Novedad novedad({
  String id = 'n-1',
  String centroCostoId = 'cc-1',
  String reportadaPor = 'sup-1',
  DateTime? reportadaAt,
  Prioridad prioridad = Prioridad.media,
  EstadoNovedad estado = EstadoNovedad.abierta,
  List<String> evidenciaIds = const [],
  List<String> accionesTomadas = const [],
  String descripcion = 'Se observa agua bajo la ventana del segundo piso.',
  String? resolucion,
  String? resueltaPor,
  DateTime? resueltaAt,
}) => Novedad(
  id: id,
  visitaId: 'v-1',
  centroCostoId: centroCostoId,
  titulo: 'Fuga de agua en pasillo',
  descripcion: descripcion,
  prioridad: prioridad,
  reportadaPor: reportadaPor,
  reportadaAt: reportadaAt ?? DateTime.utc(2026, 3, 10, 9, 30),
  evidenciaIds: evidenciaIds,
  accionesTomadas: accionesTomadas,
  estado: estado,
  resolucion: resolucion,
  resueltaPor: resueltaPor,
  resueltaAt: resueltaAt,
);

/// Líneas del CSV sin el BOM inicial.
List<String> lineas(String csv) {
  final limpio = csv.startsWith(_bom) ? csv.substring(1) : csv;
  return limpio.split('\r\n').where((l) => l.isNotEmpty).toList();
}

void main() {
  const reporte = ReporteCsv();
  final centros = {
    'cc-1': const CentroCosto(
      id: 'cc-1',
      nombre: 'Sede Administrativa',
      ubicacion: GeoPoint(4.7110, -74.0721),
    ),
  };
  final supervisores = {'sup-1': 'Ana Rivera', 'sup-2': 'Luis Ortega'};

  group('Formato del archivo', () {
    test('empieza con BOM UTF-8 para que Excel respete los acentos', () {
      final csv = reporte.visitas(visitas: [visita()]);

      expect(csv.startsWith(_bom), isTrue);
    });

    test('usa punto y coma como separador de columnas', () {
      final csv = reporte.visitas(visitas: [visita()]);

      final encabezado = lineas(csv).firstWhere(
        (l) => l.contains('Id visita'),
      );
      expect(encabezado, contains(';'));
      expect(
        encabezado.split(';').length,
        19,
        reason: '19 columnas de visita, separadas por 18 punto y comas',
      );
    });

    test('el BOM aparece una sola vez, incluso con dos secciones', () {
      final csv = reporte.completo(
        listaVisitas: [visita()],
        listaNovedades: [novedad()],
      );

      expect(csv.startsWith(_bom), isTrue);
      // La segunda sección no debe volver a emitir BOM: Excel lo mostraría como
      // un carácter extraño en la primera celda de la hoja.
      expect(_bom.allMatches(csv).length, 1);
    });

    test('incluye la versión del formato en el encabezado', () {
      final csv = reporte.visitas(visitas: [visita()]);

      expect(csv, contains('Reporte de visitas FieldCheck v${ReporteCsv.version}'));
    });

    test('declara el total de registros', () {
      final csv = reporte.visitas(visitas: [visita(id: 'a'), visita(id: 'b')]);

      expect(csv, contains('Total de visitas;2'));
    });
  });

  group('Reporte de visitas', () {
    test('lista las columnas esperadas', () {
      final csv = reporte.visitas(visitas: const []);
      final encabezado = lineas(csv).firstWhere((l) => l.contains('Id visita'));

      final columnas = encabezado.split(';');
      expect(columnas.first, 'Id visita');
      expect(columnas, contains('Centro de costo'));
      expect(columnas, contains('% Cumplimiento'));
      expect(columnas.last, 'Observaciones');
    });

    test('resuelve el nombre del centro de costo cuando está en caché', () {
      final csv = reporte.visitas(
        visitas: [visita(centroCostoId: 'cc-1')],
        centrosPorId: centros,
      );

      expect(csv, contains('Sede Administrativa'));
    });

    test('usa el id del centro si no hay caché, nunca una celda vacía', () {
      final csv = reporte.visitas(
        visitas: [visita(centroCostoId: 'cc-99')],
        centrosPorId: centros,
      );

      final fila = lineas(csv).last;
      final columnaCentro = fila.split(';')[2];
      expect(columnaCentro, 'cc-99');
    });

    test('una visita sin check-in deja en blanco las columnas del marcador', () {
      final csv = reporte.visitas(visitas: [visita()]);
      final columnas = lineas(csv).last.split(';');

      // La fila de datos tiene 19 columnas, alineadas con el encabezado; sin
      // check-in, las de hora y distancia van vacías (no con "null").
      expect(columnas[6], '');
      expect(columnas[8], '');
      expect(columnas[12], '', reason: 'no hay check-out, no hay duración');
    });

    test('calcula la duración en minutos entre check-in y check-out', () {
      final entrada = DateTime.utc(2026, 3, 10, 8);
      final salida = DateTime.utc(2026, 3, 10, 10, 45);
      final csv = reporte.visitas(
        visitas: [
          visita(
            checkIn: marcador(entrada),
            checkOut: marcador(salida),
            estado: EstadoVisita.completada,
          ),
        ],
      );

      expect(lineas(csv).last.split(';')[12], '165');
    });

    test('reporta el porcentaje de cumplimiento con un decimal', () {
      final csv = reporte.visitas(
        visitas: [
          visita(
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
            ],
          ),
        ],
      );
      final columnas = lineas(csv).last.split(';');

      expect(columnas[13], '1', reason: 'actividades cumplidas');
      expect(columnas[14], '1', reason: 'actividades no cumplidas');
      expect(columnas[15], '50.0');
    });

    test('guarda la distancia al centro con un decimal', () {
      final csv = reporte.visitas(
        visitas: [visita(checkIn: marcador(DateTime.utc(2026, 3, 10, 8)), distanciaCheckIn: 42.37)],
      );

      expect(lineas(csv).last.split(';')[8], '42.4');
    });

    test('exporta las coordenadas con 6 decimales', () {
      final csv = reporte.visitas(
        visitas: [visita(checkIn: marcador(DateTime.utc(2026, 3, 10, 8)))],
      );
      final columnas = lineas(csv).last.split(';');

      expect(columnas[16], '4.711000');
      expect(columnas[17], '-74.072100');
    });

    test('el estado de la visita y el de sincronización usan etiquetas', () {
      final csv = reporte.visitas(
        visitas: [
          visita(
            estado: EstadoVisita.completada,
            syncStatus: SyncStatus.pendiente,
          ),
        ],
      );
      final columnas = lineas(csv).last.split(';');

      expect(columnas[4], 'Completada');
      expect(columnas[5], 'Pendiente de sincronizar');
    });

    test('con varias visitas genera una fila por cada una, en orden', () {
      final csv = reporte.visitas(
        visitas: [visita(id: 'v-1'), visita(id: 'v-2'), visita(id: 'v-3')],
      );

      final filas = lineas(csv).skipWhile((l) => !l.contains('Id visita')).skip(1);
      expect(filas, hasLength(3));
      expect(filas.first.startsWith('v-1'), isTrue);
      expect(filas.last.startsWith('v-3'), isTrue);
    });
  });

  group('Reporte de novedades', () {
    test('lista las columnas esperadas', () {
      final csv = reporte.novedades(novedades: const []);
      final encabezado = lineas(csv).firstWhere((l) => l.contains('Id novedad'));

      expect(encabezado.split(';').last, 'Fecha de cierre');
    });

    test('resuelve el nombre del supervisor que reportó', () {
      final csv = reporte.novedades(
        novedades: [novedad(reportadaPor: 'sup-1')],
        supervisoresPorId: supervisores,
      );

      final columnas = lineas(csv).last.split(';');
      expect(columnas[3], 'Ana Rivera');
    });

    test('cae al id si el supervisor no está en el diccionario', () {
      final csv = reporte.novedades(
        novedades: [novedad(reportadaPor: 'sup-2')],
        supervisoresPorId: supervisores,
      );

      expect(lineas(csv).last.split(';')[3], 'Luis Ortega');
    });

    test('cuenta las evidencias y une las acciones con separador legible', () {
      final csv = reporte.novedades(
        novedades: [
          novedad(
            evidenciaIds: const ['e-1', 'e-2'],
            accionesTomadas: const ['Se cerró la llave de paso', 'Se avisó a mantenimiento'],
          ),
        ],
      );
      final columnas = lineas(csv).last.split(';');

      expect(columnas[9], '2');
      expect(columnas[8], 'Se cerró la llave de paso | Se avisó a mantenimiento');
    });

    test('una novedad abierta deja en blanco las columnas de cierre', () {
      final csv = reporte.novedades(novedades: [novedad()]);
      final columnas = lineas(csv).last.split(';');

      expect(columnas[10], '');
      expect(columnas[11], '');
      expect(columnas[12], '');
    });

    test('una novedad resuelta exporta el cierre con su autor y fecha', () {
      final csv = reporte.novedades(
        novedades: [
          novedad(
            estado: EstadoNovedad.resuelta,
            resolucion: 'Reparado y verificado',
            resueltaPor: 'sup-1',
            resueltaAt: DateTime.utc(2026, 3, 11, 15, 5),
          ),
        ],
        supervisoresPorId: supervisores,
      );
      final columnas = lineas(csv).last.split(';');

      expect(columnas[6], 'Resuelta');
      expect(columnas[10], 'Reparado y verificado');
      expect(columnas[11], 'Ana Rivera');
      expect(columnas[12], isNotEmpty);
    });

    test('exporta la prioridad en texto legible, no el valor crudo', () {
      final csv = reporte.novedades(novedades: [novedad(prioridad: Prioridad.alta)]);

      expect(lineas(csv).last.split(';')[5], 'Alta');
    });

    test('una descripción con punto y coma no rompe las columnas', () {
      // Este es el motivo de usar CSV con comillas en lugar de unir a mano con
      // punto y coma: el texto del supervisor puede contener el separador.
      final csv = reporte.novedades(
        novedades: [
          novedad(
            descripcion: 'Dos hallazgos: fuga en el baño; y falta de papel.',
          ),
        ],
      );
      final filas = lineas(csv);
      final fila = filas.last;

      expect(fila, contains('"Dos hallazgos: fuga en el baño; y falta de papel."'));
      expect(fila, startsWith('n-1;'));
    });
  });

  group('Reporte completo', () {
    test('contiene las dos secciones en un solo archivo', () {
      final csv = reporte.completo(
        listaVisitas: [visita()],
        listaNovedades: [novedad()],
      );

      expect(csv, contains('Reporte de visitas FieldCheck'));
      expect(csv, contains('Reporte de novedades FieldCheck'));
    });

    test('exporta exactamente las listas que se le entregan', () {
      // El panel exporta las listas ya filtradas que muestra en pantalla, sin
      // volver a consultar: así el archivo y la vista no pueden divergir.
      final csv = reporte.completo(
        listaVisitas: [visita(id: 'v-1'), visita(id: 'v-2')],
        listaNovedades: [novedad(id: 'n-1')],
      );

      expect(csv, contains('Total de visitas;2'));
      expect(csv, contains('Total de novedades;1'));
      expect(csv, isNot(contains('v-3')));
    });

    test('con listas vacías produce un archivo con solo encabezados', () {
      final csv = reporte.completo(listaVisitas: const [], listaNovedades: const []);

      expect(csv, contains('Id visita'));
      expect(csv, contains('Id novedad'));
      expect(csv, contains('Total de visitas;0'));
    });
  });

  group('nombreArchivo', () {
    test('incluye marca de tiempo para no sobrescribir reportes', () {
      final nombre = ReporteCsv.nombreArchivo(
        'visitas',
        momento: DateTime(2026, 3, 10, 14, 5),
      );

      expect(nombre, 'visitas_20260310_1405.csv');
    });

    test('el formato es estable y predecible', () {
      final nombre = ReporteCsv.nombreArchivo(
        'novedades',
        momento: DateTime(2026, 12, 31, 23, 59),
      );

      expect(nombre, 'novedades_20261231_2359.csv');
      expect(nombre, endsWith('.csv'));
    });
  });
}

