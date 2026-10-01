/// Detalle de una visita: check-in, checklist, evidencias, novedad y check-out.
///
/// ## El flujo en pantalla
///
/// ```text
/// asignada -> [Registrar llegada] -> en curso -> [checklist + fotos]
///          -> [Reportar novedad]* -> [Registrar salida] -> completada
/// ```
///
/// El botón principal cambia según el estado de la visita. Que la acción
/// principal sea siempre la misma posición evita que el supervisor tenga que
/// buscar el botón correcto en cada visita.
///
/// ## Por qué el geofence se valida en el dominio y no aquí
///
/// Esta pantalla pide la posición, la pasa a `VisitaRepository` y muestra el
/// resultado. Todo el cálculo (distancia, radio, mensaje) vive en
/// `GeofenceService`, que ya tiene sus tests. Duplicar aquí el cálculo
/// significaría dos lugares que pueden discrepar.
///
/// La diferencia con la UI es el **tono**: un fallo de validación se muestra
/// como un aviso accionable, no como un error de sistema.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/di/dependencias.dart';
import '../../core/error/app_exception.dart';
import '../../core/theme/tema.dart';
import '../../core/widgets/comunes.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/evidencia.dart';
import '../../domain/models/geo_point.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/visita.dart';
import '../../domain/services/geofence_service.dart';
import '../../domain/services/ubicacion_service.dart';
import 'novedad_form_sheet.dart';

class VisitaDetalleScreen extends StatefulWidget {
  const VisitaDetalleScreen({required this.visitaId, super.key});

  final String visitaId;

  @override
  State<VisitaDetalleScreen> createState() => _VisitaDetalleScreenState();
}

class _VisitaDetalleScreenState extends State<VisitaDetalleScreen> {
  Visita? _visita;
  CentroCosto? _centro;
  List<Evidencia> _evidencias = const [];
  List<Novedad> _novedades = const [];

  /// `true` mientras se ejecuta una acción que escribe (check-in, check-out).
  bool _operando = false;

  /// Mensaje de la última validación fallida, mostrado bajo el botón principal.
  String? _avisoGeofence;

