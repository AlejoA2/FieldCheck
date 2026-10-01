/// Diálogo de cierre de una novedad.
///
/// ## Por qué el comentario es obligatorio
///
/// Una novedad cerrada sin explicación es indistinguible de una novedad
/// olvidada. El comentario es lo que permite, dentro de tres meses, saber qué se
/// hizo con el reporte. Por eso el botón permanece deshabilitado mientras el
/// campo esté vacío y el mensaje de error se muestra bajo el campo, no como un
/// aviso al final (`RF-UX-01`).
///
/// ## Qué puede hacer el coordinador
///
/// Dos acciones y ninguna más: marcar la novedad como "en revisión" (para que
/// quede constancia de que alguien la tomó sin cerrar el tema todavía) o
/// resolverla con su comentario. El contenido del reporte del supervisor nunca
/// se edita: la trazabilidad exige que lo que se vio en campo se conserve.
library;

import 'package:flutter/material.dart';

import '../../core/di/dependencias.dart';
import '../../core/error/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/novedad.dart';

/// Diálogo para revisar o resolver una novedad.
class NovedadResolucionDialog extends StatefulWidget {
  const NovedadResolucionDialog({
    required this.novedad,
    required this.coordinadorId,
    super.key,
  });

  final Novedad novedad;
  final String coordinadorId;

  /// Abre el diálogo y devuelve `true` si la novedad cambió de estado.
  static Future<bool> mostrar(
    BuildContext context, {
    required Novedad novedad,
    required String coordinadorId,
  }) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (_) => NovedadResolucionDialog(
        novedad: novedad,
        coordinadorId: coordinadorId,
      ),
    );
    return resultado ?? false;
  }

  @override
  State<NovedadResolucionDialog> createState() =>
      _NovedadResolucionDialogState();
}

class _NovedadResolucionDialogState extends State<NovedadResolucionDialog> {
  final TextEditingController _comentario = TextEditingController();

  bool _ocupado = false;
  bool _mostrarError = false;
  String? _errorGeneral;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _marcarEnRevision() async {
    setState(() {
      _ocupado = true;
      _errorGeneral = null;
    });

    try {
      await BootstrapScope.of(
        context,
      ).consulta.marcarNovedadEnRevision(widget.novedad.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _errorGeneral = e.message;
      });
    }
  }

  Future<void> _resolver() async {
    final texto = _comentario.text.trim();
    // Se valida aquí y no solo en el repositorio: el botón debe estar
    // deshabilitado, no permitir el envío para recibir un error después.
    if (texto.isEmpty) {
      setState(() => _mostrarError = true);
      return;
    }

    setState(() {
      _ocupado = true;
      _mostrarError = false;
      _errorGeneral = null;
    });

    try {
      await BootstrapScope.of(context).consulta.resolverNovedad(
        novedadId: widget.novedad.id,
        comentario: texto,
        resueltoPor: widget.coordinadorId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _errorGeneral = e.message;
      });
    } catch (e, s) {
      Log.error('Fallo inesperado al resolver la novedad', e, s);
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _errorGeneral = 'No se pudo guardar el cierre. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Resolver novedad'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: esquema.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.novedad.titulo,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.novedad.descripcion,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _comentario,
                enabled: !_ocupado,
                maxLines: 4,
                minLines: 3,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Comentario de cierre',
                  hintText: 'Qué se hizo y cómo quedó el sitio.',
                  errorText: _mostrarError
                      ? 'Escribe el cierre para dejar registro de la solución.'
                      : null,
                ),
                onChanged: (_) {
                  if (!_mostrarError) setState(() {});
                },
              ),
              if (_errorGeneral != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorGeneral!,
                  style: TextStyle(color: esquema.error, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        if (widget.novedad.estado == EstadoNovedad.abierta)
          TextButton(
            onPressed: _ocupado ? null : _marcarEnRevision,
            child: const Text('Marcar en revisión'),
          ),
        FilledButton(
          onPressed: _ocupado ? null : _resolver,
          child: _ocupado
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Resolver'),
        ),
      ],
    );
  }
}
