/// Punto geográfico del dominio.
///
/// Deliberadamente NO usa `GeoPoint` de Firebase: el dominio no debe depender
/// de la capa de datos. El mapeo a `GeoPoint` ocurre en los datasources.
library;

/// Coordenada en grados decimales (WGS84).
class GeoPoint {
  const GeoPoint(this.latitud, this.longitud);

  final double latitud;
  final double longitud;

  GeoPoint copyWith({double? latitud, double? longitud}) =>
      GeoPoint(latitud ?? this.latitud, longitud ?? this.longitud);

  Map<String, dynamic> toMap() => {'lat': latitud, 'lng': longitud};

  /// Reconstruye desde el formato persistido en Firestore.
  factory GeoPoint.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GeoPoint(0, 0);
    final lat = _toDouble(map['lat'] ?? map['latitude'] ?? map['latitud']);
    final lng = _toDouble(map['lng'] ?? map['longitude'] ?? map['longitud']);
    return GeoPoint(lat, lng);
  }

  static double _toDouble(Object? valor) {
    if (valor is num) return valor.toDouble();
    if (valor is String) return double.tryParse(valor) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitud == latitud && other.longitud == longitud;

  @override
  int get hashCode => Object.hash(latitud, longitud);

  @override
  String toString() =>
      'GeoPoint(${latitud.toStringAsFixed(6)}, ${longitud.toStringAsFixed(6)})';
}