  String? _sugerenciaGeofence;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final visita = _visita;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de la visita'),
        actions: [
          if (visita != null && visita.syncStatus.requiereSync)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: InsigniaSync(estado: visita.syncStatus)),
            ),
        ],
      ),
      body: visita == null
          ? const Center(child: CircularProgressIndicator())
          : _cuerpo(visita),
      bottomNavigationBar: visita == null ? null : _barraAccion(visita),
    );
  }

  Widget _cuerpo(Visita visita) {
    final checklist = _centro?.actividades ?? const <ActividadChecklist>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _EncabezadoVisita(visita: visita, centro: _centro),
        const SizedBox(height: 16),
        _Marcadores(visita: visita, geofence: const GeofenceService()),
        const SizedBox(height: 20),
        _Seccion(titulo: 'Checklist de actividades', child: _Checklist(
          actividades: checklist,
          registros: visita.actividades,
          editable: _puedeEditar(visita),
          alCambiar: _guardarActividades,
        )),
        const SizedBox(height: 20),
        _Seccion(
          titulo: 'Evidencias fotográficas',
          child: _Evidencias(
            evidencias: _evidencias,
            alTomar: _puedeEditar(visita) ? _tomarFoto : null,
          ),
        ),
        const SizedBox(height: 20),
        _Seccion(
          titulo: 'Novedades reportadas',
          child: _Novedades(
            novedades: _novedades,
            alReportar: _puedeEditar(visita) ? _reportarNovedad : null,
          ),
        ),
      ],
    );
  }

  /// Barra inferior con la acción principal de la visita.
  Widget _barraAccion(Visita visita) {
    final (icono, etiqueta, activo) = switch (visita.estado) {
      EstadoVisita.pendiente => (
        Icons.login,
        'Registrar llegada',
        !_operando,
      ),
      EstadoVisita.enProgreso => (
        Icons.logout,
        'Registrar salida',
        !_operando,
      ),
      EstadoVisita.completada => (Icons.check_circle, 'Visita completada', false),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_avisoGeofence != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: TemaCampo.rojo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: TemaCampo.rojo.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _avisoGeofence!,
                      style: const TextStyle(
                        color: TemaCampo.rojo,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_sugerenciaGeofence != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _sugerenciaGeofence!,
                        style: const TextStyle(
                          color: TemaCampo.rojo,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            FilledButton.icon(
              onPressed: activo ? _ejecutarMarcaje : null,
              icon: _operando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icono),
              label: Text(etiqueta),
              style: visita.estado.esTerminal
                  ? FilledButton.styleFrom(
                      backgroundColor: TemaCampo.verde,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ acciones

  Future<void> _cargar() async {
    final dependencias = BootstrapScope.of(context);
    final visita = await dependencias.visitas.obtenerVisita(widget.visitaId);
    if (visita == null) {
      if (!mounted) return;
      mostrarMensaje(context, 'La visita ya no está disponible.', esError: true);
      Navigator.of(context).maybePop();
      return;
    }

    final centro = await dependencias.almacen.centroCostoPorId(
      visita.centroCostoId,
    );
    if (!mounted) return;

    // La visita puede cambiar mientras se cargan los anexos (por ejemplo, otro
    // item de la cola que terminó de subir), así que se vuelve a leer.
    final evidencias = await dependencias.almacen.evidenciasDe(visita.id);
    final novedades = await dependencias.visitas.novedadesDe(visita.id);
    if (!mounted) return;

    setState(() {
      _visita = visita;
      _centro = centro;
      _evidencias = evidencias;
      _novedades = novedades;
    });
  }

  /// `true` si el supervisor todavía puede modificar la visita.
  ///
  /// Cierra el checklist en cuanto hay check-out: `VisitaRepository` lo rechaza,
  /// y es mejor no ofrecer un control que va a fallar.
  bool _puedeEditar(Visita visita) =>
      !_operando && visita.tieneCheckIn && !visita.tieneCheckOut;

  Future<void> _ejecutarMarcaje() async {
    final visita = _visita;
    if (visita == null) return;

    final dependencias = BootstrapScope.of(context);

    setState(() {
      _operando = true;
      _avisoGeofence = null;
      _sugerenciaGeofence = null;
    });

    try {
      // La posición se pide antes de tocar el repositorio: si no se puede
      // leer, no tiene sentido encolar un registro sin coordenadas, porque la
      // validación geográfica es el valor de la visita.
      final lectura = await dependencias.ubicacion.leerPosicion();
      final posicion = lectura.posicion;

      if (posicion == null) {
        final fallo = lectura as PosicionNoObtenida;
        setState(() {
          _avisoGeofence = fallo.motivo;
          _sugerenciaGeofence = fallo.sugerencia;
        });
        return;
      }

      const geofence = GeofenceService();
      final centro = _centro;
      if (centro != null) {
        final resultado = geofence.evaluar(
          posicion: posicion,
          centroCosto: centro,
        );
        if (!resultado.dentroDelRadio) {
          setState(() => _avisoGeofence = resultado.mensaje);
          return;
        }
      }

      if (visita.tieneCheckIn) {
        final actualizado = await dependencias.visitas.registrarCheckOut(
          visitaId: visita.id,
          posicion: posicion,
          observaciones: visita.observaciones,
        );
        if (!mounted) return;
        mostrarMensaje(context, 'Salida registrada. Ubicación verificada.');
        setState(() => _visita = actualizado);
      } else {
        final actualizado = await dependencias.visitas.registrarCheckIn(
          visitaId: visita.id,
          posicion: posicion,
        );
        if (!mounted) return;
        mostrarMensaje(context, 'Llegada registrada. Ubicación verificada.');
        setState(() => _visita = actualizado);
      }
    } on ValidationException catch (e) {
      setState(() => _avisoGeofence = e.message);
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensaje(context, e.message, esError: true);
    } finally {
      if (mounted) setState(() => _operando = false);
    }
  }

  Future<void> _guardarActividades(List<RegistroActividad> actividades) async {
    final visita = _visita;
    if (visita == null) return;

    final dependencias = BootstrapScope.of(context);
    try {
      final actualizada = await dependencias.visitas.guardarActividades(
        visitaId: visita.id,
        actividades: actividades,
      );
      if (!mounted) return;
      setState(() => _visita = actualizada);
      mostrarMensaje(context, 'Checklist guardado en el dispositivo.');
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensaje(context, e.message, esError: true);
    }
  }

  Future<void> _tomarFoto() async {
    final visita = _visita;
    if (visita == null) return;

    final dependencias = BootstrapScope.of(context);

    String? ruta;
    try {
      ruta = await dependencias.camara.capturar(CapturaFoto.fotografiar);
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensaje(context, e.message, esError: true);
      return;
    }
    if (ruta == null || !mounted) return;

    // La foto se etiqueta con las coordenadas: es la prueba de que se tomó en
    // el sitio, y no en la oficina.
    final lectura = await dependencias.ubicacion.leerPosicion();

    try {
      await dependencias.visitas.adjuntarEvidencia(
        visitaId: visita.id,
        rutaLocal: ruta,
        ubicacion: lectura.posicion,
        comentario: 'Foto de la visita',
      );
      if (!mounted) return;
      final evidencias = await dependencias.almacen.evidenciasDe(visita.id);
      if (!mounted) return;
      setState(() => _evidencias = evidencias);
      mostrarMensaje(context, 'Foto adjunta. Se enviará al recuperar la señal.');
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensaje(context, e.message, esError: true);
    }
  }

  Future<void> _reportarNovedad() async {
    final visita = _visita;
    if (visita == null) return;

    final registrada = await NovedadFormSheet.mostrar(
      context,
      visitaId: visita.id,
      centroNombre: _centro?.nombre ?? visita.centroCostoId,
    );
    if (registrada == null || !mounted) return;

    final novedades = await BootstrapScope.of(
      context,
    ).visitas.novedadesDe(visita.id);
    if (!mounted) return;
    setState(() => _novedades = novedades);
    mostrarMensaje(
      context,
      registrada.prioridad.requiereAtencionInmediata
          ? 'Novedad de prioridad alta reportada. Se avisará al coordinador.'
          : 'Novedad guardada en el dispositivo.',
    );
  }
}

/// Título de sección con separador visual.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// Datos del centro de costo y estado de la visita.
class _EncabezadoVisita extends StatelessWidget {
  const _EncabezadoVisita({required this.visita, required this.centro});

  final Visita visita;
  final CentroCosto? centro;

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat(
      "EEEE d 'de' MMMM, yyyy",
      'es',
    ).format(visita.fechaProgramada.toLocal());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              centro?.nombre ?? visita.centroCostoId,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (centro != null && centro!.direccion.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 14, color: TemaCampo.gris),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      centro!.direccion,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TemaCampo.gris,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                InsigniaEstadoVisita(estado: visita.estado),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fecha,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Check-in, check-out y distancias validadas.
class _Marcadores extends StatelessWidget {
  const _Marcadores({required this.visita, required this.geofence});

  final Visita visita;
  final GeofenceService geofence;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            _fila(
              icono: Icons.login,
              etiqueta: 'Entrada',
              momento: visita.checkIn?.momento,
              distancia: visita.distanciaCheckInMetros,
            ),
            const Divider(),
            _fila(
              icono: Icons.logout,
              etiqueta: 'Salida',
              momento: visita.checkOut?.momento,
              distancia: visita.distanciaCheckOutMetros,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila({
    required IconData icono,
    required String etiqueta,
    required DateTime? momento,
    required double? distancia,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icono, size: 18, color: TemaCampo.gris),
          const SizedBox(width: 10),
          Text(etiqueta, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              momento == null
                  ? 'Sin registrar'
                  : DateFormat('dd/MM HH:mm').format(momento.toLocal()),
              style: TextStyle(
                fontSize: 13,
                color: momento == null ? TemaCampo.gris : null,
              ),
            ),
          ),
          if (distancia != null)
            Text(
              '${distancia.round()} m',
              style: const TextStyle(fontSize: 12.5, color: TemaCampo.verde),
            ),
        ],
      ),
    );
  }
}

/// Checklist con un control de tres estados por actividad.
class _Checklist extends StatefulWidget {
  const _Checklist({
    required this.actividades,
    required this.registros,
    required this.editable,
    required this.alCambiar,
  });

  final List<ActividadChecklist> actividades;
  final List<RegistroActividad> registros;
  final bool editable;
  final ValueChanged<List<RegistroActividad>> alCambiar;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  late Map<String, RegistroActividad> _registros = _aMapa(widget.registros);

  @override
  void didUpdateWidget(_Checklist anterior) {
    super.didUpdateWidget(anterior);
    // La visita puede llegar desde la cola con actividades ya guardadas.
    if (anterior.registros != widget.registros) {
      _registros = _aMapa(widget.registros);
    }
  }

  Map<String, RegistroActividad> _aMapa(List<RegistroActividad> lista) =>
      {for (final r in lista) r.actividadId: r};

  @override
  Widget build(BuildContext context) {
    if (widget.actividades.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Este centro de costo no tiene checklist configurado.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < widget.actividades.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _FilaActividad(
              actividad: widget.actividades[i],
              registro: _registros[widget.actividades[i].id],
              editable: widget.editable,
              alCambiar: (registro) => _cambiar(widget.actividades[i], registro),
            ),
          ],
        ],
      ),
    );
  }

  void _cambiar(ActividadChecklist actividad, RegistroActividad registro) {
    setState(() => _registros = {..._registros, actividad.id: registro});
    // Se guarda en cada cambio, no al salir de la pantalla: si el teléfono se
    // apaga a mitad del checklist, el trabajo hecho no se pierde.
    final ordenadas = _registros.values.toList()
      ..sort(
        (a, b) => widget.actividades.indexWhere(
              (x) => x.id == a.actividadId,
            ) -
            widget.actividades.indexWhere((x) => x.id == b.actividadId),
      );
    widget.alCambiar(ordenadas);
  }
}

