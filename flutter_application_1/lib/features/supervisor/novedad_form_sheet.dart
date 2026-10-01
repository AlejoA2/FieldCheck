/// Formulario de reporte de novedad, como hoja modal.
///
/// ## Por qué una hoja y no una pantalla completa
///
/// El supervisor reporta la novedad **en medio de la visita**, con las manos
/// ocupadas y el checklist a medio hacer. Abrir una pantalla nueva lo saca del
/// contexto: una hoja modal se cierra con el mismo gesto con el que se abrió y
/// lo devuelve exactamente donde estaba.
///
/// ## La prioridad se elige antes de escribir
///
/// La prioridad no es un detalle menor: una novedad de prioridad alta
/// dispara la notificación al coordinador de inmediato. Por eso el control de
/// prioridad va arriba, con una explicación de qué significa cada nivel, y no al
/// final como un campo más.
///
/// ## Validación
///
/// Cumple `RF-UX-01`: título y descripción se validan bajo su campo, con
/// mensajes concretos, y el botón de enviar se deshabilita mientras falte
/// cualquiera de los dos.
library;

import 'package:flutter/material.dart';

import '../../core/di/dependencias.dart';
import '../../core/error/app_exception.dart';
import '../../core/theme/tema.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/novedad.dart';

/// Hoja modal para reportar una novedad dentro de una visita.
class NovedadFormSheet extends StatefulWidget {
  const NovedadFormSheet({
    required this.visitaId,
    required this.centroNombre,
    super.key,
  });

  final String visitaId;

  /// Nombre del centro de costo, mostrado en el encabezado.
  final String centroNombre;

  /// Abre la hoja y devuelve la novedad reportada, o `null` si se canceló.
  static Future<Novedad?> mostrar(
    BuildContext context, {
    required String visitaId,
    required String centroNombre,
  }) {
    return showModalBottomSheet<Novedad>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          NovedadFormSheet(visitaId: visitaId, centroNombre: centroNombre),
    );
  }

  @override
  State<NovedadFormSheet> createState() => _NovedadFormSheetState();
}

class _NovedadFormSheetState extends State<NovedadFormSheet> {
  final GlobalKey<FormState> _formulario = GlobalKey<FormState>();
  final TextEditingController _titulo = TextEditingController();
  final TextEditingController _descripcion = TextEditingController();
  final TextEditingController _acciones = TextEditingController();

  Prioridad _prioridad = Prioridad.media;
  bool _enviando = false;
  String? _errorGeneral;

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _acciones.dispose();
    super.dispose();
  }

  /// `true` cuando hay lo mínimo para enviar.
  bool get _puedeEnviar =>
      !_enviando && _titulo.text.trim().isNotEmpty && _descripcion.text.trim().isNotEmpty;

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!(_formulario.currentState?.validate() ?? false)) return;

    setState(() {
      _enviando = true;
      _errorGeneral = null;
    });

    final textoAcciones = _acciones.text
        .split('\n')
        .map((linea) => linea.trim())
        .where((linea) => linea.isNotEmpty)
        .toList();

    try {
      final novedad = await BootstrapScope.of(context).visitas.reportarNovedad(
        visitaId: widget.visitaId,
        titulo: _titulo.text.trim(),
        descripcion: _descripcion.text.trim(),
        prioridad: _prioridad,
        accionesTomadas: textoAcciones,
      );
      if (!mounted) return;
      Navigator.of(context).pop(novedad);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorGeneral = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // El teclado cubre la parte baja de la hoja; sin este margen el botón de
    // enviar queda debajo del teclado y el supervisor no ve que se envió.
    final alturaTeclado = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: alturaTeclado),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controlador) {
          return Form(
            key: _formulario,
            child: Column(
              children: [
                const _Handle(),
                _Encabezado(centroNombre: widget.centroNombre),
                Expanded(
                  child: ListView(
                    controller: controlador,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _SelectorPrioridad(
                        valor: _prioridad,
                        habilitado: !_enviando,
                        alCambiar: (p) => setState(() => _prioridad = p),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _titulo,
                        enabled: !_enviando,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Título',
                          hintText: 'Ej. Puerta principal sin llave',
                          prefixIcon: Icon(Icons.title),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _validarTitulo,
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _descripcion,
                        enabled: !_enviando,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                          hintText:
                              'Qué se encontró, en qué área y si el sitio sigue '
                              'operando con normalidad.',
                          alignLabelWithHint: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _validarDescripcion,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _acciones,
                        enabled: !_enviando,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Acciones tomadas (opcional)',
                          hintText: 'Una por línea',
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (_errorGeneral != null) ...[
                        const SizedBox(height: 14),
                        _Aviso(mensaje: _errorGeneral!),
                      ],
                    ],
                  ),
                ),
                _Pie(
                  enviando: _enviando,
                  habilitado: _puedeEnviar,
                  onEnviar: _enviar,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _validarTitulo(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Escribe un título corto que resuma la novedad.';
    if (texto.length < 5) return 'El título es demasiado corto para ser útil.';
    return null;
  }

  String? _validarDescripcion(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Describe qué encontraste.';
    if (texto.length < 15) {
      return 'Agrega un poco más de detalle: qué, dónde y desde cuándo.';
    }
    return null;
  }
}

/// Asa de arrastre: indica que la hoja se puede ajustar en alto.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      height: 4,
      width: 40,
      decoration: BoxDecoration(
        color: TemaCampo.gris.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Encabezado con el centro de costo donde ocurre la novedad.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.centroNombre});

  final String centroNombre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reportar novedad',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  centroNombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar sin reportar',
          ),
        ],
      ),
    );
  }
}

/// Selección de prioridad con explicación del efecto de cada nivel.
///
/// No es un `SegmentedButton` genérico porque cada nivel tiene un
/// consecuencia distinta y el supervisor debe elegir con esa información a la
/// vista.
class _SelectorPrioridad extends StatelessWidget {
  const _SelectorPrioridad({
    required this.valor,
    required this.habilitado,
    required this.alCambiar,
  });

  final Prioridad valor;
  final bool habilitado;
  final ValueChanged<Prioridad> alCambiar;

  static const Map<Prioridad, String> _descripciones = {
    Prioridad.alta: 'Se avisa al coordinador de inmediato.',
    Prioridad.media: 'Se revisa en el reporte del día.',
    Prioridad.baja: 'Queda registrada para el histórico.',
  };

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prioridad',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final p in Prioridad.values) ...[
          RadioListTile<Prioridad>(
            value: p,
            // ignore: deprecated_member_use
            groupValue: valor,
            // ignore: deprecated_member_use
            onChanged: habilitado ? (v) => alCambiar(v!) : null,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Row(
              children: [
                Text(p.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                if (p.requiereAtencionInmediata)
                  Icon(Icons.bolt, size: 15, color: esquema.error),
              ],
            ),
            subtitle: Text(
              _descripciones[p]!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TemaCampo.gris),
            ),
          ),
        ],
      ],
    );
  }
}

/// Barra inferior fija con el botón de enviar.
class _Pie extends StatelessWidget {
  const _Pie({
    required this.enviando,
    required this.habilitado,
    required this.onEnviar,
  });

  final bool enviando;
  final bool habilitado;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: habilitado ? onEnviar : null,
          icon: enviando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(enviando ? 'Enviando...' : 'Reportar novedad'),
        ),
      ),
    );
  }
}

/// Aviso de error general, debajo del formulario.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: esquema.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: esquema.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: esquema.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}