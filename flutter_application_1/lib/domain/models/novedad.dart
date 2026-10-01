/// Novedad: una situación detectada durante la visita que requiere atención del
/// coordinador.
///
/// Sigue el flujo del reto: Visita -> Identificación -> Registro -> Evidencia
/// -> Notificación -> Revisión -> Cierre.
library;

import 'enums.dart';

class Novedad {
  const Novedad({
    required this.id,
    required this.visitaId,
    required this.centroCostoId,
    required this.titulo,
    required this.descripcion,
    required this.prioridad,
    required this.reportadaPor,
    required this.reportadaAt,
    this.evidenciaIds = const [],
    this.estado = EstadoNovedad.abierta,
    this.resolucion,
    this.resueltaAt,
    this.resueltaPor,
    this.accionesTomadas = const [],
    this.syncStatus = SyncStatus.pendiente,
    this.coordinadorNotificado = false,
    this.coordinadorNotificadoAt,
  });

  /// Id generado en el cliente (idempotencia en Firestore).
  final String id;

  final String visitaId;
  final String centroCostoId;

  final String titulo;
  final String descripcion;

  final Prioridad prioridad;

  /// Id del supervisor que la reportó.
  final String reportadaPor;
  final DateTime reportadaAt;

  /// Ids de las evidencias adjuntas (ver [Evidencia]).
  final List<String> evidenciaIds;

  final EstadoNovedad estado;

  /// Comentario de cierre del coordinador.
  final String? resolucion;
  final DateTime? resueltaAt;

  /// Id del coordinador que la cerró.
  final String? resueltaPor;

  /// Acciones comprometidas al reportar la novedad.
  final List<String> accionesTomadas;

  final SyncStatus syncStatus;

  /// `true` cuando el sistema ya notificó al coordinador. Permite no duplicar
  /// notificaciones si la sincronización se reintenta.
  final bool coordinadorNotificado;
  final DateTime? coordinadorNotificadoAt;

  bool get estaAbierta => !estado.estaCerrada;
  bool get requiereSync => syncStatus.requiereSync;

  Novedad copyWith({
    EstadoNovedad? estado,
    String? resolucion,
    DateTime? resueltaAt,
    String? resueltaPor,
    List<String>? accionesTomadas,
    List<String>? evidenciaIds,
    SyncStatus? syncStatus,
    bool? coordinadorNotificado,
    DateTime? coordinadorNotificadoAt,
    String? titulo,
    String? descripcion,
    Prioridad? prioridad,
  }) {
    return Novedad(
      id: id,
      visitaId: visitaId,
      centroCostoId: centroCostoId,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      prioridad: prioridad ?? this.prioridad,
      reportadaPor: reportadaPor,
      reportadaAt: reportadaAt,
      evidenciaIds: evidenciaIds ?? this.evidenciaIds,
      estado: estado ?? this.estado,
      resolucion: resolucion ?? this.resolucion,
      resueltaAt: resueltaAt ?? this.resueltaAt,
      resueltaPor: resueltaPor ?? this.resueltaPor,
      accionesTomadas: accionesTomadas ?? this.accionesTomadas,
      syncStatus: syncStatus ?? this.syncStatus,
      coordinadorNotificado: coordinadorNotificado ?? this.coordinadorNotificado,
      coordinadorNotificadoAt: coordinadorNotificadoAt ?? this.coordinadorNotificadoAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'visitaId': visitaId,
    'centroCostoId': centroCostoId,
    'titulo': titulo,
    'descripcion': descripcion,
    'prioridad': prioridad.valor,
    'reportadaPor': reportadaPor,
    'reportadaAt': reportadaAt.toIso8601String(),
    'evidenciaIds': evidenciaIds,
    'estado': estado.valor,
    if (resolucion != null) 'resolucion': resolucion,
    if (resueltaAt != null) 'resueltaAt': resueltaAt!.toIso8601String(),
    if (resueltaPor != null) 'resueltaPor': resueltaPor,
    'accionesTomadas': accionesTomadas,
    'syncStatus': syncStatus.valor,
    'coordinadorNotificado': coordinadorNotificado,
    if (coordinadorNotificadoAt != null)
      'coordinadorNotificadoAt': coordinadorNotificadoAt!.toIso8601String(),
  };

  factory Novedad.fromMap(Map<String, dynamic> map) => Novedad(
    id: map['id'] as String? ?? '',
    visitaId: map['visitaId'] as String? ?? '',
    centroCostoId: map['centroCostoId'] as String? ?? '',
    titulo: map['titulo'] as String? ?? '',
    descripcion: map['descripcion'] as String? ?? '',
    prioridad: Prioridad.desdeValor(map['prioridad'] as String?),
    reportadaPor: map['reportadaPor'] as String? ?? '',
    reportadaAt: DateTime.tryParse(map['reportadaAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    evidenciaIds: (map['evidenciaIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
    estado: EstadoNovedad.desdeValor(map['estado'] as String?),
    resolucion: map['resolucion'] as String?,
    resueltaAt: DateTime.tryParse(map['resueltaAt'] as String? ?? '')?.toUtc(),
    resueltaPor: map['resueltaPor'] as String?,
    accionesTomadas: (map['accionesTomadas'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
    syncStatus: SyncStatus.desdeValor(map['syncStatus'] as String?),
    coordinadorNotificado: map['coordinadorNotificado'] as bool? ?? false,
    coordinadorNotificadoAt: DateTime.tryParse(
      map['coordinadorNotificadoAt'] as String? ?? '',
    )?.toUtc(),
  );

  @override
  bool operator ==(Object other) => other is Novedad && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Novedad($titulo, ${prioridad.valor}, ${estado.valor})';
}