/// Una fila del checklist con los tres resultados posibles.
class _FilaActividad extends StatelessWidget {
  const _FilaActividad({
    required this.actividad,
    required this.registro,
    required this.editable,
    required this.alCambiar,
  });

  final ActividadChecklist actividad;
  final RegistroActividad? registro;
  final bool editable;
  final ValueChanged<RegistroActividad> alCambiar;

  @override
  Widget build(BuildContext context) {
    final resultado = registro?.resultado ?? ResultadoActividad.noAplica;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  actividad.descripcion,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (actividad.requiereEvidencia)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Requiere foto como evidencia',
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: 16,
                      color: TemaCampo.ambar,
                    ),
                  ),
                ),
            ],
          ),
          if (actividad.observacion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                actividad.observacion,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
              ),
            ),
          const SizedBox(height: 8),
          // `SegmentedButton` en vez de tres botones: ocupa menos alto y el
          // estado seleccionado es visible de un vistazo, que importa cuando
          // el supervisor va con prisa.
          SegmentedButton<ResultadoActividad>(
            segments: const [
              ButtonSegment(
                value: ResultadoActividad.cumplida,
                label: Text('Cumplida'),
                icon: Icon(Icons.check, size: 16),
              ),
              ButtonSegment(
                value: ResultadoActividad.noCumplida,
                label: Text('No cumplida'),
                icon: Icon(Icons.close, size: 16),
              ),
              ButtonSegment(
                value: ResultadoActividad.noAplica,
                label: Text('N/A'),
              ),
            ],
            selected: {resultado},
            onSelectionChanged: editable
                ? (seleccion) => _cambiar(seleccion.first)
                : null,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
          ),
          if (registro?.comentario.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                registro!.comentario,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
              ),
            ),
        ],
      ),
    );
  }

  void _cambiar(ResultadoActividad resultado) {
    alCambiar(
      RegistroActividad(
        actividadId: actividad.id,
        // Se copia la descripción del catálogo para que el historial no cambie
        // si el coordinador edita el checklist después.
        descripcion: actividad.descripcion,
        resultado: resultado,
        comentario: registro?.comentario ?? '',
      ),
    );
  }
}

