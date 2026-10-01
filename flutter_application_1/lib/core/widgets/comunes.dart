/// Widgets compartidos entre las vistas de supervisor y coordinador.
///
/// Se agrupan en un solo archivo a propósito: son piezas pequeñas de bajo
/// acoplamiento (una insignia, un estado vacío, un botón de carga) que se usan
/// en varias pantallas. Separarlas en veinte archivos de treinta líneas cada uno
/// haría más difícil encontrar la pieza correcta que leerlas juntas.
library;

import 'package:flutter/material.dart';

import '../../domain/models/enums.dart';
import '../theme/tema.dart';

/// Mapea el estado de sincronización del dominio al tono visual del tema.
///
/// El mapeo vive aquí, y no en el tema, para que `tema.dart` no dependa del
/// dominio y para que cambiar un color no toque la lógica de los estados.
SyncStatusTone tonoDeSync(SyncStatus estado) => switch (estado) {
  SyncStatus.pendiente => SyncStatusTone.pendiente,
  SyncStatus.sincronizando => SyncStatusTone.sincronizando,
  SyncStatus.sincronizado => SyncStatusTone.sincronizado,
  SyncStatus.fallido => SyncStatusTone.fallido,
};

/// Insignia de estado de sincronización.
///
/// ## Por qué siempre lleva texto
///
/// El color por sí solo no es información accesible: un usuario con
/// daltonismo no distingue el ámbar del rojo, y en la calle el brillo del sol
/// tampoco ayuda. Por eso la insignia combina color **y** etiqueta.
class InsigniaSync extends StatelessWidget {
  const InsigniaSync({required this.estado, super.key});

  final SyncStatus estado;

  @override
  Widget build(BuildContext context) {
    final tono = tonoDeSync(estado);
    final color = TemaCampo.deSyncStatus(tono);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: TemaCampo.fondoDeSyncStatus(tono),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (estado == SyncStatus.sincronizando)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            estado.etiqueta,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de estado de la visita, en el mismo estilo que [InsigniaSync].
class InsigniaEstadoVisita extends StatelessWidget {
  const InsigniaEstadoVisita({required this.estado, super.key});

  final EstadoVisita estado;

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) {
      EstadoVisita.pendiente => TemaCampo.gris,
      EstadoVisita.enProgreso => TemaCampo.azul,
      EstadoVisita.completada => TemaCampo.verde,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado.etiqueta,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Indicador de prioridad de una novedad.
class InsigniaPrioridad extends StatelessWidget {
  const InsigniaPrioridad({required this.prioridad, super.key});

  final Prioridad prioridad;

  @override
  Widget build(BuildContext context) {
    final color = switch (prioridad) {
      Prioridad.alta => TemaCampo.rojo,
      Prioridad.media => TemaCampo.ambar,
      Prioridad.baja => TemaCampo.gris,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icono(), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            prioridad.etiqueta,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _icono() => switch (prioridad) {
    Prioridad.alta => Icons.keyboard_double_arrow_up,
    Prioridad.media => Icons.keyboard_arrow_up,
    Prioridad.baja => Icons.keyboard_arrow_down,
  };
}

/// Pantalla de estado vacío.
///
/// Siempre lleva una acción: un estado vacío sin salida deja al usuario sin
/// saber qué hacer, y en el caso del supervisor eso puede significar que la
/// descarga de visitas falló y no que no tenga ninguna asignada.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
    super.key,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 56, color: esquema.outline),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: TemaCampo.gris),
            ),
            if (accion != null) ...[const SizedBox(height: 20), accion!],
          ],
        ),
      ),
    );
  }
}

/// Banner de estado de conexión y de la cola de sincronización.
///
/// Es el elemento que convierte el modo offline-first en algo **visible**: sin
/// él, el supervisor no tiene forma de saber si su registro ya llegó al
/// coordinador. Se fija arriba del contenido y nunca lo tapa.
class BannerSincronizacion extends StatelessWidget {
  const BannerSincronizacion({
    required this.hayConexion,
    required this.pendientes,
    this.enEjecucion = false,
    this.ultimoError,
    this.alReintentar,
    super.key,
  });

  final bool hayConexion;
  final int pendientes;
  final bool enEjecucion;
  final String? ultimoError;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    if (hayConexion && pendientes == 0 && !enEjecucion && ultimoError == null) {
      return const SizedBox.shrink();
    }

    final (color, fondo, mensaje) = _descripcion();

    return Material(
      color: fondo,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            if (enEjecucion)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Icon(_icono(), size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (alReintentar != null)
              TextButton(
                onPressed: alReintentar,
                style: TextButton.styleFrom(foregroundColor: color),
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }

  (Color, Color, String) _descripcion() {
    if (enEjecucion) {
      return (
        TemaCampo.azul,
        TemaCampo.azulClaro,
        'Sincronizando $pendientes registro${_plural(pendientes)}...',
      );
    }
    if (!hayConexion) {
      final sufijo = pendientes == 0
          ? 'Tus registros se guardarán en el dispositivo.'
          : '${_plural(pendientes, 'registro', 'registros')} esperando conexión.';
      return (TemaCampo.ambar, TemaCampo.ambar.withValues(alpha: 0.12), sufijo);
    }
    if (ultimoError != null) {
      return (
        TemaCampo.rojo,
        TemaCampo.rojo.withValues(alpha: 0.10),
        ultimoError!,
      );
    }
    return (
      TemaCampo.ambar,
      TemaCampo.ambar.withValues(alpha: 0.12),
      '${_plural(pendientes)} por enviar.',
    );
  }

  IconData _icono() => hayConexion ? Icons.cloud_upload_outlined : Icons.cloud_off;

  /// Concuerda el texto con la cantidad.
  ///
  /// Se centraliza aquí porque un "1 registro" mal escrito se ve descuidado
  /// justo en el banner que el supervisor lee con prisa.
  static String _plural(
    int cantidad, [
    String singular = 'registro',
    String plural = 'registros',
  ]) => '$cantidad ${cantidad == 1 ? singular : plural}';
}

/// Muestra un mensaje breve al usuario.
///
/// Reemplaza los `ScaffoldMessenger` sueltos para que todos los mensajes
/// compartan estilo y, sobre todo, para que ninguno muestre un detalle técnico.
void mostrarMensaje(BuildContext context, String mensaje, {bool esError = false}) {
  final esquema = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? esquema.error : null,
        duration: Duration(seconds: esError ? 5 : 3),
      ),
    );
}

/// Diálogo de confirmación para acciones destructivas o irreversibles.
///
/// Devuelve `true` solo si el usuario confirma explícitamente.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoConfirmar = 'Confirmar',
  String textoCancelar = 'Cancelar',
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(contexto).pop(false),
          child: Text(textoCancelar),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexto).pop(true),
          child: Text(textoConfirmar),
        ),
      ],
    ),
  );
  return respuesta ?? false;
}
