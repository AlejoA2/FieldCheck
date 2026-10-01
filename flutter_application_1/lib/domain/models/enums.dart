/// Enumeraciones del dominio.
///
/// Cada enum sabe serializarse a un `String` estable. Esa estabilidad importa:
/// el valor se escribe en Firestore y, una vez guardado, cambiar el nombre del
/// enum o del valor dejaría datos huérfanos. Por eso cada uno declara
/// explícitamente su forma serializada y la deserialización tolera valores
/// desconocidos en lugar de fallar.
library;

/// Rol del usuario en el sistema.
enum UserRole {
  supervisor('supervisor'),
  coordinador('coordinador');

  const UserRole(this.valor);

  /// Representación persistida en Firestore.
  final String valor;

  static UserRole desdeValor(String? valor) {
    return UserRole.values.firstWhere(
      (r) => r.valor == valor,
      orElse: () => UserRole.supervisor,
    );
  }

  String get etiqueta => switch (this) {
    UserRole.supervisor => 'Supervisor',
    UserRole.coordinador => 'Coordinador',
  };
}

/// Estado de la cuenta de un usuario.
enum UserStatus {
  activo('activo'),
  inactivo('inactivo');

  const UserStatus(this.valor);

  final String valor;

  static UserStatus desdeValor(String? valor) {
    return UserStatus.values.firstWhere(
      (s) => s.valor == valor,
      orElse: () => UserStatus.activo,
    );
  }

  String get etiqueta => switch (this) {
    UserStatus.activo => 'Activo',
    UserStatus.inactivo => 'Inactivo',
  };
}

/// Ciclo de vida de una visita de supervisión.
enum EstadoVisita {
  /// Asignada al supervisor, aún sin check-in.
  pendiente('pendiente'),

  /// El supervisor hizo check-in y está ejecutando el checklist.
  enProgreso('en_progreso'),

  /// Check-out registrado. Terminal para el flujo del supervisor.
  completada('completada');

  const EstadoVisita(this.valor);

  final String valor;

  static EstadoVisita desdeValor(String? valor) {
    return EstadoVisita.values.firstWhere(
      (e) => e.valor == valor,
      orElse: () => EstadoVisita.pendiente,
    );
  }

  String get etiqueta => switch (this) {
    EstadoVisita.pendiente => 'Pendiente',
    EstadoVisita.enProgreso => 'En curso',
    EstadoVisita.completada => 'Completada',
  };

  bool get esTerminal => this == EstadoVisita.completada;
}

/// Resultado del registro de una actividad del checklist.
enum ResultadoActividad {
  cumplida('cumplida'),
  noCumplida('no_cumplida'),

  /// La actividad no aplica para este centro de costo en esta visita.
  noAplica('no_aplica');

  const ResultadoActividad(this.valor);

  final String valor;

  static ResultadoActividad desdeValor(String? valor) {
    return ResultadoActividad.values.firstWhere(
      (r) => r.valor == valor,
      orElse: () => ResultadoActividad.noAplica,
    );
  }

  String get etiqueta => switch (this) {
    ResultadoActividad.cumplida => 'Cumplida',
    ResultadoActividad.noCumplida => 'No cumplida',
    ResultadoActividad.noAplica => 'No aplica',
  };
}

/// Prioridad de una novedad reportada.
enum Prioridad {
  alta('alta'),
  media('media'),
  baja('baja');

  const Prioridad(this.valor);

  final String valor;

  static Prioridad desdeValor(String? valor) {
    return Prioridad.values.firstWhere(
      (p) => p.valor == valor,
      orElse: () => Prioridad.media,
    );
  }

  String get etiqueta => switch (this) {
    Prioridad.alta => 'Alta',
    Prioridad.media => 'Media',
    Prioridad.baja => 'Baja',
  };

  /// Las novedades de prioridad alta no deben esperar al ciclo diario.
  bool get requiereAtencionInmediata => this == Prioridad.alta;

  /// Orden de urgencia ascendente, útil para ordenar listados.
  int get pesoUrgencia => switch (this) {
    Prioridad.baja => 0,
    Prioridad.media => 1,
    Prioridad.alta => 2,
  };
}

/// Ciclo de vida de una novedad, desde que el supervisor la reporta hasta su
/// cierre por parte del coordinador.
enum EstadoNovedad {
  abierta('abierta'),
  enRevision('en_revision'),
  resuelta('resuelta');

  const EstadoNovedad(this.valor);

  final String valor;

  static EstadoNovedad desdeValor(String? valor) {
    return EstadoNovedad.values.firstWhere(
      (e) => e.valor == valor,
      orElse: () => EstadoNovedad.abierta,
    );
  }

  String get etiqueta => switch (this) {
    EstadoNovedad.abierta => 'Abierta',
    EstadoNovedad.enRevision => 'En revisión',
    EstadoNovedad.resuelta => 'Resuelta',
  };

  bool get estaCerrada => this == EstadoNovedad.resuelta;
}

/// Tipo de evidencia adjunta a una visita o novedad.
enum TipoEvidencia {
  foto('foto'),
  video('video'),
  documento('documento');

  const TipoEvidencia(this.valor);

  final String valor;

  static TipoEvidencia desdeValor(String? valor) {
    return TipoEvidencia.values.firstWhere(
      (t) => t.valor == valor,
      orElse: () => TipoEvidencia.foto,
    );
  }

  String get etiqueta => switch (this) {
    TipoEvidencia.foto => 'Fotografía',
    TipoEvidencia.video => 'Video',
    TipoEvidencia.documento => 'Documento',
  };
}

/// Estado de sincronización de un registro respecto al servidor.
///
/// Es el campo que hace explícito el requisito de "control de registros
/// pendientes de sincronización" del reto: todo registro creado en campo nace
/// en [pendiente] y solo pasa a [sincronizado] cuando el servidor confirma.
enum SyncStatus {
  /// Solo existe en el dispositivo, esperando red.
  pendiente('pending_sync'),

  /// En curso de subida; si el proceso muere aquí, vuelve a [pendiente].
  sincronizando('syncing'),

  /// Confirmado por el servidor. Estado terminal.
  sincronizado('synced'),

  /// Agotó los reintentos automáticos; requiere intervención o nuevo intento.
  fallido('failed');

  const SyncStatus(this.valor);

  final String valor;

  static SyncStatus desdeValor(String? valor) {
    return SyncStatus.values.firstWhere(
      (s) => s.valor == valor,
      orElse: () => SyncStatus.pendiente,
    );
  }

  String get etiqueta => switch (this) {
    SyncStatus.pendiente => 'Pendiente de sincronizar',
    SyncStatus.sincronizando => 'Sincronizando',
    SyncStatus.sincronizado => 'Sincronizado',
    SyncStatus.fallido => 'Error al sincronizar',
  };

  bool get requiereSync => this != SyncStatus.sincronizado;
}

/// Colección remota sobre la que opera la cola de sincronización.
///
/// Determina a qué documento de Firestore se escribe cada item encolado.
enum TipoEntidad {
  visita('visitas'),
  novedad('novedades'),
  evidencia('evidencias');

  const TipoEntidad(this.valor);

  /// Nombre de la colección en Firestore.
  final String valor;

  static TipoEntidad desdeValor(String? valor) {
    return TipoEntidad.values.firstWhere(
      (t) => t.valor == valor,
      orElse: () => TipoEntidad.visita,
    );
  }

  String get etiqueta => switch (this) {
    TipoEntidad.visita => 'Visita',
    TipoEntidad.novedad => 'Novedad',
    TipoEntidad.evidencia => 'Evidencia',
  };
}
