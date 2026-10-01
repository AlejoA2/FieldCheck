/// Visita de supervisión: una jornada de un supervisor en un centro de costo.
///
/// Es la entidad que más evidencia de confiabilidad acumula, y por eso lleva
/// tanto la validación geográfica (check-in/check-out) como el resultado del
/// checklist, las evidencias y su estado de sincronización.
library;

import 'enums.dart';
import 'geo_point.dart';

/// Marca temporal de un punto de control (check-in o check-out).
class MarcadorVisita {
  const MarcadorVisita({required this.momento, required this.posicion});

  final DateTime momento;
  final GeoPoint posicion;

  Map<String, dynamic> toMap() => {
    'momento': momento.toIso8601String(),
    'posicion': posicion.toMap(),
  };

  factory MarcadorVisita.fromMap(Map<String, dynamic> map) => MarcadorVisita(
    momento: DateTime.tryParse(map['momento'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    posicion: GeoPoint.fromMap(
      map['posicion'] == null
          ? null
          : Map<String, dynamic>.from(map['posicion'] as Map),
    ),
  );
}

/// Resultado registrado para una actividad del checklist.
class RegistroActividad {
  const RegistroActividad({
    required this.actividadId,
    required this.descripcion,
    required this.resultado,
    this.comentario = '',
  });

  final String actividadId;

  /// Copia de la descripción al momento de la visita, para que el historial no
  /// cambie si el centro de costo edita su checklist después.
  final String descripcion;

  final ResultadoActividad resultado;
  final String comentario;

  bool get fueCumplida => resultado == ResultadoActividad.cumplida;
  bool get fueIncumplida => resultado == ResultadoActividad.noCumplida;

  RegistroActividad copyWith({ResultadoActividad? resultado, String? comentario}) =>
      RegistroActividad(
        actividadId: actividadId,
        descripcion: descripcion,
        resultado: resultado ?? this.resultado,
        comentario: comentario ?? this.comentario,
      );

  Map<String, dynamic> toMap() => {
    'actividadId': actividadId,
    'descripcion': descripcion,
    'resultado': resultado.valor,
    'comentario': comentario,
  };

  factory RegistroActividad.fromMap(Map<String, dynamic> map) => RegistroActividad(
    actividadId: map['actividadId'] as String? ?? '',
    descripcion: map['descripcion'] as String? ?? '',
    resultado: ResultadoActividad.desdeValor(map['resultado'] as String?),
    comentario: map['comentario'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is RegistroActividad && other.actividadId == actividadId;

  @override
  int get hashCode => actividadId.hashCode;
}

class Visita {
  const Visita({
    required this.id,
    required this.supervisorId,
    required this.centroCostoId,
    required this.fechaProgramada,
    this.checkIn,
    this.checkOut,
    this.actividades = const [],
    this.observaciones = '',
    this.estado = EstadoVisita.pendiente,
    this.syncStatus = SyncStatus.pendiente,
    this.distanciaCheckInMetros,
    this.distanciaCheckOutMetros,
    this.actualizadaAt,
  });

  /// Id generado en el cliente. Se usa como ID del documento en Firestore para
  /// que reintentar una subida sobrescriba en vez de duplicar.
  final String id;

  final String supervisorId;
  final String centroCostoId;

  /// Fecha en la que el coordinador programó la visita.
  final DateTime fechaProgramada;

  final MarcadorVisita? checkIn;
  final MarcadorVisita? checkOut;

  /// Resultados del checklist. Vacío hasta que el supervisor registre.
  final List<RegistroActividad> actividades;

  final String observaciones;

  final EstadoVisita estado;
  final SyncStatus syncStatus;

  /// Distancia al centro de costo al hacer check-in / check-out. Se guarda para
  /// que el coordinador pueda auditar la validación sin recalcularla.
  final double? distanciaCheckInMetros;
  final double? distanciaCheckOutMetros;

  final DateTime? actualizadaAt;

  bool get tieneCheckIn => checkIn != null;
  bool get tieneCheckOut => checkOut != null;

  /// Duración entre check-in y check-out. `null` si la visita sigue abierta.
  Duration? get duracion {
    final entrada = checkIn?.momento;
    final salida = checkOut?.momento;
    if (entrada == null || salida == null) return null;
    final d = salida.difference(entrada);
    return d.isNegative ? null : d;
  }

  /// Actividades evaluadas (excluye "no aplica").
  List<RegistroActividad> get actividadesEvaluadas =>
      actividades.where((a) => a.resultado != ResultadoActividad.noAplica).toList();

  int get totalCumplidas =>
      actividadesEvaluadas.where((a) => a.fueCumplida).length;

  int get totalIncumplidas =>
      actividadesEvaluadas.where((a) => a.fueIncumplida).length;

  /// Porcentaje de cumplimiento (0-100) sobre las actividades evaluadas.
  ///
  /// Devuelve 100 si no hay nada que evaluar: una visita sin checklist
  /// verificable no debe penalizar al supervisor.
  double get porcentajeCumplimiento {
    final evaluadas = actividadesEvaluadas.length;
    if (evaluadas == 0) return 100;
    return totalCumplidas / evaluadas * 100;
  }

  /// `true` si se registró alguna actividad no cumplida.
  bool get hayIncumplimientos => totalIncumplidas > 0;

  Visita copyWith({
    MarcadorVisita? checkIn,
    MarcadorVisita? checkOut,
    List<RegistroActividad>? actividades,
    String? observaciones,
    EstadoVisita? estado,
    SyncStatus? syncStatus,
    double? distanciaCheckInMetros,
    double? distanciaCheckOutMetros,
    DateTime? actualizadaAt,
  }) {
    return Visita(
      id: id,
      supervisorId: supervisorId,
      centroCostoId: centroCostoId,
      fechaProgramada: fechaProgramada,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      actividades: actividades ?? this.actividades,
      observaciones: observaciones ?? this.observaciones,
      estado: estado ?? this.estado,
      syncStatus: syncStatus ?? this.syncStatus,
      distanciaCheckInMetros: distanciaCheckInMetros ?? this.distanciaCheckInMetros,
      distanciaCheckOutMetros: distanciaCheckOutMetros ?? this.distanciaCheckOutMetros,
      actualizadaAt: actualizadaAt ?? this.actualizadaAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'supervisorId': supervisorId,
    'centroCostoId': centroCostoId,
    'fechaProgramada': fechaProgramada.toIso8601String(),
    if (checkIn != null) 'checkIn': checkIn!.toMap(),
    if (checkOut != null) 'checkOut': checkOut!.toMap(),
    'actividades': actividades.map((a) => a.toMap()).toList(),
    'observaciones': observaciones,
    'estado': estado.valor,
    'syncStatus': syncStatus.valor,
    if (distanciaCheckInMetros != null) 'distanciaCheckInMetros': distanciaCheckInMetros,
    if (distanciaCheckOutMetros != null) 'distanciaCheckOutMetros': distanciaCheckOutMetros,
    if (actualizadaAt != null) 'actualizadaAt': actualizadaAt!.toIso8601String(),
  };

  factory Visita.fromMap(Map<String, dynamic> map) => Visita(
    id: map['id'] as String? ?? '',
    supervisorId: map['supervisorId'] as String? ?? '',
    centroCostoId: map['centroCostoId'] as String? ?? '',
    fechaProgramada: DateTime.tryParse(map['fechaProgramada'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    checkIn: _marcadorDesde(map['checkIn']),
    checkOut: _marcadorDesde(map['checkOut']),
    actividades: (map['actividades'] as List<dynamic>? ?? const [])
        .map((e) => RegistroActividad.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    observaciones: map['observaciones'] as String? ?? '',
    estado: EstadoVisita.desdeValor(map['estado'] as String?),
    syncStatus: SyncStatus.desdeValor(map['syncStatus'] as String?),
    distanciaCheckInMetros: _aDouble(map['distanciaCheckInMetros']),
    distanciaCheckOutMetros: _aDouble(map['distanciaCheckOutMetros']),
    actualizadaAt: DateTime.tryParse(map['actualizadaAt'] as String? ?? '')?.toUtc(),
  );

  static MarcadorVisita? _marcadorDesde(Object? valor) {
    if (valor == null) return null;
    return MarcadorVisita.fromMap(Map<String, dynamic>.from(valor as Map));
  }

  static double? _aDouble(Object? valor) => valor is num ? valor.toDouble() : null;

  @override
  bool operator ==(Object other) => other is Visita && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Visita($id, ${estado.valor}, sync: ${syncStatus.valor})';
}