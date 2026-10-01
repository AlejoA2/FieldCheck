/// Detalle de una visita visto por el coordinador.
///
/// ## Qué cambia respecto a la vista del supervisor
///
/// La misma visita se ve desde dos lados del flujo, y la diferencia no es
/// estética sino de permisos:
///
///  - El supervisor **crea** los registros. El coordinador solo los lee y, sobre
///    las novedades, avanza el estado (revisión → resuelta).
///  - El supervisor ve un botón grande de "Registrar llegada/salida". Aquí no
///    hay ningún botón de ese tipo: el geofence ya se validó en el dispositivo y
///    las distancias ya vienen guardadas. Volver a pedirle una posición al
///    coordinador no aportaría nada y además falsearía la evidencia.
///
/// ## Por qué el coordinador no ve las fotos
///
/// Las evidencias se suben a Storage y se asocian a la visita por id. Enruta la
/// versión vigente del panel no se cargan: mostrarlas exigiría resolver las URLs
/// de descarga y el conteo ya aparece en la ficha, que es lo que el coordinador
/// necesita para decidir si abre el detalle operativo.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tema.dart';
import '../../core/widgets/comunes.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/evidencia.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/visita.dart';
import '../supervisor/novedad_resolucion_dialog.dart';

/// Ficha de una visita para el coordinador.
class VisitaDetalleCoordinadorScreen extends StatelessWidget {
  const VisitaDetalleCoordinadorScreen({
    required this.visita,
    required this.centro,
    required this.novedades,
    required this.evidencias,
    required this.coordinadorId,
    super.key,
  });

  final Visita visita;
  final CentroCosto? centro;
  final List<Novedad> novedades;
  final List<Evidencia> evidencias;

  /// Id del coordinador en sesión, para firmar el cierre de una novedad.
  final String coordinadorId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(centro?.nombre ?? visita.centroCostoId),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: InsigniaEstadoVisita(estado: visita.estado)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _ResumenAuditoria(visita: visita, centro: centro),
          const SizedBox(height: 16),
          _MarcajePanel(visita: visita),
          const SizedBox(height: 16),
          _Seccion(
            titulo: 'Resultado del checklist',
            child: _Checklist(
              visita: visita,
              actividades: centro?.actividades ?? const [],
            ),
          ),
          const SizedBox(height: 16),
          _Seccion(
            titulo: 'Evidencias (${evidencias.length})',
            child: _Evidencias(evidencias: evidencias),
          ),
          const SizedBox(height: 16),
          _Seccion(
            titulo: 'Novedades reportadas (${novedades.length})',
            child: _Novedades(
              novedades: novedades,
              coordinadorId: coordinadorId,
            ),
          ),
          if (visita.observaciones.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Seccion(
              titulo: 'Observaciones de la visita',
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(visita.observaciones),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fecha, estado de sincronización y cumplimiento.
class _ResumenAuditoria extends StatelessWidget {
  const _ResumenAuditoria({required this.visita, required this.centro});

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
              fecha,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (centro != null && centro!.direccion.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                centro!.direccion,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _Metrica(
                  etiqueta: 'Cumplimiento',
                  valor: '${visita.porcentajeCumplimiento.round()}%',
                ),
                const SizedBox(width: 20),
                _Metrica(
                  etiqueta: 'Cumplidas',
                  valor: '${visita.totalCumplidas}',
                ),
                const SizedBox(width: 20),
                _Metrica(
                  etiqueta: 'No cumplidas',
                  valor: '${visita.totalIncumplidas}',
                ),
                const SizedBox(width: 20),
                _Metrica(
                  etiqueta: 'Duración',
                  valor: visita.duracion == null
                      ? 'En curso'
                      : '${visita.duracion!.inMinutes} min',
                ),
              ],
            ),
            if (visita.syncStatus.requiereSync) ...[
              const SizedBox(height: 12),
              InsigniaSync(estado: visita.syncStatus),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          valor,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          etiqueta,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: TemaCampo.gris),
        ),
      ],
    );
  }
}

