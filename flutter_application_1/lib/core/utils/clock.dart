/// Fuente de tiempo inyectable.
///
/// Los servicios que dependen del tiempo (cola de sincronización, cálculo de
/// duración de visita, backoff exponencial) reciben un `Clock` en lugar de
/// llamar a `DateTime.now()` directamente. Así los tests pueden simular el
/// paso del tiempo de forma determinista.
library;

/// Reloj inyectable. La implementación real usa el reloj del sistema.
abstract class Clock {
  const Clock();

  /// Fecha y hora actuales en UTC.
  DateTime nowUtc();

  /// Fecha y hora actuales en hora local.
  DateTime nowLocal() => nowUtc().toLocal();

  /// Registro de la actividad, útil paraiagnostics de sincronización.
  DateTime now() => nowUtc();
}

/// Reloj respaldado por el sistema.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Reloj controlado por tests: el tiempo solo avanza si el test lo hace avanzar.
class FakeClock extends Clock {
  FakeClock(this._instante);

  DateTime _instante;

  @override
  DateTime nowUtc() => _instante.toUtc();

  /// Avanza el reloj una cantidad dada.
  void avanzar(Duration duracion) => _instante = _instante.add(duracion);

  /// Fija el reloj en un instante concreto.
  void fijar(DateTime instante) => _instante = instante;
}