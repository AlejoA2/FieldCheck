/// Panel de filtros del coordinador.
///
/// ## Por qué los filtros viven aquí y no en la barra de la app
///
/// El filtro no es una navegación: es un recorte sobre los mismos datos que ya
/// se están viendo. Por eso vive en una tarjeta encima de las listas y su
/// efecto es inmediato, sin cambiar de pantalla.
///
/// ## El filtro activo siempre es visible
///
/// El botón "Limpiar" aparece solo cuando hay algo que limpiar, y cada control
/// que tiene valor seleccionado lo muestra. Un panel con cuatro filtros
/// aplicados a la vista y ninguno visible obliga al coordinador a probar uno por
/// uno para saber qué está viendo.
library;

import 'package:flutter/material.dart';

import '../../core/theme/tema.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/filtro_consulta.dart';

/// Tarjeta con los controles de filtrado.
class PanelFiltros extends StatelessWidget {
  const PanelFiltros({
    required this.filtro,
    required this.centros,
    required this.alCambiar,
    required this.alLimpiar,
    required this.alExportar,
    this.exportando = false,
    super.key,
  });

  final FiltroConsulta filtro;
  final List<CentroCosto> centros;
  final ValueChanged<FiltroConsulta> alCambiar;
  final VoidCallback alLimpiar;
  final VoidCallback alExportar;
  final bool exportando;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Filtros',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: filtro.estaVacio ? null : alLimpiar,
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Limpiar'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  onPressed: exportando ? null : alExportar,
                  icon: exportando
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Exportar CSV'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _CampoFecha(
                  rango: filtro.rango,
                  alCambiar: (r) => alCambiar(_conRango(r)),
                ),
                _CampoCentro(
                  valor: filtro.centroCostoId,
                  centros: centros,
                  alCambiar: (id) => alCambiar(filtro.copyWith(centroCostoId: id)),
                ),
                _CampoEstadoVisita(
                  valor: filtro.estadoVisita,
                  alCambiar: (e) => alCambiar(filtro.copyWith(estadoVisita: e)),
                ),
                _CampoPrioridad(
                  valor: filtro.prioridad,
                  alCambiar: (p) => alCambiar(filtro.copyWith(prioridad: p)),
                ),
                _Interruptor(
                  etiqueta: 'Sin sincronizar',
                  valor: filtro.soloPendientesDeSync,
                  onChanged: (v) =>
                      alCambiar(filtro.copyWith(soloPendientesDeSync: v)),
                ),
                _Interruptor(
                  etiqueta: 'Con incumplimientos',
                  valor: filtro.soloConIncumplimientos,
                  onChanged: (v) =>
                      alCambiar(filtro.copyWith(soloConIncumplimientos: v)),
                ),
              ],
            ),
            if (!filtro.estaVacio) ...[
              const SizedBox(height: 10),
              _ResumenFiltro(filtro: filtro),
            ],
          ],
        ),
      ),
    );
  }

  /// `copyWith` no puede poner `null`, así que para el rango se decide el valor
  /// antes de llamar: si no hay rango nuevo, se limpia con [FiltroConsulta.limpiar]
  /// reconstruido desde cero.
  FiltroConsulta _conRango(RangoFechas? rango) => FiltroConsulta(
    rango: rango,
    supervisorId: filtro.supervisorId,
    centroCostoId: filtro.centroCostoId,
    estadoVisita: filtro.estadoVisita,
    estadoNovedad: filtro.estadoNovedad,
    prioridad: filtro.prioridad,
    soloPendientesDeSync: filtro.soloPendientesDeSync,
    soloConIncumplimientos: filtro.soloConIncumplimientos,
  );
}

/// Texto que resume el filtro en una línea, para que el coordinador confirme de
/// un vistazo qué está viendo sin inspeccionar cada control.
class _ResumenFiltro extends StatelessWidget {
  const _ResumenFiltro({required this.filtro});

  final FiltroConsulta filtro;

  @override
  Widget build(BuildContext context) {
    final partes = <String>[
      if (filtro.rango != null) 'Rango ${filtro.rango!.etiqueta}',
      if (filtro.centroCostoId != null) 'Centro seleccionado',
      if (filtro.supervisorId != null) 'Supervisor ${filtro.supervisorId}',
      if (filtro.estadoVisita != null) 'Estado ${filtro.estadoVisita!.etiqueta}',
      if (filtro.estadoNovedad != null)
        'Novedad ${filtro.estadoNovedad!.etiqueta}',
      if (filtro.prioridad != null) 'Prioridad ${filtro.prioridad!.etiqueta}',
      if (filtro.soloPendientesDeSync) 'Solo sin sincronizar',
      if (filtro.soloConIncumplimientos) 'Solo con incumplimientos',
    ];

    return Row(
      children: [
        const Icon(Icons.info_outline, size: 14, color: TemaCampo.gris),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            partes.join(' · '),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
          ),
        ),
      ],
    );
  }
}

/// Selector de rango de fechas.
class _CampoFecha extends StatelessWidget {
  const _CampoFecha({required this.rango, required this.alCambiar});

  final RangoFechas? rango;
  final ValueChanged<RangoFechas?> alCambiar;

  @override
  Widget build(BuildContext context) {
    final etiqueta = rango == null ? 'Todas las fechas' : rango!.etiqueta;

    return OutlinedButton.icon(
      onPressed: () => _elegir(context),
      icon: const Icon(Icons.date_range_outlined, size: 18),
      label: Text(etiqueta),
    );
  }