/// Check-in, check-out y distancia validada contra el geofence.
class _MarcajePanel extends StatelessWidget {
  const _MarcajePanel({required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context) {
    final radio = visita.tieneCheckIn || visita.tieneCheckOut;

    return _Seccion(
      titulo: 'Marcajes y validación geográfica',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              _fila(
                icono: Icons.login,
                etiqueta: 'Entrada',
                momento: visita.checkIn?.momento,
                distancia: visita.distanciaCheckInMetros,
              ),
              if (radio) const Divider(),
              _fila(
                icono: Icons.logout,
                etiqueta: 'Salida',
                momento: visita.checkOut?.momento,
                distancia: visita.distanciaCheckOutMetros,
              ),
            ],
          ),
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
                  : DateFormat(
                      'dd/MM/yyyy HH:mm',
                      'es',
                    ).format(momento.toLocal()),
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

/// Resultados del checklist como tabla de solo lectura.
class _Checklist extends StatelessWidget {
  const _Checklist({required this.visita, required this.actividades});

  final Visita visita;
  final List<ActividadChecklist> actividades;

  @override
  Widget build(BuildContext context) {
    if (visita.actividades.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'El supervisor no registró resultados de checklist en esta visita.',
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
          for (var i = 0; i < visita.actividades.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _FilaResultado(registro: visita.actividades[i]),
          ],
        ],
      ),
    );
  }
}

class _FilaResultado extends StatelessWidget {
  const _FilaResultado({required this.registro});

  final RegistroActividad registro;

  @override
  Widget build(BuildContext context) {
    final (icono, color, etiqueta) = switch (registro.resultado) {
      ResultadoActividad.cumplida => (
        Icons.check_circle,
        TemaCampo.verde,
        'Cumplida',
      ),
      ResultadoActividad.noCumplida => (
        Icons.cancel,
        TemaCampo.rojo,
        'No cumplida',
      ),
      ResultadoActividad.noAplica => (Icons.remove_circle_outline, TemaCampo.gris, 'No aplica'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(registro.descripcion),
                if (registro.comentario.isNotEmpty)
                  Text(
                    registro.comentario,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            etiqueta,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Lista de evidencias de la visita.
class _Evidencias extends StatelessWidget {
  const _Evidencias({required this.evidencias});

  final List<Evidencia> evidencias;

  @override
  Widget build(BuildContext context) {
    if (evidencias.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Sin evidencias registradas.',
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
          for (var i = 0; i < evidencias.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.photo_camera_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      DateFormat(
                        'dd/MM/yyyy HH:mm',
                        'es',
                      ).format(evidencias[i].capturadaAt.toLocal()),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    evidencias[i].estaSincronizada ? 'Enviada' : 'Pendiente',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: evidencias[i].estaSincronizada
                          ? TemaCampo.verde
                          : TemaCampo.ambar,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Novedades de la visita, con la acción de cierre del coordinador.
class _Novedades extends StatelessWidget {
  const _Novedades({required this.novedades, required this.coordinadorId});

  final List<Novedad> novedades;
  final String coordinadorId;

  @override
  Widget build(BuildContext context) {
    if (novedades.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Esta visita no tiene novedades reportadas.',
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
          for (var i = 0; i < novedades.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _FilaNovedad(novedad: novedades[i], coordinadorId: coordinadorId),
          ],
        ],
      ),
    );
  }
}

class _FilaNovedad extends StatelessWidget {
  const _FilaNovedad({required this.novedad, required this.coordinadorId});

  final Novedad novedad;
  final String coordinadorId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  novedad.titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              InsigniaPrioridad(prioridad: novedad.prioridad),
              const SizedBox(width: 8),
              Text(
                novedad.estado.etiqueta,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: TemaCampo.gris),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(novedad.descripcion),
          if (novedad.accionesTomadas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Acciones: ${novedad.accionesTomadas.join(', ')}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
            ),
          ],
          if (!novedad.estaAbierta) ...[
            const SizedBox(height: 6),
            Text(
              'Cerrada: ${novedad.resolucion ?? "sin comentario"}',
              style: const TextStyle(fontSize: 12, color: TemaCampo.verde),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => NovedadResolucionDialog.mostrar(
                  context,
                  novedad: novedad,
                  coordinadorId: coordinadorId,
                ),
                icon: const Icon(Icons.task_alt, size: 18),
                label: const Text('Resolver novedad'),
              ),
            ),
          ],
        ],
      ),
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
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}