/// Mapa de cobertura del coordinador.
///
/// ## Qué muestra y por qué
///
/// Tres capas superpuestas, cada una con una pregunta distinta:
///
///  1. **Círculos de los centros de costo** con su radio de geofence. Es la
///     capa que responde "¿dónde se puede hacer check-in?": un círculo fuera de
///     la zona azul significa que el supervisor no podía registrar su llegada
///     allí, y eso es un hallazgo, no un error de dibujo.
///  2. **Marcadores de visita**, coloreados por estado. Responde "¿qué se hizo
///     en cada sitio?".
///  3. **Línea desde el centro hasta el check-in**, cuando ambos existen.
///     Responde "¿el supervisor realmente se movió hasta el centro o solo se
///     Acercó a la esquina?". Es la lectura visual de la validación geográfica.
///
/// ## Por qué las teselas son de OpenStreetMap
///
/// Son las más adecuadas para un prototipo que se despliega en una red de
/// empresa: no requieren clave de API ni cuenta de facturación. La capa lleva
/// la atribución obligatoria de OSM.
///
/// La advertencia es real y está en el código: los servidores públicos de OSM
/// no están pensados para uso intensivo. Si el panel pasara a producción con
/// muchos usuarios simultáneos, la capa de teselas debe cambiarse por un
/// proveedor con contrato (MapTiler, Stadia, Mapbox), que es un cambio de una
/// sola línea en este archivo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/tema.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/geo_point.dart';
import '../../domain/models/visita.dart';

/// Mapa con los centros de costo y las visitas del filtro activo.
class PanelMapa extends StatefulWidget {
  const PanelMapa({
    required this.centros,
    required this.visitas,
    this.visitaResaltadaId,
    super.key,
  });

  final List<CentroCosto> centros;
  final List<Visita> visitas;

  /// Visita enfocada desde la lista: el mapa se acerca a ella.
  final String? visitaResaltadaId;

  @override
  State<PanelMapa> createState() => _PanelMapaState();
}

class _PanelMapaState extends State<PanelMapa> {
  final MapController _controlador = MapController();

  /// Se guarda el punto al que ya se movió el mapa.
  ///
  /// Sin esta marca, cada rebuild del filtro vuelve a centrar el mapa y el
  /// coordinador pierde la posición en la que estaba leyendo.
  String? _ultimoFoco;

  static const _urlTeselas = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void didUpdateWidget(PanelMapa anterior) {
    super.didUpdateWidget(anterior);
    final objetivo = widget.visitaResaltadaId;
    if (objetivo != null && objetivo != _ultimoFoco) {
      _enfocar(objetivo);
    }
  }

