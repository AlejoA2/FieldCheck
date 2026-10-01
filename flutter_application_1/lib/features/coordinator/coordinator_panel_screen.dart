/// Panel de control del coordinador.
///
/// ## Estructura de la pantalla
///
/// De arriba hacia abajo, en este orden deliberado:
///
/// 1. **Indicadores** — la respuesta a "¿cómo va el servicio?".
/// 2. **Filtros** — el recorte sobre lo que se va a ver.
/// 3. **Dos columnas**: la lista de visitas a la izquierda y el mapa a la
///    derecha. La lista manda porque el flujo de trabajo del coordinador es
///    "revisar visita por visita"; el mapa es la referencia visual que hace
///    evidente lo que la tabla esconde (por ejemplo, dos visitas al mismo centro
///    en la misma semana).
///
/// En pantallas estrechas las columnas se apilan y el mapa pasa a ser una
/// pestaña, porque en vertical no caben las dos cosas con tamaño legible.
///
/// ## Por qué el mapa y la lista comparten el mismo filtro
///
/// Es la misma instancia de [FiltroConsulta] la que alimenta `observarVisitas`,
/// `observarNovedades` y la exportación. Si cada uno tuviera el suyo, el
/// coordinador podría exportar un archivo que no corresponde a lo que ve, que es
/// justo el defecto que un panel de control no puede permitirse.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependencias.dart';
import '../../core/error/app_exception.dart';
import '../../core/theme/tema.dart';
import '../../core/utils/exportador_csv.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/comunes.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/filtro_consulta.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/visita.dart';
import '../../domain/services/reporte_csv.dart';
import '../auth/sesion_controller.dart';
import '../supervisor/novedad_resolucion_dialog.dart';
import 'panel_filtros.dart';
import 'panel_kpis.dart';
import 'panel_mapa.dart';
import 'visita_detalle_coordinador_screen.dart';

/// Pantalla principal del coordinador.
class CoordinatorPanelScreen extends StatelessWidget {
  const CoordinatorPanelScreen({required this.usuario, super.key});

  final AppUser usuario;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel deFieldCheck'),
        actions: [
          IconButton(
            onPressed: () => context.read<SesionController>().cerrarSesion(),
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: const _CuerpoPanel(),
    );
  }
}

/// Cuerpo del panel: escucha los streams del repositorio de consulta.
///
/// Es un `StatefulWidget` porque los tres `Stream` se reconstuyen cuando cambia
/// el filtro. No se usan `StreamBuilder` anidados porque los tres streams
/// comparten el mismo filtro y, con `StreamBuilder` por separado, un cambio de
/// filtro produciría tres recargas con estados intermedios inconsistentes entre
/// sí (por ejemplo, los KPI ya filtrados con los datos de la tabla sin filtrar).
class _CuerpoPanel extends StatefulWidget {
  const _CuerpoPanel();

  @override
  State<_CuerpoPanel> createState() => _CuerpoPanelState();
}

class _CuerpoPanelState extends State<_CuerpoPanel> {
  final List<StreamSubscription<void>> _suscripciones = [];

  FiltroConsulta _filtro = const FiltroConsulta.sinFiltros();

  List<Visita> _visitas = const [];
  List<Novedad> _novedades = const [];
  List<CentroCosto> _centros = const [];

