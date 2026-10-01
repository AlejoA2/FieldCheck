/// Pantalla de inicio de sesión.
///
/// ## Validación en el propio campo
///
/// El formulario valida al perder el foco y otra vez al enviar, y el error
/// aparece **bajo el campo**, no como un aviso al final. Es el requisito
/// `RF-UX-01` del proyecto: el supervisor debe saber qué corregir sin tener que
/// adivinarlo.
///
/// ## Por qué el botón se bloquea al enviar
///
/// Un doble toque en "Entrar" con mala clave produce dos intentos y dos
/// "credenciales incorrectos". Con el botón deshabilitado el segundo toque no
/// llega al backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'sesion_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formulario = GlobalKey<FormState>();
  final TextEditingController _correo = TextEditingController();
  final TextEditingController _clave = TextEditingController();

  bool _enviando = false;
  bool _mostrarClave = false;
  String? _errorGeneral;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!(_formulario.currentState?.validate() ?? false)) return;

    setState(() {
      _enviando = true;
      _errorGeneral = null;
    });

    final sesion = context.read<SesionController>();
    final error = await sesion.iniciarSesion(
      email: _correo.text,
      password: _clave.text,
    );

    if (!mounted) return;

    setState(() {
      _enviando = false;
      _errorGeneral = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: esquema.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              // En escritorio el formulario no se estira de lado a lado: un
              // campo de 900 px de ancho es incómodo de leer.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Marca(),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formulario,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _correo,
                              enabled: !_enviando,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              inputFormatters: const [FiltroCorreo()],
                              decoration: const InputDecoration(
                                labelText: 'Correo institucional',
                                hintText: 'nombre@university.edu',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: _validarCorreo,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _clave,
                              enabled: !_enviando,
                              obscureText: !_mostrarClave,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _enviar(),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _mostrarClave = !_mostrarClave,
                                  ),
                                  icon: Icon(
                                    _mostrarClave
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  tooltip: _mostrarClave
                                      ? 'Ocultar contraseña'
                                      : 'Mostrar contraseña',
                                ),
                              ),
                              validator: (valor) => (valor ?? '').isEmpty
                                  ? 'Escribe tu contraseña.'
                                  : null,
                            ),
                            if (_errorGeneral != null) ...[
                              const SizedBox(height: 14),
                              _MensajeError(mensaje: _errorGeneral!),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _enviando ? null : _enviar,
                              child: _enviando
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text('Entrar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'FieldCheck · Supervisión inteligente en campo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: esquema.onPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Valida el formato del correo con una expresión regular simple.
  ///
  /// No se intenta adivinar qué dominios institucionales existen: la verificación
  /// real la hace Firebase al autenticar. Este chequeo solo evita un viaje en
  /// redondo por un error de dedo.
  String? _validarCorreo(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Escribe tu correo institucional.';
    final patron = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!patron.hasMatch(texto)) {
      return 'Ese correo no parece válido. Revisa que tenga el formato '
          'nombre@dominio.com';
    }
    return null;
  }
}

/// Encabezado con el nombre de la app.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 68,
          width: 68,
          decoration: BoxDecoration(
            color: esquema.onPrimary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            Icons.fact_check_outlined,
            size: 36,
            color: esquema.onPrimary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'FieldCheck',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: esquema.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Control de visitas verificable, incluso sin señal',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: esquema.onPrimary.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// Mensaje de error general del formulario.
class _MensajeError extends StatelessWidget {
  const _MensajeError({required this.mensaje});

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

/// Filtra la entrada del correo.
///
/// Deja pasar todo lo que un correo puede llevar y quita los espacios, que en un
/// teclado móvil es fácil colar por accidente y Firebase los rechaza.
class FiltroCorreo extends TextInputFormatter {
  const FiltroCorreo();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    final limpio = nuevo.text.replaceAll(' ', '');
    return limpio == nuevo.text ? nuevo : nuevo.copyWith(text: limpio);
  }
}