  void _enfocar(String visitaId) {
    final visita = widget.visitas.where((v) => v.id == visitaId).firstOrNull;
    final centro = visita == null
        ? null
        : widget.centros.where((c) => c.id == visita.centroCostoId).firstOrNull;
    final punto = visita?.checkIn?.posicion ?? centro?.ubicacion;
    if (punto == null) return;

    _ultimoFoco = visitaId;
    _controlador.move(LatLng(punto.latitud, punto.longitud), 16.5);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.centros.isEmpty && widget.visitas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay centros de costo ni visitas para mostrar.'),
        ),
      );
    }

    return FlutterMap(
      mapController: _controlador,
      options: MapOptions(
        initialCenter: _centroInicial(),
        initialZoom: 12,
        minZoom: 3,
        maxZoom: 18,
        onTap: (posicion, punto) => _enfocarEn(punto),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _urlTeselas,
          userAgentPackageName: 'com.fieldcheck.app',
        ),

        // Geofence: el área en la que un check-in es válido.
        CircleLayer(
          circles: [
            for (final centro in widget.centros)
              CircleMarker(
                point: LatLng(centro.ubicacion.latitud, centro.ubicacion.longitud),
                radius: centro.radioToleranciaMetros,
                useRadiusInMeter: true,
                color: TemaCampo.azul.withValues(alpha: 0.08),
                borderColor: TemaCampo.azul.withValues(alpha: 0.55),
                borderStrokeWidth: 1.5,
              ),
          ],
        ),

        // Trayecto real: centro de referencia -> punto del check-in.
        PolylineLayer(
          polylines: _trazos(14),
        ),
        PolylineLayer(
          polylines: _trazos(6),
        ),

        MarkerLayer(markers: [_mapaCentros(), ..._marcadoresVisitas()]),

        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  /// Dos polilíneas superpuestas: una gruesa y clara debajo, otra fina y
  /// marcada encima. Es el mismo camino con halo, y evita el clásico trazo negro
  /// que desaparece sobre el asfalto del mapa.
  List<Polyline> _trazos(double ancho) {
    final color = ancho > 10
        ? Colors.white.withValues(alpha: 0.85)
        : TemaCampo.ambar.withValues(alpha: 0.9);

    return [
      for (final visita in widget.visitas)
        if (_trazado(visita) case final puntos?)
          Polyline(points: puntos, strokeWidth: ancho, color: color),
    ];
  }

  /// Centro y check-in de una visita, o `null` si falta alguno de los dos.
  List<LatLng>? _trazado(Visita visita) {
    final entrada = visita.checkIn?.posicion;
    final centro = widget.centros
        .where((c) => c.id == visita.centroCostoId)
        .firstOrNull;
    if (entrada == null || centro == null) return null;
    return [
      LatLng(centro.ubicacion.latitud, centro.ubicacion.longitud),
      LatLng(entrada.latitud, entrada.longitud),
    ];
  }

  /// Marcador del centro de costo, con su nombre.
  Marker _mapaCentros() {
    // El marcador del centro se ancla a la esquina superior izquierda del
    // círculo: ponerlo en el centro taparía el punto real del check-in, que es
    // la información que el coordinador viene a mirar.
    final primero = widget.centros.first;
    return Marker(
      key: ValueKey('centro-${primero.id}'),
      point: LatLng(primero.ubicacion.latitud, primero.ubicacion.longitud),
      width: 168,
      height: 26,
      alignment: Alignment.topLeft,
      child: _EtiquetaMapa(
        texto: primero.nombre,
        fondo: TemaCampo.azul,
      ),
    );
  }

  List<Marker> _marcadoresVisitas() => [
    for (final visita in widget.visitas)
      if (visita.checkIn?.posicion case final punto?)
        Marker(
          key: ValueKey('visita-${visita.id}'),
          point: LatLng(punto.latitud, punto.longitud),
          width: 30,
          height: 30,
          child: _PinVisita(
            estado: visita.estado,
            resaltada: visita.id == widget.visitaResaltadaId,
          ),
        ),
  ];

  /// Centra el mapa en el punto tocado, para revisar una zona concreta.
  void _enfocarEn(LatLng punto) => _controlador.move(punto, 15);

  /// Centro inicial: el promedio de los centros si los hay, o el primero que
  /// aparezca. El promedio evita que un centro en el norte de la ciudad deje al
  /// resto del mapa fuera de la vista inicial.
  LatLng _centroInicial() {
    final List<GeoPoint> puntos = [
      if (widget.centros.isNotEmpty)
        ...widget.centros.map((c) => c.ubicacion)
      else
        ...widget.visitas
            .map((v) => v.checkIn?.posicion)
            .whereType<GeoPoint>(),
    ];
    if (puntos.isEmpty) return const LatLng(4.7110, -74.0721);

    final lat =
        puntos.map((p) => p.latitud).reduce((a, b) => a + b) / puntos.length;
    final lng =
        puntos.map((p) => p.longitud).reduce((a, b) => a + b) / puntos.length;
    return LatLng(lat, lng);
  }
}

/// Etiqueta rectangular con el nombre del centro de costo.
class _EtiquetaMapa extends StatelessWidget {
  const _EtiquetaMapa({required this.texto, required this.fondo});

  final String texto;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Pin de una visita, coloreado por estado.
///
/// El color va acompañado de forma: los estados usan iconos distintos porque el
/// mapa es el lugar donde menos texto cabe, y el requisito de accesibilidad del
/// proyecto (`RNF-ACC-02`) pide que el estado no dependa solo del color.
class _PinVisita extends StatelessWidget {
  const _PinVisita({required this.estado, required this.resaltada});

  final EstadoVisita estado;
  final bool resaltada;

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (estado) {
      EstadoVisita.pendiente => (TemaCampo.gris, Icons.schedule),
      EstadoVisita.enProgreso => (TemaCampo.ambar, Icons.play_arrow),
      EstadoVisita.completada => (TemaCampo.verde, Icons.check),
    };

    return Tooltip(
      message: estado.etiqueta,
      child: Container(
        decoration: BoxDecoration(
          color: resaltada ? color : color.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(
            color: resaltada ? Colors.white : Colors.white.withValues(alpha: 0.6),
            width: resaltada ? 3 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: resaltada ? 6 : 2,
            ),
          ],
        ),
        child: Icon(icono, size: 16, color: Colors.white),
      ),
    );
  }
}