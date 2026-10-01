/// Centro de costo: el establecimiento donde se presta el servicio y donde el
/// supervisor realiza sus visitas.
///
/// Incluye el geofence (`radioToleranciaMetros`) y el checklist de actividades
/// que el supervisor debe verificar en cada visita.
library;

import 'geo_point.dart';

/// Actividad del plan de trabajo que el supervisor debe verificar.
class ActividadChecklist {
  const ActividadChecklist({
    required this.id,
    required this.descripcion,
    this.observacion = '',
    this.requiereEvidencia = false,
  });

  final String id;
  final String descripcion;

  /// Texto de apoyo que se muestra al supervisor durante la visita.
  final String observacion;

  /// Si es `true`, el supervisor debe adjuntar al menos una foto para marcarla
  /// como cumplida. Refuerza la trazabilidad de la evidencia.
  final bool requiereEvidencia;

  Map<String, dynamic> toMap() => {
    'id': id,
    'descripcion': descripcion,
    'observacion': observacion,
    'requiereEvidencia': requiereEvidencia,
  };

  factory ActividadChecklist.fromMap(Map<String, dynamic> map) => ActividadChecklist(
    id: map['id'] as String? ?? '',
    descripcion: map['descripcion'] as String? ?? '',
    observacion: map['observacion'] as String? ?? '',
    requiereEvidencia: map['requiereEvidencia'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) => other is ActividadChecklist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Estado del geofence de un centro de costo, por si se requiere inspeccionarlo.
class CentroCosto {
  const CentroCosto({
    required this.id,
    required this.nombre,
    required this.ubicacion,
    this.direccion = '',
    this.radioToleranciaMetros = 100,
    this.actividades = const [],
    this.supervisoresAsignados = const [],
    this.contacto,
    this.activo = true,
  });

  final String id;
  final String nombre;
  final String direccion;

  /// Punto de referencia del centro de costo.
  final GeoPoint ubicacion;

  /// Radio válido para considerarle "en sitio" durante el check-in/check-out.
  ///
  /// Un radio mayor reduce falsas negativas (señal GPS débil, edificio grande
  /// con patio interior) a costa de admitir más superficie. 100 m es un punto de
  /// partida razonable y es configurable por centro de costo.
  final double radioToleranciaMetros;

  /// Actividades a verificar en cada visita.
  final List<ActividadChecklist> actividades;

  /// Ids de los supervisores asignados a este centro.
  final List<String> supervisoresAsignados;

  final String? contacto;
  final bool activo;

  bool get tieneActividades => actividades.isNotEmpty;

  CentroCosto copyWith({
    String? nombre,
    String? direccion,
    GeoPoint? ubicacion,
    double? radioToleranciaMetros,
    List<ActividadChecklist>? actividades,
    List<String>? supervisoresAsignados,
    String? contacto,
    bool? activo,
  }) {
    return CentroCosto(
      id: id,
      nombre: nombre ?? this.nombre,
      direccion: direccion ?? this.direccion,
      ubicacion: ubicacion ?? this.ubicacion,
      radioToleranciaMetros: radioToleranciaMetros ?? this.radioToleranciaMetros,
      actividades: actividades ?? this.actividades,
      supervisoresAsignados: supervisoresAsignados ?? this.supervisoresAsignados,
      contacto: contacto ?? this.contacto,
      activo: activo ?? this.activo,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'direccion': direccion,
    'ubicacion': ubicacion.toMap(),
    'latitud': ubicacion.latitud,
    'longitud': ubicacion.longitud,
    'radioToleranciaMetros': radioToleranciaMetros,
    'actividades': actividades.map((a) => a.toMap()).toList(),
    'supervisoresAsignados': supervisoresAsignados,
    if (contacto != null) 'contacto': contacto,
    'activo': activo,
  };

  factory CentroCosto.fromMap(Map<String, dynamic> map) {
    final ubicacion = map['ubicacion'] != null
        ? GeoPoint.fromMap(Map<String, dynamic>.from(map['ubicacion'] as Map))
        : GeoPoint(
            _toDouble(map['latitud']) ?? 0,
            _toDouble(map['longitud']) ?? 0,
          );

    return CentroCosto(
      id: map['id'] as String? ?? '',
      nombre: map['nombre'] as String? ?? '',
      direccion: map['direccion'] as String? ?? '',
      ubicacion: ubicacion,
      radioToleranciaMetros: _toDouble(map['radioToleranciaMetros']) ?? 100,
      actividades: (map['actividades'] as List<dynamic>? ?? const [])
          .map((e) => ActividadChecklist.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      supervisoresAsignados: (map['supervisoresAsignados'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      contacto: map['contacto'] as String?,
      activo: map['activo'] as bool? ?? true,
    );
  }

  static double? _toDouble(Object? valor) => valor is num ? valor.toDouble() : null;

  @override
  bool operator ==(Object other) => other is CentroCosto && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CentroCosto($nombre, radio: ${radioToleranciaMetros}m)';
}

/// Resultado de evaluar la posición del supervisor contra el geofence.
class ResultadoGeofence {
  const ResultadoGeofence({
    required this.dentroDelRadio,
    required this.distanciaMetros,
    required this.radioToleranciaMetros,
  });

  /// `true` si el supervisor está dentro del radio válido.
  final bool dentroDelRadio;

  /// Distancia medida al centro de costo.
  final double distanciaMetros;

  /// Radio configurado para ese centro de costo.
  final double radioToleranciaMetros;

  /// Cuántos metros le sobran (o faltan) para estar dentro del radio.
  double get margenMetros => radioToleranciaMetros - distanciaMetros;

  /// Mensaje listo para mostrar al supervisor.
  String get mensaje => dentroDelRadio
      ? 'Ubicación verificada'
      : 'Estás a ${_entero(distanciaMetros)} m del centro de costo, '
            'fuera del radio válido de ${_entero(radioToleranciaMetros)} m';

  /// Formatea un double sin decimales para mostrarlo como texto ("334", no
  /// "334.0"). Devuelve `String` a propósito: interpolar un `double` en Dart
  /// siempre añade el sufijo ".0", que se ve descuidado en la UI.
  static String _entero(double valor) => valor.toStringAsFixed(0);
}