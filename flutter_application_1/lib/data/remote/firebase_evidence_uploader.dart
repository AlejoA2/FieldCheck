/// Implementación de [EvidenceUploader] sobre Firebase Storage.
///
/// ## Idempotencia
///
/// El objeto se nombra con `evidencias/<id>/<archivo>`, donde `<id>` es el id
/// generado en el cliente para la evidencia. Como ese id nunca cambia, subir
/// dos veces el mismo archivo sobrescribe el objeto en lugar de crear un
/// duplicado, y el costo de un reintento es el ancho de banda, no el
/// almacenamiento acumulado.
///
/// ## Reintentos
///
/// `putFile` usa por defecto la política `retry` del SDK. Se sube además el
/// contenido como archivo (`File`), no como blob, porque el original de
/// `image_picker` ya está en el disco del dispositivo y así no se duplica la
/// imagen en memoria.
library;

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../../core/error/app_exception.dart';
import '../../domain/repositories/contracts.dart';

class FirebaseEvidenceUploader implements EvidenceUploader {
  FirebaseEvidenceUploader({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<String> subir({
    required String rutaLocal,
    required String nombreDestino,
  }) async {
    try {
      final archivo = File(rutaLocal);
      if (!await archivo.exists()) {
        throw const RemoteException('No se encontró la foto para adjuntar.');
      }

      final referencia = _storage.ref().child(nombreDestino);

      // `putFile` devuelve un `UploadTask`, que es un `Future<TaskSnapshot>`.
      // Sin esperarlo, el método devolvería la URL antes de que la subida
      // terminara y el `SyncService` borraría el archivo local mientras todavía
      // se está subiendo.
      await referencia.putFile(
        archivo,
        SettableMetadata(
          contentType: _contentTypeDe(rutaLocal),
          customMetadata: const <String, String>{'origen': 'fieldcheck-app'},
        ),
      );

      return await referencia.getDownloadURL();
    } on AppException {
      rethrow;
    } catch (e, s) {
      throw RemoteException(
        'No se pudo subir la evidencia. Se reintentará automáticamente.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<void> eliminar(String urlRemota) async {
    try {
      final referencia = _storage.refFromURL(urlRemota);
      await referencia.delete();
    } catch (_) {
      // Best-effort por contrato: borrar evidencia remota es una limpieza, y un
      // fallo acá no debe propagarse a la cola de sincronización.
    }
  }

  @override
  Future<void> limpiarLocales(List<String> rutasLocales) async {
    for (final ruta in rutasLocales) {
      try {
        final archivo = File(ruta);
        if (await archivo.exists()) await archivo.delete();
      } catch (_) {
        // Igual que arriba: si el archivo ya no está, la limpieza dio igual.
      }
    }
  }

  /// `image_picker` produce JPEG por defecto, así que ese es el caso normal.
  static String _contentTypeDe(String rutaLocal) {
    final ruta = rutaLocal.toLowerCase();
    if (ruta.endsWith('.png')) return 'image/png';
    if (ruta.endsWith('.webp')) return 'image/webp';
    if (ruta.endsWith('.heic')) return 'image/heic';
    if (ruta.endsWith('.mp4')) return 'video/mp4';
    if (ruta.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }
}
