import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/exportar_archivo.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/inventario_providers.dart';

Future<void> showLibroInventarioMensualDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _LibroInventarioMensualDialog(),
  );
}

class _LibroInventarioMensualDialog extends ConsumerStatefulWidget {
  const _LibroInventarioMensualDialog();

  @override
  ConsumerState<_LibroInventarioMensualDialog> createState() =>
      _LibroInventarioMensualDialogState();
}

class _LibroInventarioMensualDialogState
    extends ConsumerState<_LibroInventarioMensualDialog> {
  DateTime _fechaInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fechaFin = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  bool _exportando = false;

  Future<void> _seleccionarFechaInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _fechaInicio = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _seleccionarFechaFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaFin,
      firstDate: _fechaInicio,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _fechaFin = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    try {
      final repo = ref.read(inventarioRepoProvider)!;
      final datos = await repo.getLibroInventarioMensual(
        fechaInicio: _fechaInicio,
        fechaFin: _fechaFin,
      );

      if (datos.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('No hay movimientos en el periodo seleccionado')));
        setState(() => _exportando = false);
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel['Libro de Inventario'];
      excel.delete('Sheet1');

      final headerStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('FF1F4E79'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final headers = [
        'Código',
        'Producto',
        'Categoría',
        'Unidad',
        'Saldo Inicial',
        'Entradas',
        'Ventas',
        'Salidas/Consumos',
        'Ajustes (+)',
        'Ajustes (-)',
        'Saldo Final',
      ];

      sheet.appendRow([for (final h in headers) TextCellValue(h)]);
      for (var c = 0; c < headers.length; c++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
          TextCellValue(headers[c]),
          cellStyle: headerStyle,
        );
      }

      for (final row in datos) {
        sheet.appendRow([
          TextCellValue(row['codigo']?.toString() ?? ''),
          TextCellValue(row['producto']?.toString() ?? ''),
          TextCellValue(row['categoria']?.toString() ?? 'Sin categoría'),
          TextCellValue(row['unidad']?.toString() ?? 'UND'),
          DoubleCellValue(_toDouble(row['saldo_inicial'])),
          DoubleCellValue(_toDouble(row['entradas'])),
          DoubleCellValue(_toDouble(row['ventas'])),
          DoubleCellValue(_toDouble(row['salidas'])),
          DoubleCellValue(_toDouble(row['ajustes_pos'])),
          DoubleCellValue(_toDouble(row['ajustes_neg'])),
          DoubleCellValue(_toDouble(row['saldo_final'])),
        ]);
      }

      final fmt = DateFormat('yyyyMM');
      final nombre = 'LibroInventario_${fmt.format(_fechaInicio)}_${fmt.format(_fechaFin)}.xlsx';
      final ruta = await guardarExcel(excel, nombre);
      if (!mounted) return;

      if (ruta == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Exportación cancelada')));
        Navigator.pop(context);
        return;
      }

      messenger.showSnackBar(SnackBar(
        content: Text('Archivo guardado: $ruta'),
        backgroundColor: scheme.primary,
        duration: const Duration(seconds: 5),
      ));
      Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error al generar reporte: $e'),
        backgroundColor: scheme.error,
      ));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('dd/MM/yyyy');

    return AlertDialog(
      title: const Text('Libro de Inventario Mensual'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: modalContentWidth(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Seleccione el periodo a reportar'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportando ? null : _seleccionarFechaInicio,
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Desde: ${fmt.format(_fechaInicio)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportando ? null : _seleccionarFechaFin,
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Hasta: ${fmt.format(_fechaFin)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Incluye: Saldo Inicial, Entradas, Ventas, Salidas/Consumos, Ajustes (+/-) y Saldo Final',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (_exportando)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exportando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _exportando ? null : _exportar,
          icon: const Icon(Icons.download),
          label: const Text('Generar Excel'),
        ),
      ],
    );
  }
}
