import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/historial_providers.dart';
import '../data/historial_repository.dart';
import 'widgets/entrada_card.dart';

/// Tab "Por Fecha" (porta `_build_fecha_tab` + `_load_entradas_por_fecha` de
/// `historial_facturas_view.py`): chips de período rápido (Hoy/Ayer/Antier/
/// semana/mes), selector de fecha específica y listado de entradas agrupadas
/// por día con totales de unidades y kilos.
class PorFechaTab extends ConsumerStatefulWidget {
  const PorFechaTab({super.key});

  @override
  ConsumerState<PorFechaTab> createState() => _PorFechaTabState();
}

class _PorFechaTabState extends ConsumerState<PorFechaTab> {
  static const _periodos = [
    ('Hoy', 'hoy'),
    ('Ayer', 'ayer'),
    ('Antier', 'antier'),
    ('Esta semana', 'semana'),
    ('Este mes', 'mes'),
  ];

  String _periodo = 'hoy';
  DateTime? _fechaEspecifica;

  ({DateTime ini, DateTime fin}) get _rango {
    if (_fechaEspecifica != null) {
      final ini = DateTime(_fechaEspecifica!.year, _fechaEspecifica!.month, _fechaEspecifica!.day);
      return (ini: ini, fin: ini.add(const Duration(days: 1)));
    }
    final hoy = DateTime.now();
    final dia = DateTime(hoy.year, hoy.month, hoy.day);
    late DateTime d1;
    final d2 = dia;
    switch (_periodo) {
      case 'ayer':
        d1 = dia.subtract(const Duration(days: 1));
      case 'antier':
        d1 = dia.subtract(const Duration(days: 2));
      case 'semana':
        d1 = dia.subtract(Duration(days: dia.weekday - 1));
      case 'mes':
        d1 = DateTime(dia.year, dia.month, 1);
      default:
        d1 = dia;
    }
    return (ini: d1, fin: d2.add(const Duration(days: 1)));
  }

  void _seleccionarPeriodo(String key) {
    setState(() {
      _periodo = key;
      _fechaEspecifica = null;
    });
  }

  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _fechaEspecifica = picked);
    }
  }

  void _limpiarFecha() {
    setState(() {
      _fechaEspecifica = null;
      _periodo = 'hoy';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entradasAsync = ref.watch(porFechaProvider(_rango));

    return Column(
      children: [
        _buildSelectorRow(scheme),
        Expanded(
          child: entradasAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: scheme.error))),
            data: (entradas) => _buildListado(entradas, scheme),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorRow(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            color: scheme.primary,
            style: IconButton.styleFrom(backgroundColor: scheme.primary.withValues(alpha: 0.1)),
            tooltip: 'Elegir fecha específica',
            onPressed: _elegirFecha,
          ),
          if (_fechaEspecifica != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Chip(
                label: Text(
                  '(${_fmtCorta(_fechaEspecifica!)})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                visualDensity: VisualDensity.compact,
                onDeleted: _limpiarFecha,
              ),
            )
          else
            const SizedBox(width: 8),
          Container(width: 1, height: 20, color: scheme.outlineVariant),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (label, key) in _periodos) _chip(scheme, label, key),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme scheme, String label, String key) {
    final activo = _fechaEspecifica == null && _periodo == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _seleccionarPeriodo(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: activo ? scheme.primary : scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: activo ? FontWeight.bold : FontWeight.normal,
              color: activo ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListado(List<EntradaPorFecha> entradas, ColorScheme scheme) {
    if (entradas.isEmpty) {
      return Center(
        child: Text('Sin movimientos en este periodo', style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    final grupos = <String, List<EntradaPorFecha>>{};
    for (final e in entradas) {
      grupos.putIfAbsent(_fmtDia(e.fecha), () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final MapEntry(key: dia, value: movs) in grupos.entries) ...[
          _headerDia(scheme, dia, movs),
          for (final e in movs) EntradaCard(entrada: e),
        ],
      ],
    );
  }

  Widget _headerDia(ColorScheme scheme, String dia, List<EntradaPorFecha> movs) {
    final uds = movs.fold<int>(0, (acc, m) => acc + m.cantidad.round());
    final kg = movs.fold<double>(0, (acc, m) => acc + m.pesoTotal);
    var texto = '$dia  •  $uds uds';
    if (kg > 0) texto += '  •  ${kg.toStringAsFixed(3)} kg';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
      ),
    );
  }

  String _fmtDia(DateTime? d) {
    if (d == null) return '??/??/????';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }

  String _fmtCorta(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
