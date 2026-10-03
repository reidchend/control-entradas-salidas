import '../../../core/utils/fecha_utils.dart';

/// Vistas de habitaciones: estado actual, semana y mes.
enum HostelVista { actual, semana, mes }

/// Rango de fechas [desde, hasta] (ambos inclusive) de una vista.
typedef HostelRango = ({DateTime desde, DateTime hasta});

/// Calcula el rango de fechas de una vista anclado en [ancla].
HostelRango rangoDe(HostelVista vista, DateTime ancla) {
  switch (vista) {
    case HostelVista.semana:
      return (desde: inicioSemana(ancla), hasta: finSemana(ancla));
    case HostelVista.mes:
      return (desde: inicioMes(ancla), hasta: finMes(ancla));
    case HostelVista.actual:
      return (desde: soloFecha(ancla), hasta: soloFecha(ancla));
  }
}
