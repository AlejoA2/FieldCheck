/// Construcción del reporte CSV del coordinador.
///
/// ## Por qué vive en el dominio y no en la capa de datos
///
/// Un reporte que no coincide con lo que el coordinador ve en pantalla es el
/// peor defecto posible en un panel de control. Por eso el filtro se aplica
/// con [FiltroConsulta.coincideVisita] (el mismo objeto que usa la pantalla) y la
/// construcción del CSV vive aquí, sin Firebase ni `dart:io`, para poder
/// verificarla en tests.
///
/// ## Separador y formato
///
/// Se usa el paquete `csv` con punto y coma como separador. El destino del
/// reporte es una hoja de cálculo en configuración regional española, donde la
/// coma es el separador decimal: con coma como separador de columnas, Excel
/// rompería cada columna numérica en dos.
library;

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../models/centro_costo.dart';
import '../models/novedad.dart';
import '../models/visita.dart';

/// Genera el contenido CSV de un reporte de visitas.
class ReporteCsv {
  const ReporteCsv();

  /// Codec con `;` como separador y BOM UTF-8: el perfil de Excel en español.
  static final Csv _csvExcel = Csv.excel();

  /// Marca de byte order del archivo UTF-8.
  ///
  /// El paquete `csv` la antepone a cada bloque que codifica, así que el
  /// reporte de dos secciones se construye en una sola llamada: concatenar dos
  /// CSV ya codificados dejaría un BOM intermedio que Excel mostraría como un
  /// carácter basura al inicio de la segunda sección.
  static const String _bom = '\uFEFF';

  static final DateFormat _fecha = DateFormat('yyyy-MM-dd');
  static final DateFormat _hora = DateFormat('HH:mm');
  static final DateFormat _fechaHora = DateFormat('yyyy-MM-dd HH:mm');

  /// Versión del formato, en la cabecera.
  ///
  /// Un reporte exportado puede terminar en un archivo que alguien abre meses
  /// después; la versión permite saber qué columnas esperar.
  static const String version = '1.0';

  /// Genera el CSV de visitas.
  ///
  /// [centrosPorId] resuelve el nombre del centro de costo. Sin él, la columna
  /// queda con el id: es preferible un id a una celda vacía que se parece a un
  /// dato perdido.
  String visitas({
    required List<Visita> visitas,
    Map<String, CentroCosto> centrosPorId = const {},
  }) => _codificar(_filasVisitas(visitas, centrosPorId));

  /// Genera el CSV de novedades.
  String novedades({
    required List<Novedad> novedades,
    Map<String, CentroCosto> centrosPorId = const {},
    Map<String, String> supervisoresPorId = const {},
  }) => _codificar(_filasNovedades(novedades, centrosPorId, supervisoresPorId));

  /// Genera un archivo con dos secciones: visitas y novedades.
  ///
  /// Es el formato que el botón "Exportar" produce: una sola descarga con todo
  /// lo que el filtro seleccionado dejó visible, para que el archivo y lo que
  /// se ve en pantalla sean exactamente el mismo conjunto de datos.
  ///
  /// Las dos secciones se codifican en una sola llamada justamente para que el
  /// BOM UTF-8 aparezca una única vez, al inicio del archivo.
  String completo({
    // Los parámetros llevan prefijo `lista` a propósito: si se llamaran igual
    // que los métodos, dentro de este cuerpo `visitas` resolvería a la lista y
    // la llamada al método fallaría con "not a function".
    required List<Visita> listaVisitas,
    required List<Novedad> listaNovedades,
    Map<String, CentroCosto> centrosPorId = const {},
    Map<String, String> supervisoresPorId = const {},
  }) {
    return _codificar([
      ..._filasVisitas(listaVisitas, centrosPorId),
      // Línea en blanco entre secciones: separa visualmente los dos bloques
      // sin introducir una fila que Excel interpretaría como dato.
      const [],
      const [],
      ..._filasNovedades(listaNovedades, centrosPorId, supervisoresPorId),
    ]);
  }

  List<List<dynamic>> _filasVisitas(
    List<Visita> lista,
    Map<String, CentroCosto> centrosPorId,
  ) => <List<dynamic>>[
    ['Reporte de visitas FieldCheck v$version'],
    ['Generado', _fechaHora.format(DateTime.now())],
    ['Total de visitas', lista.length],
    const [],
    _encabezadoVisitas,
    ...lista.map((v) => _filaVisita(v, centrosPorId[v.centroCostoId])),
  ];

