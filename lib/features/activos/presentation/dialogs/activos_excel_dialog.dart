import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/modal_sizing.dart';
import '../../data/activos_providers.dart';

/// Diálogo de exportación de activos a Excel.
///
/// Genera un XLSX con dos hojas: "Activos" (todos) y "Totales por Grupo"
/// (conteo, unidades y valor total por categoría+grupo).
Future<void> showActivosExcelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _ActivosExcelDialog(),
  );
}

class _ActivosExcelDialog extends ConsumerStatefulWidget {
  const _ActivosExcelDialog();

  @override
  ConsumerState<_ActivosExcelDialog> createState() => _ActivosExcelDialogState();
}

class _ActivosExcelDialogState extends ConsumerState<_ActivosExcelDialog> {
  bool _exportando = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Exportar Activos a Excel'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: modalContentWidth(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se generará un archivo con dos hojas:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text('• Activos: lista completa con todos sus parámetros.'),
            const Text('• Totales por Grupo: cantidad, unidades y valor '
                'total agrupados por categoría y grupo.'),
            const SizedBox(height: 8),
            Text(
              'Incluye también los activos desactivados.',
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
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Exportar'),
        ),
      ],
    );
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      final repo = ref.read(activosRepoProvider)!;
      final activos = await repo.getActivosParaExportar();
      final totales = await repo.getTotalesPorGrupo();

      if (activos.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('No hay activos para exportar')));
        return;
      }

      final ahora = DateTime.now();
      String p(int v) => v.toString().padLeft(2, '0');
      final nombre =
          'activos_${ahora.year}${p(ahora.month)}${p(ahora.day)}.xlsx';
      _generarExcel(activos, totales, nombre);

      messenger.showSnackBar(
          SnackBar(content: Text('Archivo guardado: $nombre')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error al exportar: $e'),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  void _generarExcel(
    List<Map<String, dynamic>> activos,
    List<Map<String, dynamic>> totales,
    String nombre,
  ) {
    final excel = Excel.createExcel();
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('FF366092'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      fontSize: 11,
    );

    _hojaActivos(excel, headerStyle, activos);
    _hojaTotales(excel, headerStyle, totales);

    excel.save(fileName: nombre);
  }

  void _hojaActivos(
    Excel excel,
    CellStyle headerStyle,
    List<Map<String, dynamic>> activos,
  ) {
    final sheet = excel['Activos'];
    const headers = [
      'Categoría',
      'Grupo',
      'Tipo',
      'Ubicación',
      'Estado',
      'Valor (Bs)',
      'Fecha',
      'Modelo',
      'Observaciones',
    ];
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (var c = 0; c < headers.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
    }

    for (final a in activos) {
      sheet.appendRow([
        TextCellValue((a['categoria_nombre'] as String?) ?? 'Sin categoría'),
        TextCellValue((a['grupo'] as String?) ?? 'Sin grupo'),
        TextCellValue((a['nombre'] as String?) ?? 'Sin tipo'),
        TextCellValue((a['ubicacion'] as String?) ?? ''),
        TextCellValue((a['estado'] as String?) ?? ''),
        DoubleCellValue(_toDouble(a['valor'])),
        TextCellValue(_fechaCorta(a['fecha'])),
        TextCellValue((a['modelo'] as String?) ?? ''),
        TextCellValue((a['observaciones'] as String?) ?? ''),
      ]);
    }
  }

  void _hojaTotales(
    Excel excel,
    CellStyle headerStyle,
    List<Map<String, dynamic>> totales,
  ) {
    final sheet = excel['Totales por Grupo'];
    const headers = [
      'Categoría',
      'Grupo',
      'N° Activos',
      'Unidades',
      'Valor Total (Bs)',
    ];
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (var c = 0; c < headers.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
    }

    for (final t in totales) {
      sheet.appendRow([
        TextCellValue((t['categoria_nombre'] as String?) ?? 'Sin categoría'),
        TextCellValue((t['grupo'] as String?) ?? 'Sin grupo'),
        DoubleCellValue(_toDouble(t['n_activos'])),
        DoubleCellValue(_toDouble(t['unidades'])),
        DoubleCellValue(_toDouble(t['valor_total'])),
      ]);
    }
  }

  double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  String _fechaCorta(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}