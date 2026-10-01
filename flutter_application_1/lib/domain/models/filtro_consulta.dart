/// Criterios de filtrado del panel del coordinador.
///
/// Un solo objeto de valor (inmutable) en lugar de parámetros sueltos: los
/// filtros se combinan entre sí y se usan tanto en streams como en la consulta
/// concreta que alimenta el exportador. Un único tipo evita que esas dos rutas
/// se desincronicen.
library;

import 'enums.dart';
import 'novedad.dart';
import 'visita.dart';

/// Rango de fechas inclusivo aplicado a la fecha programada de la visita.
class RangoFechas {
  const RangoFechas({required this.desde, required this.hasta});

  /// Comienzo del rango, inclusive.
  final DateTime desde;

  /// Fin del rango, inclusive. Se compara por día completo.
  final DateTime hasta;

  /// `true` si [fecha] cae dentro del rango (comparando solo la fecha, sin
  /// hora), que es lo que espera un usuario al filtrar "por día".
  bool contiene(DateTime fecha) {
    final f = DateTime(fecha.year, fecha.month, fecha.day);
    final d = DateTime(desde.year, desde.month, desde.day);
    final h = DateTime(hasta.year, hasta.month, hasta.day);
    return !f.isBefore(d) && !f.isAfter(h);
  }

  /// Etiqueta legible para mostrar en la interfaz ("12/03/2026 - 18/03/2026").
  String get etiqueta =>
      '${_dia(desde)} - ${_dia(hasta)}';

  static String _dia(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  bool operator ==(Object other) =>
      other is RangoFechas && other.desde == desde && other.hasta == hasta;

  @override
  int get hashCode => Object.hash(desde, hasta);
}

/// Filtro de consultas del coordinador.
///
/// Todos los campos son opcionales: `null` significa "sin restricción por este
/// criterio", de modo que el filtro vacío devuelve todo.
class FiltroConsulta {
  const FiltroConsulta({
    this.rango,
    this.supervisorId,
    this.centroCostoId,
    this.estadoVisita,
    this.estadoNovedad,
    this.prioridad,
    this.soloPendientesDeSync = false,
    this.soloConIncumplimientos = false,
  });

  const FiltroConsulta.sinFiltros() : this();

  final RangoFechas? rango;
  final String? supervisorId;
  final String? centroCostoId;
  final EstadoVisita? estadoVisita;

  /// `null` incluye abiertas y resueltas; útil para el KPI de abiertas.
  final EstadoNovedad? estadoNovedad;
  final Prioridad? prioridad;

  /// Filtra por registros que aún no llegaron al servidor. El coordinador lo
  /// usa para distinguir "no hubo visita" de "hay visita sin sincronizar".
  final bool soloPendientesDeSync;

  /// Filtra por visitas con al menos una actividad no cumplida.
  final bool soloConIncumplimientos;

  bool get estaVacio =>
      rango == null &&
      supervisorId == null &&
      centroCostoId == null &&
      estadoVisita == null &&
      estadoNovedad == null &&
      prioridad == null &&
      !soloPendientesDeSync &&
      !soloConIncumplimientos;

  /// Copia con campos substituidos. Los parámetros `null` conservan el valor
  /// actual; para borrar un filtro se usa [FiltroConsulta.limpiar].
  FiltroConsulta copyWith({
    RangoFechas? rango,
    String? supervisorId,
    String? centroCostoId,
    EstadoVisita? estadoVisita,
    EstadoNovedad? estadoNovedad,
    Prioridad? prioridad,
    bool? soloPendientesDeSync,
    bool? soloConIncumplimientos,
  }) {
    return FiltroConsulta(
      rango: rango ?? this.rango,
      supervisorId: supervisorId ?? this.supervisorId,
      centroCostoId: centroCostoId ?? this.centroCostoId,
      estadoVisita: estadoVisita ?? this.estadoVisita,
      estadoNovedad: estadoNovedad ?? this.estadoNovedad,
      prioridad: prioridad ?? this.prioridad,
      soloPendientesDeSync: soloPendientesDeSync ?? this.soloPendientesDeSync,
      soloConIncumplimientos:
          soloConIncumplimientos ?? this.soloConIncumplimientos,
    );
  }

  /// Devuelve una copia sin filtros, para el botón "Limpiar".
  ///
  /// Existe porque `copyWith` no puede poner `null` (eso significaría
  /// "conservar el valor"). Es la misma razón por la que `copyWith` en el resto
  /// del proyecto usa banderas como `limpiarError`.
  FiltroConsulta limpiar() => const FiltroConsulta.sinFiltros();

  /// Aplica el filtro a una visita.
  ///
  /// Vive en el dominio (y no en el datasource) para que el panel web y el
  /// exportador apliquen exactamente la misma lógica: un reporte que no coincide
  /// con lo que se ve en pantalla sería el peor defecto de un panel de control.
  bool coincideVisita(Visita visita) {
    if (supervisorId != null && visita.supervisorId != supervisorId) {
      return false;
    }
    if (centroCostoId != null && visita.centroCostoId != centroCostoId) {
      return false;
    }
    if (estadoVisita != null && visita.estado != estadoVisita) {
      return false;
    }
    if (soloPendientesDeSync && !visita.syncStatus.requiereSync) {
      return false;
    }
    if (soloConIncumplimientos && !visita.hayIncumplimientos) {
      return false;
    }
    final r = rango;
    if (r != null && !r.contiene(visita.fechaProgramada)) {
      return false;
    }
    return true;
  }

  /// Aplica el filtro a una novedad.
  bool coincideNovedad(Novedad novedad) {
    if (centroCostoId != null && novedad.centroCostoId != centroCostoId) {
      return false;
    }
    if (estadoNovedad != null && novedad.estado != estadoNovedad) {
      return false;
    }
    if (prioridad != null && novedad.prioridad != prioridad) {
      return false;
    }
    if (soloPendientesDeSync && !novedad.syncStatus.requiereSync) {
      return false;
    }
    final r = rango;
    if (r != null && !r.contiene(novedad.reportadaAt)) {
      return false;
    }
    return true;
  }
}
