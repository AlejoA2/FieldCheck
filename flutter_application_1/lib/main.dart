/// Punto de entrada de FieldCheck.
///
/// ## Por qué el arranque se hace antes de `runApp`
///
/// `Dependencias.construir()` abre Hive e inicializa Firebase, y ambas cosas son
/// asíncronas y pueden fallar. Si se hiciera dentro del árbol de widgets, el
/// primer fotograma sería una pantalla en blanco o, peor, una pantalla de error
/// genérica sin contexto. Haciéndolo aquí se distingue un problema con
/// solución (falta el `google-services.json`) de uno sin ella.
///
/// ## Sin credenciales la app no se rompe, explica
///
/// [FirebaseNoConfiguradoException] es el caso esperado hasta que cada
/// desarrollador descarga su `google-services.json`. En lugar de dejar una
/// pantalla blanca o un error del SDK —cuyo texto, `[core/no-app] No Firebase
/// App '[DEFAULT]' has been created`, no le dice nada a quien no conoce
/// Firebase— se muestra [PantallaConfiguracionFirebase] con los pasos.
///
/// ## El enrutado por rol ocurre una sola vez
///
/// [SesionController] resuelve el rol y decide a qué pantalla llevar. No se
/// reparte esa decisión entre las pantallas: si lo hiciera cada una, habría un
/// instante en que una ya está en el panel del coordinador y otra todavía
/// cree que es supervisor.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/di/dependencias.dart';
import 'domain/models/app_user.dart';
import 'core/theme/tema.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/sesion_controller.dart';
import 'features/coordinator/coordinator_panel_screen.dart';
import 'features/supervisor/supervisor_home_screen.dart';
import 'features/sync/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin esto, `DateFormat(..., 'es')` lanza `LocaleDataException`: el paquete
  // `intl` no trae los meses en español hasta que se cargan sus datos. Toda la
  // app formatea fechas en español, así que es un paso obligatorio, no opcional.
  await initializeDateFormatting('es');

  try {
    final dependencias = await Dependencias.construir();
    final pendientes = await dependencias.cola.contarPendientes();

    runApp(FieldCheckApp(dependencias: dependencias, pendientes: pendientes));
  } on FirebaseNoConfiguradoException catch (e) {
    runApp(PantallaConfiguracionFirebase(detalle: e.detalle));
  } on AppBootstrapException catch (e, s) {
    // El error técnico queda en consola, no en pantalla: el usuario solo puede
    // actuar sobre "no se pudo iniciar la app".
    debugPrint('FieldCheck no pudo arrancar: $e\n$s');
    runApp(const PantallaErrorArranque());
  }
}

/// Raíz de la aplicación.
///
/// El [BootstrapScope] envuelve todo para que cualquier widget llegue al grafo de
/// dependencias por un único punto documentado. Los controladores de sesión y
/// de sincronización se crean aquí (no en el `State` de cada pantalla) porque su
/// vida debe ser la de la app: un `SyncController` por pantalla dejaría de
/// contar pendientes al salir de ella.
class FieldCheckApp extends StatefulWidget {
  const FieldCheckApp({
    required this.dependencias,
    required this.pendientes,
    super.key,
  });

  final Dependencias dependencias;

  /// Pendientes leídos del almacén antes de construir la app.
  ///
  /// Se pasan por parámetro para que el primer fotograma del banner ya tenga el
  /// número correcto: leerlos de forma asíncrona mostraría "0 pendientes" y lo
  /// corregiría un instante después.
  final int pendientes;

  @override
  State<FieldCheckApp> createState() => _FieldCheckAppState();
}

class _FieldCheckAppState extends State<FieldCheckApp> {
  late final SesionController _sesion;
  late final SyncController _sync;

  @override
  void initState() {
    super.initState();
    _sesion = SesionController(
      auth: widget.dependencias.auth,
      onSesionResuelta: _alResolverSesion,
    );
    _sync = SyncController(
      sync: widget.dependencias.sync,
      pendientesIniciales: widget.pendientes,
    );
  }

  @override
  void dispose() {
    _sync.dispose();
    _sesion.dispose();
    super.dispose();
  }

