/// Pantalla principal del supervisor.
///
/// ## Qué muestra y por qué en este orden
///
/// 1. El banner de sincronización, arriba y fijo. Es lo primero que el supervisor
///    necesita saber: si su registro anterior llegó al coordinador.
/// 2. El resumen de la jornada (completadas / en curso / sin enviar).
/// 3. La lista de visitas, ordenada por fecha programada.
///
/// ## Por qué la lista se lee de la caché local y no de Firestore
///
/// `VisitaRepository.observarVisitasAsignadas` ya emite desde la caché local
/// (Hive), no desde la red. Eso es deliberado: sin cobertura, la pantalla tiene
/// que mostrar exactamente lo mismo que con señal, y el refresco al entrar es
/// solo una mejora oportunista.
///
/// ## Por qué los nombres de los centros se cargan una vez
///
/// `AlmacenLocal` expone los centros como lista, no como stream: son datos de
/// solo lectura que no cambian durante la sesión. Se cargan al montar y se pasan
/// como mapa a las tarjetas, para que el nombre se resuelva de forma síncrona
/// durante el `build` y no haya un spinner por fila mientras se lee Hive.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependencias.dart';
import '../../core/theme/tema.dart';
import '../../core/widgets/comunes.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/centro_costo.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/visita.dart';
import '../auth/sesion_controller.dart';
import '../sync/sync_controller.dart';
import 'visita_detalle_screen.dart';

class SupervisorHomeScreen extends StatelessWidget {
  const SupervisorHomeScreen({required this.usuario, super.key});

  final AppUser usuario;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${_nombreCorto(usuario.nombre)}'),
        actions: [
          IconButton(
            onPressed: sync.enEjecucion ? null : () => sync.sincronizar(manual: true),
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar ahora',
          ),
        ],
      ),
      body: Column(
        children: [
          BannerSincronizacion(
            hayConexion: sync.hayConexion,
            pendientes: sync.pendientes,
            enEjecucion: sync.enEjecucion,
            ultimoError: sync.ultimoError,
            alReintentar: () => sync.sincronizar(manual: true),
          ),
          Expanded(
            child: _CuerpoLista(supervisorId: context.watch<SesionController>().supervisorId),
          ),
        ],
      ),
    );
  }

  /// Primer nombre, para el saludo.
  ///
  /// El nombre completo no cabe en la barra de un teléfono angosto, que es el
  /// caso normal del supervisor.
  static String _nombreCorto(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    return partes.isEmpty ? '' : partes.first;
  }
}

/// Cuerpo de la pantalla: resumen y lista de visitas.
///
/// Es un `StatefulWidget` solo para conservar los nombres de los centros entre
/// rebuilds. No guarda estado de negocio.
class _CuerpoLista extends StatefulWidget {
  const _CuerpoLista({required this.supervisorId});

  final String supervisorId;

  @override
  State<_CuerpoLista> createState() => _CuerpoListaState();
}

class _CuerpoListaState extends State<_CuerpoLista> {
  Map<String, CentroCosto> _centros = const {};

  @override
  void initState() {
    super.initState();
    _cargarCentros();
  }

  @override
  void didUpdateWidget(_CuerpoLista anterior) {
    super.didUpdateWidget(anterior);
    // Cambió el supervisor en sesión: sus centros pueden ser otros.
    if (anterior.supervisorId != widget.supervisorId) _cargarCentros();
  }

  Future<void> _cargarCentros() async {
    final almacen = BootstrapScope.of(context).almacen;
    final lista = await almacen.centrosActivos();
    if (!mounted) return;
    setState(() => _centros = {for (final c in lista) c.id: c});
  }

  @override
  Widget build(BuildContext context) {
    final repositorio = BootstrapScope.of(context).visitas;

    return StreamBuilder<List<Visita>>(
      stream: repositorio.observarVisitasAsignadas(widget.supervisorId),
      builder: (contexto, snapshot) {
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.cloud_off,
            titulo: 'No se pudieron cargar tus visitas',
            detalle: 'Revisa tu conexión e intenta de nuevo.',
            accion: FilledButton.tonalIcon(
              onPressed: _refrescar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final visitas = snapshot.data!;
        if (visitas.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refrescar,
            child: ListView(
              // `AlwaysScrollableScrollPhysics` permite tirar para actualizar
              // incluso con la lista vacía; sin esto el `RefreshIndicator` no
              // aparece y el supervisor no tiene cómo reintentar.
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EstadoVacio(
                  icono: Icons.assignment_outlined,
                  titulo: 'No tienes visitas asignadas',
                  detalle:
                      'Cuando el coordinador te asigne una visita aparecerá '
                      'aquí. Puedes seguir usando la app sin conexión.',
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refrescar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _ResumenJornada(visitas: visitas),
              const SizedBox(height: 20),
              ...visitas.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TarjetaVisita(visita: v, centros: _centros),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _refrescar() async {
    final repositorio = BootstrapScope.of(context).visitas;
    await repositorio.refrescarVisitasAsignadas(widget.supervisorId);
  }
}

/// Tarjeta resumen de la jornada.
class _ResumenJornada extends StatelessWidget {
  const _ResumenJornada({required this.visitas});

  final List<Visita> visitas;

  @override
  Widget build(BuildContext context) {
    final completadas = visitas.where((v) => v.estado.esTerminal).length;
    final enCurso = visitas
        .where((v) => v.estado == EstadoVisita.enProgreso)
        .length;
    final sinSync = visitas.where((v) => v.syncStatus.requiereSync).length;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Dato(valor: '$completadas', etiqueta: 'Completadas'),
            const _Separador(),
            _Dato(valor: '$enCurso', etiqueta: 'En curso'),
            const _Separador(),
            _Dato(valor: '$sinSync', etiqueta: 'Sin enviar'),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          valor,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: esquema.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: esquema.onPrimaryContainer.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: Theme.of(
      context,
    ).colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
  );
}

/// Tarjeta de una visita en la lista.
class _TarjetaVisita extends StatelessWidget {
  const _TarjetaVisita({required this.visita, required this.centros});

  final Visita visita;

  /// Nombres de centros indexados por id, para resolución síncrona.
  final Map<String, CentroCosto> centros;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final fecha = DateFormat('EEE d/MMM').format(visita.fechaProgramada.toLocal());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VisitaDetalleScreen(visitaId: visita.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      centros[visita.centroCostoId]?.nombre ??
                          visita.centroCostoId,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InsigniaEstadoVisita(estado: visita.estado),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 15,
                    color: esquema.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    fecha,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                  ),
                  if (visita.tieneCheckIn) ...[
                    const SizedBox(width: 14),
                    Icon(
                      Icons.login,
                      size: 15,
                      color: esquema.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(visita.checkIn!.momento.toLocal()),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                    ),
                  ],
                ],
              ),
              if (visita.hayIncumplimientos) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.report_problem_outlined,
                      size: 15,
                      color: TemaCampo.ambar,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${visita.totalIncumplidas} '
                        '${visita.totalIncumplidas == 1 ? 'actividad no cumplida' : 'actividades no cumplidas'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TemaCampo.ambar,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (visita.syncStatus.requiereSync) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InsigniaSync(estado: visita.syncStatus),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
