import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/historial_providers.dart';
import '../../data/historial_repository.dart';
import '../../../../core/utils/modal_sizing.dart';

/// Diálogo de exportación del Libro de Compras (porta `_show_export_dialog` +
/// `_exportar_excel` de `historial_facturas_view.py`).
Future<void> showExportarDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _ExportarDialog(),
  );
}

class _ExportarDialog extends ConsumerStatefulWidget {
  const _ExportarDialog();

  @override
  ConsumerState<_ExportarDialog> createState() => _ExportarDialogState();
}

class _ExportarDialogState extends ConsumerState<_ExportarDialog> {
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  late int _mes;
  late final TextEditingController _anioCtrl;
  String _tipo = '';
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = now.month - 1;
    _anioCtrl = TextEditingController(text: now.year.toString());
  }

  @override
  void dispose() {
    _anioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Exportar Libro de Compras'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: modalContentWidth(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Seleccione el período a exportar:', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _mes,
                    decoration: const InputDecoration(labelText: 'Mes', border: OutlineInputBorder(), isDense: true),
                    items: [
                      for (var i = 0; i < 12; i++)
                        DropdownMenuItem(value: i, child: Text(_meses[i])),
                    ],
                    onChanged: (v) => setState(() => _mes = v ?? _mes),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _anioCtrl,
                    decoration: const InputDecoration(labelText: 'Año', border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo de Documento', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('Todos')),
                DropdownMenuItem(value: 'Factura', child: Text('Factura')),
                DropdownMenuItem(value: 'Nota de Entrega', child: Text('Nota de Entrega')),
                DropdownMenuItem(value: 'Entrada', child: Text('Entrada')),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? ''),
            ),
            const SizedBox(height: 12),
            Text(
              'Se exportarán las facturas del mes seleccionado.',
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
      final anio = int.tryParse(_anioCtrl.text.trim()) ?? DateTime.now().year;
      final inicio = DateTime(anio, _mes + 1, 1);
      final fin = DateTime(anio, _mes + 1) // fin de mes
          .add(const Duration(days: 1))
          .subtract(const Duration(days: 1));

      final repo = ref.read(historialRepoProvider)!;
      final rows = await repo.getLibroCompras(inicio, fin, tipoDocumento: _tipo.isEmpty ? null : _tipo);

      if (rows.isEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('No hay facturas validadas en ${_meses[_mes]} $anio'),
        ));
        return;
      }

      final nombre = 'libro_compras_$anio-${(_mes + 1).toString().padLeft(2, '0')}.xlsx';
      _generarExcel(rows, nombre);
      messenger.showSnackBar(SnackBar(content: Text('Archivo guardado: $nombre')));
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

  void _generarExcel(List<LibroComprasRow> rows, String nombre) {
    final excel = Excel.createExcel();
    final sheet = excel['Libro de Compras'];

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('FF366092'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      fontSize: 11,
    );

    const headers = ['Fecha', 'N° Factura', 'Proveedor', 'Efectivo (VES)', 'Transferencia (VES)', 'Divisas (USD)', 'Tasa', 'Total (VES)', 'Validado por'];
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);

    for (var c = 0; c < headers.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
    }

    for (final r in rows) {
      final f = r.factura;
      final ff = DateTime.tryParse(f['fecha_factura']?.toString() ?? '');
      sheet.appendRow([
        TextCellValue(_fmtFecha(ff)),
        TextCellValue((f['numero_factura'] as String?) ?? ''),
        TextCellValue((f['proveedor'] as String?) ?? ''),
        DoubleCellValue(r.efectivo),
        DoubleCellValue(r.transferencia),
        DoubleCellValue(r.divisasUsd),
        if (r.tasa != null) DoubleCellValue(r.tasa!) else null,
        DoubleCellValue((f['total_neto'] as num?)?.toDouble() ?? 0),
        TextCellValue((f['validada_por'] as String?) ?? ''),
      ]);
    }

    excel.save(fileName: nombre);
  }

  String _fmtFecha(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }
}