/// Lista de evidencias con acceso a la foto.
class _Evidencias extends StatelessWidget {
  const _Evidencias({required this.evidencias, required this.alTomar});

  final List<Evidencia> evidencias;
  final VoidCallback? alTomar;

  @override
  Widget build(BuildContext context) {
    if (evidencias.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(
                'Sin fotos todavía.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
              ),
              if (alTomar != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: alTomar,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Tomar foto'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in evidencias) ...[
              Row(
                children: [
                  Icon(
                    e.estaSincronizada
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    size: 16,
                    color: e.estaSincronizada ? TemaCampo.verde : TemaCampo.ambar,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('dd/MM HH:mm').format(e.capturadaAt.toLocal()),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    e.estaSincronizada ? 'Enviada' : 'Pendiente',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: e.estaSincronizada
                          ? TemaCampo.verde
                          : TemaCampo.ambar,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (e.ubicacion != null)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2, bottom: 6),
                  child: Text(
                    'GPS: ${e.ubicacion!.latitud.toStringAsFixed(5)}, '
                    '${e.ubicacion!.longitud.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 11, color: TemaCampo.gris),
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
            if (alTomar != null) ...[
              const Divider(),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: alTomar,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tomar otra foto'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lista de novedades reportadas en la visita.
class _Novedades extends StatelessWidget {
  const _Novedades({required this.novedades, required this.alReportar});

  final List<Novedad> novedades;
  final VoidCallback? alReportar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (novedades.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No se han reportado novedades en esta visita.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                ),
              ),
            for (final n in novedades) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.titulo,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        InsigniaPrioridad(prioridad: n.prioridad),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.descripcion,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!n.estaAbierta)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Cerrada: ${n.resolucion ?? "sin comentario"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TemaCampo.verde,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (alReportar != null) ...[
              const Divider(),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: alReportar,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Reportar novedad'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaCampo.ambar,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Extensión de lectura rápida del punto, para reuso en el formulario.
extension GeoPointLectura on GeoPoint {
  /// Texto corto de las coordenadas, para mostrar junto a la foto.
  String get etiquetaCorta =>
      '${latitud.toStringAsFixed(5)}, ${longitud.toStringAsFixed(5)}';
}