  Future<void> _elegir(BuildContext context) async {
    final ahora = DateTime.now();
    // Sin rango previo se ofrecen los últimos 30 días: es el intervalo que el
    // coordinador revisa normalmente y evita tener que definir fechas a mano
    // para el uso más común.
    final inicial =
        rango ??
        RangoFechas(desde: ahora.subtract(const Duration(days: 30)), hasta: ahora);

    final elegido = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: DateTime(inicial.desde.year, inicial.desde.month, inicial.desde.day),
        end: DateTime(inicial.hasta.year, inicial.hasta.month, inicial.hasta.day),
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(ahora.year + 1, 12, 31),
      helpText: 'Filtrar visitas por fecha programada',
      saveText: 'Aplicar',
    );

    if (elegido == null) return;
    alCambiar(RangoFechas(desde: elegido.start, hasta: elegido.end));
  }
}

/// Selector de centro de costo.
class _CampoCentro extends StatelessWidget {
  const _CampoCentro({
    required this.valor,
    required this.centros,
    required this.alCambiar,
  });

  final String? valor;
  final List<CentroCosto> centros;
  final ValueChanged<String?> alCambiar;

  @override
  Widget build(BuildContext context) {
    final nombreSeleccionado = centros
        .where((c) => c.id == valor)
        .map((c) => c.nombre)
        .firstOrNull;

    return _Desplegable<String>(
      etiqueta: nombreSeleccionado ?? 'Todos los centros',
      icono: Icons.storefront_outlined,
      alAbrir: (cerrar) => Column(children: [
        _Opcion(
          texto: 'Todos los centros',
          seleccionado: valor == null,
          alElegir: () {
            alCambiar(null);
            cerrar();
          },
        ),
        for (final centro in centros)
          _Opcion(
            texto: centro.nombre,
            seleccionado: centro.id == valor,
            alElegir: () {
              alCambiar(centro.id);
              cerrar();
            },
          ),
      ]),
    );
  }
}

/// Selector de estado de visita.
class _CampoEstadoVisita extends StatelessWidget {
  const _CampoEstadoVisita({required this.valor, required this.alCambiar});

  final EstadoVisita? valor;
  final ValueChanged<EstadoVisita?> alCambiar;

  @override
  Widget build(BuildContext context) {
    return _Desplegable<EstadoVisita>(
      etiqueta: valor?.etiqueta ?? 'Cualquier estado',
      icono: Icons.flag_outlined,
      alAbrir: (cerrar) => Column(children: [
        _Opcion(
          texto: 'Cualquier estado',
          seleccionado: valor == null,
          alElegir: () {
            alCambiar(null);
            cerrar();
          },
        ),
        for (final estado in EstadoVisita.values)
          _Opcion(
            texto: estado.etiqueta,
            seleccionado: estado == valor,
            alElegir: () {
              alCambiar(estado);
              cerrar();
            },
          ),
      ]),
    );
  }
}

/// Selector de prioridad de novedad.
class _CampoPrioridad extends StatelessWidget {
  const _CampoPrioridad({required this.valor, required this.alCambiar});

  final Prioridad? valor;
  final ValueChanged<Prioridad?> alCambiar;

  @override
  Widget build(BuildContext context) {
    return _Desplegable<Prioridad>(
      etiqueta: valor == null ? 'Cualquier prioridad' : 'Prioridad ${valor!.etiqueta}',
      icono: Icons.priority_high,
      alAbrir: (cerrar) => Column(children: [
        _Opcion(
          texto: 'Cualquier prioridad',
          seleccionado: valor == null,
          alElegir: () {
            alCambiar(null);
            cerrar();
          },
        ),
        for (final prioridad in Prioridad.values)
          _Opcion(
            texto: prioridad.etiqueta,
            seleccionado: prioridad == valor,
            alElegir: () {
              alCambiar(prioridad);
              cerrar();
            },
          ),
      ]),
    );
  }
}

/// Menú desplegable con el patrón "botón + lista de opciones".
///
/// Se construye a mano en vez de usar `DropdownButton` porque hace falta
/// soporte de "cualquiera" (que en `DropdownButton` se resuelve con un item
/// falso con `null`) y de un ancho constante entre controles, para que la fila
/// de filtros se vea alineada.
class _Desplegable<T> extends StatelessWidget {
  const _Desplegable({
    required this.etiqueta,
    required this.icono,
    required this.alAbrir,
  });

  final String etiqueta;
  final IconData icono;
  final Widget Function(void Function() cerrar) alAbrir;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _mostrar(context),
      icon: Icon(icono, size: 18),
      label: Text(etiqueta),
    );
  }

  void _mostrar(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (contexto) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                etiqueta,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: alAbrir(() => Navigator.of(contexto).pop()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Una opción del desplegable.
class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.texto,
    required this.seleccionado,
    required this.alElegir,
  });

  final String texto;
  final bool seleccionado;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(texto),
      trailing: seleccionado
          ? Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: alElegir,
    );
  }
}

/// Casilla de activacion para los filtros booleanos.
class _Interruptor extends StatelessWidget {
  const _Interruptor({
    required this.etiqueta,
    required this.valor,
    required this.onChanged,
  });

  final String etiqueta;
  final bool valor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(etiqueta),
      avatar: Icon(
        valor ? Icons.check_circle : Icons.circle_outlined,
        size: 17,
        color: valor ? TemaCampo.azul : TemaCampo.gris,
      ),
      selected: valor,
      onSelected: onChanged,
    );
  }
}

