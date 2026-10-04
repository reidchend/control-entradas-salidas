import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/fecha_utils.dart';

/// Línea de tiempo de habitaciones para un rango de fechas (semana o mes).
///
/// Cada fila es una habitación; las barras representan estancias/reservas
/// superpuestas al rango, coloreadas por estado y con el nombre del huésped.
class HabitacionesTimeline extends StatelessWidget {
  const HabitacionesTimeline({
    super.key,
    required this.habitaciones,
    required this.reservas,
    required this.desde,
    required this.hasta,
    required this.anchoDia,
    required this.onTap,
  });

  final List<Habitacion> habitaciones;
  final List<HostelReserva> reservas;
  final DateTime desde;
  final DateTime hasta;
  final double anchoDia;
  final void Function(Habitacion hab, HostelReserva r) onTap;

  static const double _labelW = 96;
  static const double _rowH = 46;
  static const double _headerH = 52;

  int get _dias => diasEntre(desde, hasta) + 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  for (final hab in habitaciones) _fila(context, hab),
                ],
              ),
            ),
          ),
        ),
        _leyenda(context),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoy = soloFecha(DateTime.now());
    return Container(
      height: _headerH,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _labelW),
          for (var i = 0; i < _dias; i++)
            SizedBox(
              width: anchoDia,
              child: _headerCelda(context, desde.add(Duration(days: i)), hoy),
            ),
        ],
      ),
    );
  }

  Widget _headerCelda(BuildContext context, DateTime fecha, DateTime hoy) {
    final esHoy = mismoDia(fecha, hoy);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(diaCorto(fecha).toUpperCase(),
              style: const TextStyle(fontSize: 10)),
          Text(
            '${fecha.day}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: esHoy ? appColor(context, 'warning') : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(BuildContext context, Habitacion hab) {
    final scheme = Theme.of(context).colorScheme;
    final deHab = [
      for (final r in reservas)
        if (r.habitacionId == hab.id) r,
    ];
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _labelW,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'HAB ${hab.numero}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          SizedBox(
            width: anchoDia * _dias,
            height: _rowH,
            child: Stack(
              children: [
                for (var i = 0; i <= _dias; i++)
                  Positioned(
                    left: i * anchoDia,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: scheme.outlineVariant),
                  ),
                for (final r in deHab) _barra(context, hab, r),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barra(BuildContext context, Habitacion hab, HostelReserva r) {
    final inicio = diasEntre(desde, soloFecha(r.fechaIngreso));
    if (inicio >= _dias) return const SizedBox.shrink();
    final start = inicio < 0 ? 0 : inicio;
    final fin = r.esPorHoras
        ? inicio + 1
        : diasEntre(desde, soloFecha(r.fechaSalida));
    final end = fin <= start ? start + 1 : (fin > _dias ? _dias : fin);
    final ancho = (end - start) * anchoDia - 3;
    final color = _color(context, r);
    final onColor = _onColor(context, r);
    final etiqueta = r.esPorHoras
        ? '${r.huespedNombre ?? ''} (OP)'
        : (r.huespedNombre ?? '');
    return Positioned(
      left: start * anchoDia + 1.5,
      top: 6,
      height: _rowH - 12,
      width: ancho,
      child: Tooltip(
        message: '${r.huespedNombre ?? ''} · ${r.modalidadLabel} · '
            '${r.estado.toDb()}',
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onTap(hab, r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: onColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _color(BuildContext context, HostelReserva r) {
    final scheme = Theme.of(context).colorScheme;
    return switch (r.estado) {
      HostelReservaEstado.ocupada => scheme.error,
      HostelReservaEstado.reservada => scheme.tertiary,
      HostelReservaEstado.finalizada => scheme.surfaceContainerHighest,
      HostelReservaEstado.cancelada => scheme.surfaceContainerHighest,
    };
  }

  Color _onColor(BuildContext context, HostelReserva r) {
    final scheme = Theme.of(context).colorScheme;
    return switch (r.estado) {
      HostelReservaEstado.ocupada => scheme.onError,
      HostelReservaEstado.reservada => scheme.onTertiary,
      HostelReservaEstado.finalizada => scheme.onSurface,
      HostelReservaEstado.cancelada => scheme.onSurface,
    };
  }

  Widget _leyenda(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String texto, Color color) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Text(texto, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Wrap(
        children: [
          chip('Ocupada', scheme.error),
          chip('Reservada', scheme.tertiary),
          chip('Finalizada', scheme.surfaceContainerHighest),
        ],
      ),
    );
  }
}
