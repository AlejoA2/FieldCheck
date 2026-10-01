/// Implementaciones reales de [UbicacionService] y [CamaraService].
///
/// ## Decisiones de campo
///
/// ### Ubicación
///
/// * **Una sola lectura, con `timeLimit`.** El GPS en interiores tarda en
///   estabilizarse y una lectura sin límite puede dejar al supervisor esperando
///   indefinidamente. [GeolocatorUbicacionService.timeoutLectura] corta la
///   espera y devuelve un motivo accionable.
/// * **Ubicación conocida primero.** Se consulta la última posición conocida del
///   sistema como atajo. En campo es la diferencia entre un check-in instantáneo
///   y uno de veinte segundos, y el geofence igual valida contra el radio.
/// * **Sin caché propia.** La última posición la mantiene el sistema operativo,
///   que es quien sabe cuándo quedó obsoleta. Reimplementarlo aquí produciría
///   posiciones viejas creyendo que son nuevas.
///
/// ### Cámara
///
/// Solo se ofrece tomar una foto nueva. No hay selección desde la galería: una
/// imagen de la galería puede ser de otro día o de otro lugar, y el valor del
/// reto es probar que el supervisor estuvo en el sitio. La restricción está
/// también en el enum [CapturaFoto], no solo en esta implementación.
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/models/geo_point.dart';
import '../../domain/services/ubicacion_service.dart';

class GeolocatorUbicacionService implements UbicacionService {
  const GeolocatorUbicacionService();

  /// Tiempo máximo de espera para fijar la posición.
  static const Duration timeoutLectura = Duration(seconds: 20);

  /// Antigüedad máxima aceptada para reutilizar la última posición conocida.
  ///
  /// Por debajo de un minuto la posición sigue siendo válida para validar un
  /// geofence de 100 m; por encima, se pide una lectura nueva.
  static const Duration antiguedadMaxima = Duration(minutes: 1);

  @override
  Future<LecturaPosicion> leerPosicion() async {
    final problemaDelSistema = await _servicioEncendido();
    if (problemaDelSistema != null) return problemaDelSistema;

    final problemaDePermiso = await _permisoConcedido();
    if (problemaDePermiso != null) return problemaDePermiso;

    try {
      final conocida = await Geolocator.getLastKnownPosition();
      if (conocida != null) {
        final antiguedad = DateTime.now()
            .toUtc()
            .difference(conocida.timestamp.toUtc());
        if (!antiguedad.isNegative && antiguedad <= antiguedadMaxima) {
          return PosicionObtenida(_aGeoPoint(conocida));
        }
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeoutLectura,
        ),
      );
      return PosicionObtenida(_aGeoPoint(posicion));
    } on TimeoutException {
      Log.aviso('La lectura de GPS agotó el tiempo de espera');
      return const PosicionNoObtenida(
        'No se pudo determinar tu ubicación a tiempo.',
        sugerencia: 'Sal a un lugar más abierto o espera unos segundos e '
            'intenta de nuevo.',
      );
    } on LocationServiceDisabledException {
      return const PosicionNoObtenida(
        'La ubicación está desactivada en el dispositivo.',
        sugerencia: 'Actívala en los ajustes del teléfono para registrar el '
            'check-in.',
      );
    } on PermissionDeniedException {
      return const PosicionNoObtenida(
        'No diste permiso para usar la ubicación.',
        sugerencia: 'Sin ese permiso no se puede validar que estés en el sitio.',
      );
    } catch (e, s) {
      Log.error('Fallo inesperado al leer la ubicación', e, s);
      return const PosicionNoObtenida(
        'No se pudo leer tu ubicación.',
        sugerencia: 'Intenta de nuevo en unos segundos.',
      );
    }
  }

  /// Comprueba que el servicio de ubicación del sistema esté encendido.
  ///
  /// Devuelve el problema encontrado o `null` si todo está bien, en vez de un
  /// booleano: cada causa necesita su propio mensaje y su propia sugerencia.
  Future<PosicionNoObtenida?> _servicioEncendido() async {
    final habilitado = await Geolocator.isLocationServiceEnabled();
    if (habilitado) return null;
    return const PosicionNoObtenida(
      'La ubicación está desactivada en el dispositivo.',
      sugerencia: 'Actívala en los ajustes del teléfono para registrar el '
          'check-in.',
    );
  }

  /// Pide el permiso si hace falta. `null` si ya se puede leer la posición.
  Future<PosicionNoObtenida?> _permisoConcedido() async {
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      return const PosicionNoObtenida(
        'No diste permiso para usar la ubicación.',
        sugerencia: 'Sin ese permiso no se puede validar que estés en el sitio.',
      );
    }
    if (permiso == LocationPermission.deniedForever) {
      return const PosicionNoObtenida(
        'El permiso de ubicación está bloqueado.',
        sugerencia: 'Actívalo en los ajustes del sistema, en Aplicaciones > '
            'FieldCheck > Permisos.',
      );
    }
    return null;
  }

  static GeoPoint _aGeoPoint(Position posicion) =>
      GeoPoint(posicion.latitude, posicion.longitude);
}

class ImagePickerCamaraService implements CamaraService {
  ImagePickerCamaraService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> capturar(CapturaFoto modo) async {
    // El único modo permitido es la cámara. La comprobación está también en el
    // enum del dominio; aquí protege contra una llamada interna equivocada.
    if (modo != CapturaFoto.fotografiar) {
      throw const DevicePermissionException(
        'Solo se permite tomar fotos nuevas con la cámara.',
      );
    }

    try {
      final imagen = await _picker.pickImage(
        source: ImageSource.camera,
        // Sin `maxWidth` ni `imageQuality`: recomprimir en el dispositivo
        // degrada la foto que sirve de evidencia de una incidencia. El peso lo
        // resuelve la subida a Storage, que va por red.
        preferredCameraDevice: CameraDevice.rear,
      );
      return imagen?.path;
    } on DevicePermissionException {
      rethrow;
    } catch (e, s) {
      Log.error('Fallo al abrir la cámara', e, s);
      throw const DevicePermissionException(
        'No se pudo abrir la cámara. Revisa el permiso e intenta de nuevo.',
      );
    }
  }
}
