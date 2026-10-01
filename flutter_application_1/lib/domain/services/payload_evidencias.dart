/// Sustitución de rutas locales por URLs remotas dentro de un payload.
///
/// ## Por qué existe
///
/// El `SyncService` recibe el payload ya serializado de la entidad y una lista de
/// archivos locales que deben subir a Storage. La versión anterior del servicio
/// escribía el documento en Firestore tal cual, con `rutaLocal` intacto y sin
/// haber subido el archivo: el coordinador recibía una visita que parecía
/// tener evidencia, pero el archivo no existía y la ruta era inútil para
/// cualquiera que no fuera ese dispositivo.
///
/// ## Qué garantiza
///
///  1. **Cada `rutaLocal` se convierte en un `urlRemota`** ya subido, en
///     cualquier nivel de anidamiento.
///  2. **La clave `rutaLocal` desaparece.** Una ruta del dispositivo es
///     información inútil fuera de él (y filtra el nombre del usuario del
///     teléfono), así que no debe viajar a Firestore.
///  3. **No se inventa nada.** Si la foto no llegó a subirse, la clave se omite
///     en vez de mandar una ruta que el coordinador no puede abrir.
///
/// Al vivir en el dominio (y no en el datasource), la lógica es verificable con
/// dobles en memoria, sin necesidad de Firebase.
library;

import '../models/evidencia.dart';

/// Resuelve archivos locales dentro de payloads de la cola de sincronización.
class PayloadEvidencias {
  const PayloadEvidencias();

  /// Convierte cada `rutaLocal` en un `urlRemota` ya subido.
  ///
  /// La clave se **renombra**, no se borra: si se eliminara junto con su valor,
  /// la URL subiría con ella y el documento remoto quedaría sin referencia a la
  /// foto. `rutaLocal` no sobrevive porque es una ruta del dispositivo, inútil
  /// fuera de él.
  ///
  /// [rutasRemotas] mapea ruta local -> URL ya subida.
  Map<String, dynamic> resolver(
    Map<String, dynamic> payload,
    Map<String, String> rutasRemotas,
  ) {
    return Map<String, dynamic>.from(_renombrarRutas(payload, rutasRemotas) as Map);
  }

  /// Recorre el documento renombrando `rutaLocal` a `urlRemota`.
  Object? _renombrarRutas(Object? valor, Map<String, String> rutasRemotas) {
    if (valor is Map) {
      final resultado = <String, dynamic>{};
      for (final entrada in valor.entries) {
        final clave = entrada.key.toString();
        final contenido = entrada.value;

        if (clave == 'rutaLocal' && contenido is String) {
          final url = rutasRemotas[contenido];
          // Sin URL resuelta no se inventa nada: la clave se omite para no
          // mandar al servidor una ruta que el coordinador no puede abrir.
          if (url != null) resultado['urlRemota'] = url;
          continue;
        }

        resultado[clave] = _renombrarRutas(contenido, rutasRemotas);
      }
      return resultado;
    }
    if (valor is List) {
      return valor.map((e) => _renombrarRutas(e, rutasRemotas)).toList();
    }
    return valor;
  }

  /// Construye el nombre destino de un archivo en Storage.
  ///
  /// Debe ser estable entre reintentos: es lo que hace que subir dos veces el
  /// mismo archivo sobrescriba el objeto en vez de crear otro.
  ///
  /// Se compone de colección, entidad y nombre base del archivo:
  /// `evidencias/<evidenciaId>/IMG_20260312_101530.jpg`.
  static String nombreDestino({
    required String coleccion,
    required String entidadId,
    required String rutaLocal,
  }) {
    final separador = rutaLocal.lastIndexOf(RegExp(r'[/\\]'));
    final base = separador >= 0 ? rutaLocal.substring(separador + 1) : rutaLocal;
    final nombre = base.isEmpty ? 'archivo' : base;
    return '$coleccion/$entidadId/$nombre';
  }

  /// `true` si [payload] ya no contiene ninguna clave `rutaLocal`.
  ///
  /// Lo usan los tests y el propio servicio para afirmar que el documento que
  /// viaja al servidor está limpio, en lugar de asumirlo.
  static bool estaResolvedo(Map<String, dynamic> payload) =>
      !_contieneRutaLocal(payload);

  static bool _contieneRutaLocal(Object? valor) {
    if (valor is Map) {
      for (final entrada in valor.entries) {
        if (entrada.key.toString() == 'rutaLocal') return true;
        if (_contieneRutaLocal(entrada.value)) return true;
      }
      return false;
    }
    if (valor is List) return valor.any(_contieneRutaLocal);
    return false;
  }
}

/// Marca la referencia a la evidencia solo con su URL, para incrustarla en otro
/// documento.
///
/// El coordinador muestra las evidencias dentro de la visita; guarda la URL, no
/// el modelo entero, porque el modelo incluye `rutaLocal`.
Map<String, dynamic> referenciaEvidencia(Evidencia evidencia) => <String, dynamic>{
  'id': evidencia.id,
  'actividadId': evidencia.actividadId,
  'tipo': evidencia.tipo.valor,
  'url': evidencia.urlRemota,
  'capturadaAt': evidencia.capturadaAt.toIso8601String(),
  if (evidencia.ubicacion != null) 'ubicacion': evidencia.ubicacion!.toMap(),
  'comentario': evidencia.comentario,
};