  List<List<dynamic>> _filasNovedades(
    List<Novedad> lista,
    Map<String, CentroCosto> centrosPorId,
    Map<String, String> supervisoresPorId,
  ) => <List<dynamic>>[
    ['Reporte de novedades FieldCheck v$version'],
    ['Generado', _fechaHora.format(DateTime.now())],
    ['Total de novedades', lista.length],
    const [],
    _encabezadoNovedades,
    ...lista.map((n) => _filaNovedad(n, centrosPorId, supervisoresPorId)),
  ];

  /// Nombre de archivo con marca de tiempo.
  ///
  /// Sin la marca, dos exportaciones del mismo día se sobrescriben al guardarse
  /// con el mismo nombre y el coordinador pierde el reporte anterior.
  static String nombreArchivo(String prefijo, {DateTime? momento}) {
    final fecha = DateFormat('yyyyMMdd_HHmm').format(momento ?? DateTime.now());
    return '${prefijo}_$fecha.csv';
  }

  // ------------------------------------------------------------------ tablas

  static const List<String> _encabezadoVisitas = [
    'Id visita',
    'Fecha programada',
    'Centro de costo',
    'Supervisor',
    'Estado',
    'Sincronizacion',
    'Check-in',
    'Hora check-in',
    'Distancia check-in (m)',
    'Check-out',
    'Hora check-out',
    'Distancia check-out (m)',
    'Duracion (min)',
    'Actividades cumplidas',
    'Actividades no cumplidas',
    '% Cumplimiento',
    'Latitud check-in',
    'Longitud check-in',
    'Observaciones',
  ];

  static const List<String> _encabezadoNovedades = [
    'Id novedad',
    'Fecha reporte',
    'Centro de costo',
    'Supervisor',
    'Titulo',
    'Prioridad',
    'Estado',
    'Descripcion',
    'Acciones tomadas',
    'Evidencias',
    'Cierre',
    'Resuelto por',
    'Fecha de cierre',
  ];

  List<dynamic> _filaVisita(Visita v, CentroCosto? centro) => [
    v.id,
    _fecha.format(v.fechaProgramada.toLocal()),
    centro?.nombre ?? v.centroCostoId,
    v.supervisorId,
    v.estado.etiqueta,
    v.syncStatus.etiqueta,
    v.checkIn == null ? '' : _fecha.format(v.checkIn!.momento.toLocal()),
    v.checkIn == null ? '' : _hora.format(v.checkIn!.momento.toLocal()),
    v.distanciaCheckInMetros?.toStringAsFixed(1) ?? '',
    v.checkOut == null ? '' : _fecha.format(v.checkOut!.momento.toLocal()),
    v.checkOut == null ? '' : _hora.format(v.checkOut!.momento.toLocal()),
    v.distanciaCheckOutMetros?.toStringAsFixed(1) ?? '',
    v.duracion?.inMinutes.toString() ?? '',
    v.totalCumplidas,
    v.totalIncumplidas,
    v.porcentajeCumplimiento.toStringAsFixed(1),
    v.checkIn?.posicion.latitud.toStringAsFixed(6) ?? '',
    v.checkIn?.posicion.longitud.toStringAsFixed(6) ?? '',
    v.observaciones,
  ];

  List<dynamic> _filaNovedad(
    Novedad n,
    Map<String, CentroCosto> centrosPorId,
    Map<String, String> supervisoresPorId,
  ) => [
    n.id,
    _fechaHora.format(n.reportadaAt.toLocal()),
    centrosPorId[n.centroCostoId]?.nombre ?? n.centroCostoId,
    supervisoresPorId[n.reportadaPor] ?? n.reportadaPor,
    n.titulo,
    n.prioridad.etiqueta,
    n.estado.etiqueta,
    n.descripcion,
    n.accionesTomadas.join(' | '),
    n.evidenciaIds.length,
    n.resolucion ?? '',
    n.resueltaPor == null ? '' : (supervisoresPorId[n.resueltaPor] ?? n.resueltaPor!),
    n.resueltaAt == null ? '' : _fechaHora.format(n.resueltaAt!.toLocal()),
  ];

  /// Codifica con `;` como separador de columnas y BOM UTF-8.
  ///
  /// El BOM no es decorativo: sin él, Excel en Windows abre los acentos de
  /// "Gestión", "Distancia" y "Titulo" como caracteres rotos. Es el paquete
  /// `csv` el que lo emite, con su perfil `excel`.
  ///
  /// La guarda final deja constancia de que el BOM es exactamente uno y está al
  /// principio: si el formato cambiara, el archivo dejaría de abrirse bien en
  /// Excel y ese fallo solo se vería al abrirlo a mano.
  String _codificar(List<List<dynamic>> filas) {
    final csv = _csvExcel.encode(filas);
    assert(
      csv.startsWith(_bom) && _bom.allMatches(csv).length == 1,
      'El CSV debe tener exactamente un BOM UTF-8, al inicio.',
    );
    return csv;
  }
}
