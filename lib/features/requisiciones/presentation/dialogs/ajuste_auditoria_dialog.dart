import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calculadora/presentation/calculadora.dart';
import '../../data/requisiciones_providers.dart';
import '../../data/requisiciones_repository.dart';

/// Resultado del ajuste de stock durante auditoría.
class AjusteStockResult {
  const AjusteStockResult({
    required this.productoId,
    required this.nuevaCantidad,
    required this.pesoTotal,
  });

  final int productoId;
  final double nuevaCantidad;
  final double? pesoTotal;
}

/// Diálogo de ajuste de stock en auditoría (porta `_show_adjust_dialog` de
/// audit_view.py). Devuelve [AjusteStockResult] o `null`.
Future<AjusteStockResult?> showAjusteAuditoriaDialog(
  BuildContext context, {
  required AuditItem item,
  required String almacen,
}) {
  return showDialog<AjusteStockResult>(
    context: context,
    builder: (ctx) => _AjusteDialog(item: item, almacen: almacen),
  );
}

class _AjusteDialog extends ConsumerStatefulWidget {
  const _AjusteDialog({required this.item, required this.almacen});

  final AuditItem item;
  final String almacen;

  @override
  ConsumerState<_AjusteDialog> createState() => _AjusteDialogState();
}

class _AjusteDialogState extends ConsumerState<_AjusteDialog> {
  final _pesoTotalCtrl = TextEditingController();
  final _finalCtrl = TextEditingController();
  final _inicialCtrl = TextEditingController();
  bool _esPesable = false;
  bool _procesando = false;

  double get _inicial => widget.item.origen.inicial;
  double get _trasladada => widget.item.origen.trasladada;

  TextEditingController get _campoPrincipal =>
      _esPesable ? _pesoTotalCtrl : _inicialCtrl;

  @override
  void initState() {
    super.initState();
    final finalActual = _inicial - _trasladada;
    _pesoTotalCtrl.text = _inicial.toStringAsFixed(3);
    _finalCtrl.text = finalActual.toStringAsFixed(3);
    _inicialCtrl.text = _inicial.toInt().toString();
    _cargarProducto();
  }

