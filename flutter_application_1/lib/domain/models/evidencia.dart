/// Evidencia (fotografía, video o documento) asociada a una visita o novedad.
///
/// Este modelo es la pieza que hace posible el modo offline: una foto tomada
/// en campo vive primero como [rutaLocal] en el dispositivo y solo cuando el
/// `SyncService` la sube a Firebase Storage obtiene su [urlRemota].
library;

import 'enums.dart';
import 'geo_point.dart';

class Evidencia {
  const Evidencia({
    required this.id,
    required this.visitaId,
    required this.tipo,
    required this.capturadaAt,
    this.actividadId,
    this.rutaLocal,
    this.urlRemota,
    this.ubicacion,
    this.syncStatus = SyncStatus.pendiente,
    this.comentario = '',
  });

  /// Id generado en el cliente. Se usa también como nombre del objeto en
  /// Storage, lo que garantiza idempotencia al reintentar la subida.
  final String id;

  final String visitaId;

  /// Actividad del checklist a la que se asocia, si aplica.
  final String? actividadId;

  final TipoEvidencia tipo;
  final DateTime capturadaAt;

  /// Ruta del archivo en el dispositivo. `null` si ya fue subida y limpiada.
  final String? rutaLocal;

  /// URL pública en Firebase Storage. `null` mientras no se haya subido.
  final String? urlRemota;

  /// Coordenadas en el momento de la captura: evidencia de que la foto se
  /// tomó en el lugar correcto, no en otro sitio.
  final GeoPoint? ubicacion;

  final SyncStatus syncStatus;
  final String comentario;

  bool get estaPendiente => syncStatus.requiereSync;
  bool get esLocal => rutaLocal != null && urlRemota == null;
  bool get estaSincronizada => urlRemota != null && !syncStatus.requiereSync;

  Evidencia copyWith({
    String? rutaLocal,
    String? urlRemota,
    SyncStatus? syncStatus,
    String? comentario,
    String? actividadId,
  }) {
    return Evidencia(
      id: id,
      visitaId: visitaId,
      actividadId: actividadId ?? this.actividadId,
      tipo: tipo,
      capturadaAt: capturadaAt,
      rutaLocal: rutaLocal ?? this.rutaLocal,
      urlRemota: urlRemota ?? this.urlRemota,
      ubicacion: ubicacion,
      syncStatus: syncStatus ?? this.syncStatus,
      comentario: comentario ?? this.comentario,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'visitaId': visitaId,
    if (actividadId != null) 'actividadId': actividadId,
    'tipo': tipo.valor,
    'capturadaAt': capturadaAt.toIso8601String(),
    if (rutaLocal != null) 'rutaLocal': rutaLocal,
    if (urlRemota != null) 'urlRemota': urlRemota,
    if (ubicacion != null) 'ubicacion': ubicacion!.toMap(),
    'syncStatus': syncStatus.valor,
    'comentario': comentario,
  };

  factory Evidencia.fromMap(Map<String, dynamic> map) => Evidencia(
    id: map['id'] as String? ?? '',
    visitaId: map['visitaId'] as String? ?? '',
    actividadId: map['actividadId'] as String?,
    tipo: TipoEvidencia.desdeValor(map['tipo'] as String?),
    capturadaAt:
        DateTime.tryParse(map['capturadaAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    rutaLocal: map['rutaLocal'] as String?,
    urlRemota: map['urlRemota'] as String?,
    ubicacion: map['ubicacion'] == null
        ? null
        : GeoPoint.fromMap(Map<String, dynamic>.from(map['ubicacion'] as Map)),
    syncStatus: SyncStatus.desdeValor(map['syncStatus'] as String?),
    comentario: map['comentario'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) => other is Evidencia && other.id == id;

  @override
  int get hashCode => id.hashCode;
}