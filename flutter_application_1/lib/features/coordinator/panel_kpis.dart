/// Tarjetas de indicadores del panel del coordinador.
///
/// ## Por qué los KPI se calculan sobre la lista ya filtrada
///
/// Cada cifra se deriva de las mismas listas que se pintan abajo. Es la única
/// forma de que el número de la parte de arriba y la tabla de la parte de abajo
/// nunca se contradigan: si el KPI se consultara aparte, un cambio de filtro
/// Podría tardar en verse en alguna de las dos.
///
/// ## Por qué el cumplimiento se calcula sobre visitas evaluadas
///
/// [Visita.porcentajeCumplimiento] devuelve 100 cuando no hay actividades
/// evaluadas, así que una visita sin checklist no baja el promedio del equipo.
/// Promediar sin ese cuidado castigaría al supervisor que trabaja en un centro
/// de costo que todavía no tiene plan de trabajo configurado.
library;

import 'package:flutter/material.dart';

import '../../core/theme/tema.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/novedad.dart';
import '../../domain/models/visita.dart';

/// Fila de indicadores que se adapta al ancho disponible.
class PanelKpis extends StatelessWidget {
  const PanelKpis({
    required this.visitas,
    required this.novedades,
    super.key,
  });

  final List<Visita> visitas;
  final List<Novedad> novedades;

  @override
  Widget build(BuildContext context) {
    final finalizadas = visitas.where((v) => v.estado.esTerminal).toList();
    final conChecklist = finalizadas
        .where((v) => v.actividadesEvaluadas.isNotEmpty)
        .toList();

    final cumplimiento = conChecklist.isEmpty
        ? 100.0
        : conChecklist
                  .map((v) => v.porcentajeCumplimiento)
                  .reduce((a, b) => a + b) /
              conChecklist.length;

    final abiertas = novedades.where((n) => n.estaAbierta).toList();
    final altas = abiertas.where((n) => n.prioridad.requiereAtencionInmediata);
    final incumplimientos = visitas.fold<int>(
      0,
      (total, v) => total + v.totalIncumplidas,
    );
    final sinSincronizar = visitas.where((v) => v.syncStatus.requiereSync).length;

    final tarjetas = <_Kpi>[
      _Kpi(
        etiqueta: 'Visitas',
        valor: '${visitas.length}',
        detalle: '${finalizadas.length} completadas',
        icono: Icons.assignment_turned_in_outlined,
        color: TemaCampo.azul,
      ),
      _Kpi(
        etiqueta: 'Cumplimiento',
        valor: '${cumplimiento.round()}%',
        detalle: '${conChecklist.length} visitas con checklist',
        icono: Icons.task_alt,
        color: cumplimiento >= 90 ? TemaCampo.verde : TemaCampo.ambar,
      ),
      _Kpi(
        etiqueta: 'Novedades abiertas',
        valor: '${abiertas.length}',
        detalle: '${altas.length} de prioridad alta',
        icono: Icons.campaign_outlined,
        color: altas.isNotEmpty ? TemaCampo.rojo : TemaCampo.gris,
      ),
      _Kpi(
        etiqueta: 'Actividades no cumplidas',
        valor: '$incumplimientos',
        detalle: 'en el filtro actual',
        icono: Icons.report_problem_outlined,
        color: incumplimientos > 0 ? TemaCampo.ambar : TemaCampo.verde,
      ),
      _Kpi(
        etiqueta: 'Sin sincronizar',
        valor: '$sinSincronizar',
        detalle: 'aún no llegaron al servidor',
        icono: Icons.cloud_upload_outlined,
        color: sinSincronizar > 0 ? TemaCampo.ambar : TemaCampo.verde,
      ),
    ];

    return LayoutBuilder(
      builder: (context, restricciones) {
        // Se eligen columnas a partir del ancho real, no del tipo de dispositivo:
        // el mismo panel se usa en un portátil y en una tablet, y la diferencia
        // que importa es cuánto cabe, no qué pantalla se tiene.
        final columnas = restricciones.maxWidth >= 1100
            ? 5
            : restricciones.maxWidth >= 700
            ? 3
            : 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final kpi in tarjetas)
              SizedBox(
                width:
                    (restricciones.maxWidth - 12 * (columnas - 1)) / columnas,
                child: _TarjetaKpi(kpi: kpi),
              ),
          ],
        );
      },
    );
  }
}

/// Datos de un indicador.
class _Kpi {
  const _Kpi({
    required this.etiqueta,
    required this.valor,
    required this.detalle,
    required this.icono,
    required this.color,
  });

  final String etiqueta;
  final String valor;
  final String detalle;
  final IconData icono;
  final Color color;
}

class _TarjetaKpi extends StatelessWidget {
  const _TarjetaKpi({required this.kpi});

  final _Kpi kpi;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(kpi.icono, size: 16, color: kpi.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kpi.etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: TemaCampo.gris),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              kpi.valor,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: kpi.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              kpi.detalle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta compacta de prioridad reutilizada por la lista de novedades.
///
/// Se expone aquí (y no se importa de `comunes.dart`) para no crear una
/// dependencia cruzada entre las piezas del panel.
class EtiquetaPrioridad extends StatelessWidget {
  const EtiquetaPrioridad({required this.prioridad, super.key});

  final Prioridad prioridad;

  @override
  Widget build(BuildContext context) {
    final color = switch (prioridad) {
      Prioridad.alta => TemaCampo.rojo,
      Prioridad.media => TemaCampo.ambar,
      Prioridad.baja => TemaCampo.gris,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        prioridad.etiqueta,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
