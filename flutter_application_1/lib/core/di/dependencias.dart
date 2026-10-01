/// Inyección de dependencias: el único lugar donde se construye el grafo de
/// objetos de la aplicación.
///
/// ## Por qué un contenedor propio y no `get_it` u otro paquete
///
/// El proyecto tiene una docena de dependencias que construir y ninguna con
/// colisión de tipos. Un contenedor escrito a mano son unas sesenta líneas, sin
/// dependencia nueva, y además sirve de documentación: se lee de arriba abajo y
/// se ve exactamente qué se inyecta en cada capa. `provider` (que ya está en el
/// pubspec) se encarga después de *distribuir* lo que este archivo construye.
///
/// ## Orden de construcción
///
/// El orden importa y no es arbitrario:
///
///  1. [FirebaseAuthRepository] primero, porque `VisitaRepositoryImpl` lo necesita
///     para resolver el supervisor de la sesión en curso.
///  2. La caché local y la cola, que dependen solo de Hive ya abierto.
///  3. [SyncService], que consume cola, gateway y subidor de evidencias.
///  4. Los repositorios, que son los que usan las piezas anteriores.
///
/// ## El callback `supervisorActual`
///
/// `VisitaRepositoryImpl` recibe `String Function()` y no `String`: se construye
/// una sola vez al arrancar la app, cuando todavía no hay sesión. El callback
/// lo consulta en cada uso, y por eso cambiar de usuario (cerrar sesión y entrar
/// otro) no deja datos cruzados.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';

import '../../data/local/hive_almacen_local.dart';
import '../../data/local/hive_cajas.dart';
import '../../data/local/hive_sync_queue_store.dart';
import '../../data/remote/firebase_auth_repository.dart';
import '../../data/remote/firebase_evidence_uploader.dart';
import '../../data/remote/firestore_sync_gateway.dart';
import '../../data/remote/firestore_visitas_remotas.dart';
import '../../data/repositories/firestore_consulta_repository.dart';
import '../../data/repositories/visita_repository_impl.dart';
import '../../data/services/conectividad_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/ubicacion_service_impl.dart';
import '../../domain/repositories/contracts.dart';
import '../../domain/services/geofence_service.dart';
import '../../domain/services/reporte_csv.dart';
import '../../domain/services/ubicacion_service.dart';

/// Contenedor de dependencias de la aplicación.
///
/// Se construye una vez en `main` y se entrega al árbol de widgets con
/// `provider`. Todos los campos son `final`: el grafo no cambia durante la vida
/// de la app.
class Dependencias {
  Dependencias._({
    required this.auth,
    required this.almacen,
    required this.cola,
    required this.sync,
    required this.visitas,
    required this.consulta,
    required this.ubicacion,
    required this.camara,
    required this.reporteCsv,
  });

  final AuthRepository auth;
  final AlmacenLocal almacen;
  final SyncQueueStore cola;
  final SyncService sync;
  final VisitaRepository visitas;
  final ConsultaRepository consulta;
  final UbicacionService ubicacion;
  final CamaraService camara;
  final ReporteCsv reporteCsv;

  /// Construye el grafo completo.
  ///
  /// Lanza [FirebaseNoConfiguradoException] si el proyecto de Firebase no está
  /// configurado, y [AppBootstrapException] ante cualquier otro fallo. La
  /// distinción importa: el primero tiene una solución que el usuario puede
  /// aplicar (descargar `google-services.json`), el segundo no.
  static Future<Dependencias> construir() async {
    await _exigirFirebase();

    try {
      await inicializarAlmacenamientoLocal();

      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuthRepository();

      final almacen = HiveAlmacenLocal();
      final cola = HiveSyncQueueStore();

      final sync = SyncService(
        cola: cola,
        gateway: FirestoreSyncGateway(firestore: db),
        evidencia: FirebaseEvidenceUploader(
          storage: FirebaseStorage.instance,
        ),
        conectividad: ConnectivityPlusService(),
      );

      final repositorioVisitas = VisitaRepositoryImpl(
        almacen: almacen,
        cola: cola,
        sync: sync,
        geofence: const GeofenceService(),
        remotas: FirestoreVisitasRemotas(firestore: db),
        supervisorActual: () => auth.usuarioActual?.id ?? '',
      );

      return Dependencias._(
        auth: auth,
        almacen: almacen,
        cola: cola,
        sync: sync,
        visitas: repositorioVisitas,
        consulta: FirestoreConsultaRepository(firestore: db),
        ubicacion: const GeolocatorUbicacionService(),
        camara: ImagePickerCamaraService(),
        reporteCsv: const ReporteCsv(),
      );
    } on Object catch (e, s) {
      throw AppBootstrapException(
        'No se pudo iniciar FieldCheck en este dispositivo.',
        causa: e,
        traza: s,
      );
    }
  }

  /// Libera los recursos: detiene la sincronización y cierra Hive.
  ///
  /// Los datos de campo **no** se borran: son la evidencia del supervisor y
  /// deben sobrevivir al cierre para poder sincronizarse más tarde.
  Future<void> dispose() async {
    await sync.dispose();
    await cola.cerrar();
    await almacen.cerrar();
    await cerrarCajas();
  }

  /// Verifica que Firebase esté inicializado.
  ///
  /// Se consulta `Firebase.apps` en vez de llamar `initializeApp` a ciegas
  /// porque, sin credenciales, `initializeApp` lanza una excepción cuyo mensaje
  /// (`[core/no-app] No Firebase App '[DEFAULT]' has been created`) no le dice
  /// nada a quien todavía no tiene el `google-services.json`.
  static Future<void> _exigirFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }
}

/// Firebase no tiene credenciales cargadas en este build.
///
/// Es un caso esperado, no un bug: ocurre hasta que cada desarrollador descarga
/// su `google-services.json` de la consola de Firebase. La app lo muestra como
/// pantalla de configuración con los pasos exactos, en vez de una pantalla en
/// blanco.
class FirebaseNoConfiguradoException implements Exception {
  const FirebaseNoConfiguradoException(this.detalle);

  /// Texto original de la excepción del SDK, solo para el log.
  final String detalle;

  @override
  String toString() => 'FirebaseNoConfiguradoException: $detalle';
}

/// Fallo controlado durante el arranque, distinto de la falta de credenciales.
class AppBootstrapException implements Exception {
  const AppBootstrapException(this.message, {this.causa, this.traza});

  final String message;
  final Object? causa;
  final StackTrace? traza;

  @override
  String toString() => 'AppBootstrapException: $message ($causa)';
}

/// Publica las dependencias en el árbol de widgets.
///
/// `provider` ya hace esto con `Provider.value`, pero el acceso por
/// `Dependencias.de(context)` se lee mejor en los widgets que el
/// `context.read<Dependencias>()`, y deja un solo punto de acceso documentado.
class BootstrapScope extends InheritedWidget {
  const BootstrapScope({
    required this.dependencias,
    required super.child,
    super.key,
  });

  final Dependencias dependencias;

  /// Acceso a las dependencias desde cualquier widget.
  ///
  /// Lanza si se usa fuera del árbol: eso es un error de cableado, no algo que
  /// deba recuperarse en ejecución.
  static Dependencias of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BootstrapScope>();
    assert(scope != null, 'BootstrapScope no está en el árbol de widgets.');
    return scope!.dependencias;
  }

  @override
  bool updateShouldNotify(BootstrapScope oldWidget) =>
      oldWidget.dependencias != dependencias;
}