  @override
  void dispose() {
    _pesoTotalCtrl.dispose();
    _finalCtrl.dispose();
    _inicialCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProducto() async {
    final repo = ref.read(requisicionesRepoProvider);
    if (repo == null) return;
    final p = await repo.getProducto(widget.item.productoId ?? -1);
    if (mounted && p != null) {
      setState(() => _esPesable = p['es_pesable'] == true || p['es_pesable'] == 1);
    }
  }

  void _recalcDesdePesoTotal() {
    try {
      final pt = double.tryParse(_pesoTotalCtrl.text.replaceAll(',', '.')) ?? 0;
      _finalCtrl.text = (pt - _trasladada).toStringAsFixed(3);
    } catch (_) {}
  }

  void _onInicialChange() {
    try {
      final inic = double.tryParse(_inicialCtrl.text) ?? 0;
      _finalCtrl.text = (inic - _trasladada).toInt().toString();
    } catch (_) {}
  }

  void _onFinalChangeNoPesable() {
    try {
      final fin = double.tryParse(_finalCtrl.text) ?? 0;
      _inicialCtrl.text = (fin + _trasladada).toInt().toString();
    } catch (_) {}
  }

  /// Abre la calculadora (F1) apuntando al campo principal.
  void _abrirCalculadora() {
    final initial =
        double.tryParse(_campoPrincipal.text.replaceAll(',', '.')) ?? 0;
    showCalculadoraDialog(context, initialValue: initial).then((result) {
      if (result != null && mounted) {
        final formatted = _formatearResultado(result);
        _campoPrincipal.text = formatted;
        _campoPrincipal.selection =
            TextSelection.collapsed(offset: formatted.length);
        // Recalcular stock final después de cambiar el valor.
        if (_esPesable) {
          _recalcDesdePesoTotal();
        } else {
          _onInicialChange();
        }
      }
    });
  }

  String _formatearResultado(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _aceptar() async {
    if (_procesando) return;
    setState(() => _procesando = true);

    final repo = ref.read(requisicionesRepoProvider);
    if (repo == null) {
      if (mounted) setState(() => _procesando = false);
      return;
    }
    final p = widget.item.productoId ?? -1;
    if (_esPesable) {
      final pesoTotal = double.tryParse(_pesoTotalCtrl.text.replaceAll(',', '.')) ?? -1;
      if (pesoTotal <= 0) {
        _snack('El peso debe ser mayor a 0');
        if (mounted) setState(() => _procesando = false);
        return;
      }
      await repo.crearAjusteStock(
        productoId: p,
        almacen: widget.almacen,
        nuevaCantidad: pesoTotal,
        motivo: 'Ajuste durante auditoría',
        pesoTotal: pesoTotal,
      );
      if (mounted) {
        Navigator.pop(context, AjusteStockResult(
          productoId: p,
          nuevaCantidad: pesoTotal,
          pesoTotal: pesoTotal,
        ));
      }
    } else {
      final nuevaQty = double.tryParse(_inicialCtrl.text) ?? -1;
      if (nuevaQty < 0) {
        _snack('La cantidad no puede ser negativa');
        if (mounted) setState(() => _procesando = false);
        return;
      }
      await repo.crearAjusteStock(
        productoId: p,
        almacen: widget.almacen,
        nuevaCantidad: nuevaQty,
        motivo: 'Ajuste durante auditoría',
      );
      if (mounted) {
        Navigator.pop(context, AjusteStockResult(
          productoId: p,
          nuevaCantidad: nuevaQty,
          pesoTotal: null,
        ));
      }
    }
    if (mounted) setState(() => _procesando = false);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f1) {
        _abrirCalculadora();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _aceptar();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final campos = _esPesable
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trasladada: ${_trasladada.toStringAsFixed(3)} kg',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: _pesoTotalCtrl,
                decoration: InputDecoration(
                  labelText: 'Peso Inicial (kg)',
                  border: const OutlineInputBorder(),
                  suffixIcon: CalculadoraSuffixIcon(
                    targetController: _pesoTotalCtrl,
                    onResult: (result) {
                      setState(() {
                        _finalCtrl.text =
                            (result - _trasladada).toStringAsFixed(3);
                      });
                    },
                  ),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(_recalcDesdePesoTotal),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _finalCtrl,
                decoration: InputDecoration(
                    labelText: 'Stock Final',
                    border: const OutlineInputBorder(),
                    suffixIcon: CalculadoraSuffixIcon(
                      targetController: _finalCtrl,
                      onResult: (result) {
                        setState(() {
                          _pesoTotalCtrl.text =
                              (result + _trasladada).toStringAsFixed(3);
                        });
                      },
                    ),
                    suffixText: 'kg'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {
                  try {
                    final nuevoFinal = double.tryParse(_finalCtrl.text.replaceAll(',', '.')) ?? 0;
                    _pesoTotalCtrl.text = (nuevoFinal + _trasladada).toStringAsFixed(3);
                  } catch (_) {}
                }),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cantidad a trasladar: ${_trasladada.toInt()}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inicialCtrl,
                      decoration: InputDecoration(
                        labelText: 'Stock Inicial',
                        border: const OutlineInputBorder(),
                        suffixIcon:
                            CalculadoraSuffixIcon(targetController: _inicialCtrl),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(_onInicialChange),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _finalCtrl,
                      decoration: InputDecoration(
                        labelText: 'Stock Final',
                        border: const OutlineInputBorder(),
                        suffixIcon:
                            CalculadoraSuffixIcon(targetController: _finalCtrl),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(_onFinalChangeNoPesable),
                    ),
                  ),
                ],
              ),
            ],
          );

    return AlertDialog(
      title: Text('Ajustar ${widget.item.ingrediente}'),
      content: Focus(
        onKeyEvent: _onKeyEvent,
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock actual: ${_inicial.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 10),
              campos,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _procesando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        Tooltip(
          message: 'Abrir calculadora (F1)',
          child: OutlinedButton.icon(
            onPressed: _procesando ? null : _abrirCalculadora,
            icon: const Icon(Icons.calculate, size: 18),
            label: const Text('Calculadora'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _procesando ? null : _aceptar,
          child: _procesando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Aceptar'),
        ),
      ],
    );
  }
}