  /// Carga las visitas asignadas cuando ya se sabe quién es el supervisor.
  ///
  /// Se dispara desde la resolución de la sesión y no desde el `build` del panel:
  /// al arrancar puede que el usuario no haya iniciado sesión, y en ese caso no
  /// hay a quién preguntarle.
  void _alResolverSesion(AppUser? usuario) {
    if (usuario == null || !usuario.esSupervisor) return;
    // El error se ignora a propósito: `refrescarVisitasAsignadas` es
    // best-effort y el supervisor ve igualmente su caché local, que es lo que
    // importa cuando no hay cobertura.
    unawaited(
      widget.dependencias.visitas.refrescarVisitasAsignadas(usuario.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BootstrapScope(
      dependencias: widget.dependencias,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _sesion),
          ChangeNotifierProvider.value(value: _sync),
        ],
        child: MaterialApp(
          title: 'FieldCheck',
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          darkTheme: temaOscuro(),
          themeMode: ThemeMode.system,
          // Sin estos delegados, los selectores de fecha del panel hablarían en
          // inglés mientras el resto de la app está en español.
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es')],
          locale: const Locale('es'),
          home: const _RutaPorRol(),
        ),
      ),
    );
  }
}

/// Decide la pantalla inicial según el estado de la sesión.
///
/// Cubre los tres estados que distingue [SesionController]: cargando, sin
/// sesión y con sesión.
class _RutaPorRol extends StatelessWidget {
  const _RutaPorRol();

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionController>();

    if (sesion.cargando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando FieldCheck...'),
            ],
          ),
        ),
      );
    }

    final usuario = sesion.usuario;
    if (usuario == null) return const LoginScreen();

    return usuario.esCoordinador
        ? CoordinatorPanelScreen(usuario: usuario)
        : SupervisorHomeScreen(usuario: usuario);
  }
}

/// Pantalla mostrada cuando Firebase no tiene credenciales en este build.
///
/// No es una pantalla de error: es una lista de pasos. La diferencia importa
/// porque el problema tiene solución en cinco minutos y quien lo lee es un
/// desarrollador, no un usuario final.
class PantallaConfiguracionFirebase extends StatelessWidget {
  const PantallaConfiguracionFirebase({required this.detalle, super.key});

  /// Mensaje original del SDK, mostrado en letra pequeña al pie.
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldCheck',
      debugShowCheckedModeBanner: false,
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      home: Scaffold(
        appBar: AppBar(title: const Text('FieldCheck')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: TemaCampo.ambar,
            ),
            const SizedBox(height: 16),
            Text(
              'Falta configurar Firebase',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Esta compilación no tiene credenciales de Firebase, así que no '
              'puede conectarse al servidor. La app sigue compilando y todas '
              'las pruebas se ejecutan sin ellas.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: TemaCampo.gris),
            ),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Paso(
                      numero: 1,
                      texto: 'Crea un proyecto en console.firebase.google.com.',
                    ),
                    _Paso(
                      numero: 2,
                      texto: 'Activa Authentication con correo y contraseña.',
                    ),
                    _Paso(
                      numero: 3,
                      texto: 'Crea una base de datos de Firestore en modo '
                          'producción.',
                    ),
                    _Paso(
                      numero: 4,
                      texto: 'Activa Storage para las evidencias.',
                    ),
                    _Paso(
                      numero: 5,
                      texto:
                          'Descarga google-services.json y colócalo en '
                          'android/app/.',
                    ),
                    _Paso(
                      numero: 6,
                      texto: 'Ejecuta `flutter run` de nuevo.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Detalle técnico: $detalle',
              style: const TextStyle(fontSize: 11, color: TemaCampo.gris),
            ),
          ],
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 24,
            width: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

/// Pantalla de fallo de arranque, sin detalle técnico.
class PantallaErrorArranque extends StatelessWidget {
  const PantallaErrorArranque({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldCheck',
      debugShowCheckedModeBanner: false,
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 56,
                  color: TemaCampo.rojo,
                ),
                const SizedBox(height: 16),
                Text(
                  'No se pudo iniciar FieldCheck',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'El almacenamiento local no pudo abrirse. Reinicia la app; si '
                  'el problema persiste, revisa que el dispositivo tenga espacio '
                  'libre.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: TemaCampo.gris),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
