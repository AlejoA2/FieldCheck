/// Guardado del reporte CSV en el dispositivo del coordinador.
///
/// ## Por qué un paquete externo y no `dart:io`
///
/// El coordinador usa FieldCheck en el navegador (es un panel de escritorio) y
/// el supervisor lo usa en el teléfono. `dart:io` no existe en web: escribir el
/// archivo ahí requiere una descarga del navegador, y en móvil requiere elegir
/// carpeta o usar MediaStore. `file_saver` resuelve los tres casos con una sola
/// llamada, así que el proyecto no mantiene tres implementaciones de "descargar
/// un archivo".
///
/// La **construcción** del CSV no está aquí: vive en `ReporteCsv`
/// (`lib/domain/services/`), sin `dart:io` y sin este paquete, para que se pueda
/// verificar en tests. Este archivo solo se ocupa de volcar una cadena ya
/// construida al disco.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import '../error/app_exception.dart';

/// Escribe un reporte ya construido en el sistema de archivos del dispositivo.
abstract final class ExportadorCsv {
  /// Guarda [contenido] y devuelve la ruta (o el nombre, en web) donde quedó.
  ///
  /// [nombreArchivo] puede venir con o sin la extensión `.csv`: se normaliza
  /// aquí para no duplicarla en el nombre final, que es el defecto típico al
  /// concatenar el sufijo en dos sitios.
  ///
  /// Lanza [LocalStorageException] con un mensaje legible si el dispositivo
  /// rechaza la escritura (permisos, disco lleno, diálogo cancelado).
  static Future<String> guardar({
    required String nombreArchivo,
    required String contenido,
  }) async {
    final sinExtension = nombreArchivo.toLowerCase().endsWith('.csv')
        ? nombreArchivo.substring(0, nombreArchivo.length - 4)
        : nombreArchivo;

    try {
      final destino = await FileSaver.instance.saveAs(
        name: sinExtension,
        bytes: Uint8List.fromList(utf8.encode(contenido)),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      return destino ?? sinExtension;
    } catch (e, s) {
      throw LocalStorageException(
        'No se pudo guardar el reporte en este dispositivo.',
        cause: e,
        stackTrace: s,
      );
    }
  }
}