  String? _visitaResaltadaId;
  bool _cargando = true;
  bool _exportando = false;
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    _suscribir();
  }

  @override
  void dispose() {
    for (final s in _suscripciones) {
      s.cancel();
    }
    super.dispose();
  }

  /// (Re)construye las suscripciones con el filtro actual.
  ///
  /// Se cancelan todas antes de crear las nuevas: dejar una suscripción viva
  /// sobre un filtro viejo seguiría pintando datos que ya no corresponden a lo
  /// que el coordinador ve seleccionado.
  void _suscribir() {
    for (final s in _suscripciones) {
      s.cancel();
    }
    _suscripciones.clear();

    final consulta = BootstrapScope.of(context).consulta;
    setState(() => _errorCarga = null);

    _suscripciones.add(
      consulta.observarVisitas(_filtro).listen(
        (lista) {
          if (!mounted) return;
          setState(() {
            _visitas = lista;
            _cargando = false;
          });
        },
        onError: (Object _) => _marcarError(),
      ),
    );

    _suscripciones.add(
      consulta.observarNovedades(_filtro).listen(
        (lista) {
          if (!mounted) return;
          setState(() => _novedades = lista);
        },
        onError: (Object _) => _marcarError(),
      ),
    );

    _suscripciones.add(
      consulta.observarCentros().listen(
        (lista) {
          if (!mounted) return;
          setState(() => _centros = lista);
        },
        onError: (Object _) => _marcarError(),
      ),
    );
  }

  void _marcarError() {
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _errorCarga = 'No se pudo cargar la información desde el servidor.';
    });
  }

  void _cambiarFiltro(FiltroConsulta filtro) {
    setState(() {
      _filtro = filtro;
      _cargando = true;
    });
    _suscribir();
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);

    final dependencias = BootstrapScope.of(context);
    final centrosPorId = {for (final c in _centros) c.id: c};

    try {
      // Se exporta exactamente lo que hay en pantalla, sin volver a consultar:
      // si el reporte se generara con una consulta nueva, un documento que
      // llegara entre el pintado y la exportación aparecería en el archivo sin
      // haber estado nunca en la pantalla.
      final contenido = dependencias.reporteCsv.completo(
        listaVisitas: _visitas,
        listaNovedades: _novedades,
        centrosPorId: centrosPorId,
      );

      final nombre = ReporteCsv.nombreArchivo('fieldcheck_reporte');
      final destino = await ExportadorCsv.guardar(
        nombreArchivo: nombre,
        contenido: contenido,
      );

      if (!mounted) return;
      mostrarMensaje(context, 'Reporte exportado: $destino');
    } on AppException catch (e) {
      if (!mounted) return;
      mostrarMensaje(context, e.message, esError: true);
    } catch (e, s) {
      Log.error('Fallo inesperado al exportar el reporte', e, s);
      if (!mounted) return;
      mostrarMensaje(context, 'No se pudo exportar el reporte.', esError: true);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorCarga != null) {
      return EstadoVacio(
        icono: Icons.cloud_off,
        titulo: 'Sin conexión con el servidor',
        detalle: _errorCarga!,
        accion: FilledButton.icon(
          onPressed: _suscribir,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: PanelKpis(visitas: _visitas, novedades: _novedades),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: PanelFiltros(
            filtro: _filtro,
            centros: _centros,
            alCambiar: _cambiarFiltro,
            alLimpiar: () => _cambiarFiltro(const FiltroConsulta.sinFiltros()),
            alExportar: _exportar,
            exportando: _exportando,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, restricciones) {
                    // 900 px es el umbral en el que las dos columnas siguen
                    // siendo legibles en un portátil de 13"; por debajo, el mapa
                    // y la tabla compiten por el ancho y ambos se vuelven
                    // ilegibles.
                    final dosColumnas = restricciones.maxWidth >= 900;

                    if (dosColumnas) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: _PanelLista(
                                visitas: _visitas,
                                novedades: _novedades,
                                visitaResaltadaId: _visitaResaltadaId,
                                alResaltar: (id) =>
                                    setState(() => _visitaResaltadaId = id),
                                alAbrirVisita: _abrirVisita,
                                alResolverNovedad: _resolverNovedad,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 16, 16),
                              child: _PanelMapaEnvoltura(
                                centros: _centros,
                                visitas: _visitas,
                                visitaResaltadaId: _visitaResaltadaId,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(text: 'Visitas y novedades'),
                              Tab(text: 'Mapa'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: _PanelLista(
                                    visitas: _visitas,
                                    novedades: _novedades,
                                    visitaResaltadaId: _visitaResaltadaId,
                                    alResaltar: (id) =>
                                        setState(() => _visitaResaltadaId = id),
                                    alAbrirVisita: _abrirVisita,
                                    alResolverNovedad: _resolverNovedad,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                                  child: _PanelMapaEnvoltura(
                                    centros: _centros,
                                    visitas: _visitas,
                                    visitaResaltadaId: _visitaResaltadaId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Abre el detalle de una visita.
  ///
  /// Las evidencias llegan desde el almacén local, que es donde el supervisor las
  /// guarda antes de subirlas; así el coordinador ve el conteo real y no solo lo
  /// que ya llegó al servidor.
  Future<void> _abrirVisita(Visita visita) async {
    final dependencias = BootstrapScope.of(context);

    final evidencias = await dependencias.almacen.evidenciasDe(visita.id);
    final novedades = await dependencias.almacen.novedadesDe(visita.id);

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VisitaDetalleCoordinadorScreen(
          visita: visita,
          centro: _centros.where((c) => c.id == visita.centroCostoId).firstOrNull,
          novedades: novedades,
          evidencias: evidencias,
          coordinadorId: context.read<SesionController>().supervisorId,
        ),
      ),
    );
  }

  Future<void> _resolverNovedad(Novedad novedad) async {
    final cambio = await NovedadResolucionDialog.mostrar(
      context,
      novedad: novedad,
      coordinadorId: context.read<SesionController>().supervisorId,
    );
    if (!cambio || !mounted) return;
    mostrarMensaje(context, 'Novedad actualizada.');
  }
}

/// Tarjeta con el mapa, para que el borde no choque con el fondo del panel.
class _PanelMapaEnvoltura extends StatelessWidget {
  const _PanelMapaEnvoltura({
    required this.centros,
    required this.visitas,
    required this.visitaResaltadaId,
  });

  final List<CentroCosto> centros;
  final List<Visita> visitas;
  final String? visitaResaltadaId;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PanelMapa(
        centros: centros,
        visitas: visitas,
        visitaResaltadaId: visitaResaltadaId,
      ),
    );
  }
}

/// Columna izquierda: pestañas de visitas y novedades.
class _PanelLista extends StatefulWidget {
  const _PanelLista({
    required this.visitas,
    required this.novedades,
    required this.visitaResaltadaId,
    required this.alResaltar,
    required this.alAbrirVisita,
    required this.alResolverNovedad,
  });

  final List<Visita> visitas;
  final List<Novedad> novedades;
  final String? visitaResaltadaId;
  final ValueChanged<String> alResaltar;
  final ValueChanged<Visita> alAbrirVisita;
  final ValueChanged<Novedad> alResolverNovedad;

  @override
  State<_PanelLista> createState() => _PanelListaState();
}

class _PanelListaState extends State<_PanelLista> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Visitas (${widget.visitas.length})'),
              Tab(text: 'Novedades (${widget.novedades.length})'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _ListaVisitas(
                  visitas: widget.visitas,
                  visitaResaltadaId: widget.visitaResaltadaId,
                  alResaltar: widget.alResaltar,
                  alAbrir: widget.alAbrirVisita,
                ),
                _ListaNovedades(
                  novedades: widget.novedades,
                  alResolver: widget.alResolverNovedad,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaVisitas extends StatelessWidget {
  const _ListaVisitas({
    required this.visitas,
    required this.visitaResaltadaId,
    required this.alResaltar,
    required this.alAbrir,
  });

  final List<Visita> visitas;
  final String? visitaResaltadaId;
  final ValueChanged<String> alResaltar;
  final ValueChanged<Visita> alAbrir;

  @override
  Widget build(BuildContext context) {
    if (visitas.isEmpty) {
      return const EstadoVacio(
        icono: Icons.search_off,
        titulo: 'Sin visitas para este filtro',
        detalle: 'Cambia el rango de fechas o limpia los filtros para ver más.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: visitas.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final visita = visitas[i];
        return _TarjetaVisita(
          visita: visita,
          resaltada: visita.id == visitaResaltadaId,
          onTap: () => alAbrir(visita),
          onSelect: () => alResaltar(visita.id),
        );
      },
    );
  }
}

class _TarjetaVisita extends StatelessWidget {
  const _TarjetaVisita({
    required this.visita,
    required this.resaltada,
    required this.onTap,
    required this.onSelect,
  });

  final Visita visita;
  final bool resaltada;
  final VoidCallback onTap;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final fecha = DateFormat('dd/MM/yyyy').format(visita.fechaProgramada.toLocal());

    return InkWell(
      onTap: onTap,
      onLongPress: onSelect,
      child: Container(
        color: resaltada ? esquema.primaryContainer.withValues(alpha: 0.5) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          visita.centroCostoId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InsigniaEstadoVisita(estado: visita.estado),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$fecha · ${visita.porcentajeCumplimiento.round()}% cumplimiento',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                  ),
                ],
              ),
            ),
            if (visita.syncStatus.requiereSync) ...[
              const SizedBox(width: 8),
              InsigniaSync(estado: visita.syncStatus),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListaNovedades extends StatelessWidget {
  const _ListaNovedades({required this.novedades, required this.alResolver});

  final List<Novedad> novedades;
  final ValueChanged<Novedad> alResolver;

  @override
  Widget build(BuildContext context) {
    if (novedades.isEmpty) {
      return const EstadoVacio(
        icono: Icons.verified_outlined,
        titulo: 'Sin novedades para este filtro',
        detalle: 'Las novedades que reporten los supervisores aparecerán aquí.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: novedades.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final novedad = novedades[i];
        return InkWell(
          onTap: novedad.estaAbierta ? () => alResolver(novedad) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        novedad.titulo,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${novedad.centroCostoId} · ${DateFormat('dd/MM HH:mm').format(novedad.reportadaAt.toLocal())}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                EtiquetaPrioridad(prioridad: novedad.prioridad),
              ],
            ),
          ),
        );
      },
    );
  }
}