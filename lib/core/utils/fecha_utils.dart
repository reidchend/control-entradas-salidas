/// Utilidades de fechas para las vistas de agenda (semana/mes).
library;

const List<String> _diasCortos = [
  'lun',
  'mar',
  'mié',
  'jue',
  'vie',
  'sáb',
  'dom',
];

const List<String> _mesesCortos = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

const List<String> _mesesLargos = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Descarta la hora (deja solo año/mes/día).
DateTime soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lunes de la semana de [d].
DateTime inicioSemana(DateTime d) {
  final f = soloFecha(d);
  return f.subtract(Duration(days: f.weekday - 1));
}

/// Domingo de la semana de [d].
DateTime finSemana(DateTime d) => inicioSemana(d).add(const Duration(days: 6));

/// Primer día del mes de [d].
DateTime inicioMes(DateTime d) => DateTime(d.year, d.month, 1);

/// Último día del mes de [d].
DateTime finMes(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Días completos entre [a] y [b] (puede ser negativo).
int diasEntre(DateTime a, DateTime b) =>
    soloFecha(b).difference(soloFecha(a)).inDays;

/// Suma (o resta, con [meses] negativo) meses, anclando al día 1.
DateTime sumarMeses(DateTime d, int meses) => DateTime(d.year, d.month + meses, 1);

bool mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Abreviatura del día de la semana (lun..dom).
String diaCorto(DateTime d) => _diasCortos[(d.weekday - 1) % 7];

String mesCorto(DateTime d) => _mesesCortos[d.month - 1];

String mesLargo(DateTime d) => _mesesLargos[d.month - 1];

/// Formato `d mmm yyyy` (ej: `5 oct 2026`).
String fmtFecha(DateTime d) => '${d.day} ${mesCorto(d)} ${d.year}';
