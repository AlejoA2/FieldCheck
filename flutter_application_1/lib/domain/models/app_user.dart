/// Usuario del sistema: supervisor de campo o coordinador de operaciones.
library;

import 'enums.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    this.estado = UserStatus.activo,
    this.telefono,
    this.createdAt,
  });

  /// Identificador. Para el supervisor coincide con el UID de Firebase Auth.
  final String id;
  final String nombre;
  final String email;
  final UserRole rol;
  final UserStatus estado;
  final String? telefono;
  final DateTime? createdAt;

  bool get estaActivo => estado == UserStatus.activo;
  bool get esSupervisor => rol == UserRole.supervisor;
  bool get esCoordinador => rol == UserRole.coordinador;

  AppUser copyWith({
    String? nombre,
    String? email,
    UserRole? rol,
    UserStatus? estado,
    String? telefono,
  }) {
    return AppUser(
      id: id,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      rol: rol ?? this.rol,
      estado: estado ?? this.estado,
      telefono: telefono ?? this.telefono,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'email': email,
    'rol': rol.valor,
    'estado': estado.valor,
    if (telefono != null) 'telefono': telefono,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
    id: map['id'] as String? ?? '',
    nombre: map['nombre'] as String? ?? '',
    email: map['email'] as String? ?? '',
    rol: UserRole.desdeValor(map['rol'] as String?),
    estado: UserStatus.desdeValor(map['estado'] as String?),
    telefono: map['telefono'] as String?,
    createdAt: map['createdAt'] == null
        ? null
        : DateTime.tryParse(map['createdAt'] as String),
  );

  @override
  bool operator ==(Object other) => other is AppUser && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AppUser($nombre, ${rol.valor})';
}