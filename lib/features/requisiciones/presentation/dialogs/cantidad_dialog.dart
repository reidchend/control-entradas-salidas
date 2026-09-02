import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calculadora/presentation/calculadora.dart';
import '../../data/requisiciones_providers.dart';
import '../../data/requisiciones_repository.dart';

class CantidadProductoResult {
  const CantidadProductoResult({
    required this.item,
    required this.peso,
  });

  final RequisicionItem item;
  final double peso;
}

Future<CantidadProductoResult?> showCantidadDialog(
  BuildContext context, {
  required Map<String, dynamic> producto,
  required String origen,
}) {
  return showDialog<CantidadProductoResult>(
    context: context,
    builder: (ctx) => _CantidadDialog(producto: producto, origen: origen),
  );
}

class _CantidadDialog extends ConsumerStatefulWidget {
  const _CantidadDialog({required this.producto, required this.origen});

  final Map<String, dynamic> producto;
  final String origen;

  @override
  ConsumerState<_CantidadDialog> createState() => _CantidadDialogState();
}

class _CantidadDialogState extends ConsumerState<_CantidadDialog> {
  final _pesoTotalCtrl = TextEditingController(text: '0');
  final _cantCtrl = TextEditingController(text: '1');
  double _disponible = 0;
  bool _cargado = false;

  bool get _esPesable => widget.producto['es_pesable'] == true || widget.producto['es_pesable'] == 1;

  TextEditingController get _campoPrincipal =>
      _esPesable ? _pesoTotalCtrl : _cantCtrl;

  @override
  void initState() {
    super.initState();
    _cargarDisponible();
  }

  @override
  void dispose() {
    _pesoTotalCtrl.dispose();
    _cantCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDisponible() async {
    final repo = ref.read(requisicionesRepoProvider);
    if (repo == null) {
      if (mounted) setState(() => _cargado = true);
      return;
    }
    final disp =
        await repo.getExistencia(widget.producto['id'] as int, widget.origen);
    if (mounted) {
      setState(() {
        _disponible = disp;
        _cargado = true;
      });
    }
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

  void _agregar() {
    final p = widget.producto;
    final nombre = (p['nombre'] as String?) ?? '';
    final id = p['id'] as int;
    double peso = 0;
    RequisicionItem? item;
    final unidadRaw = (p['unidad_medida'] as String?) ?? '';
    final unidad = unidadRaw.isEmpty ? 'uds' : unidadRaw;

    if (_esPesable) {
      final pesoTotal =
          double.tryParse(_pesoTotalCtrl.text.replaceAll(',', '.')) ?? -1;
      if (pesoTotal <= 0) {
        _snack('Peso válido mayor a 0');
        return;
      }
      peso = pesoTotal;
      item = RequisicionItem(
        productoId: id,
        ingrediente: nombre,
        cantidad: peso,
        unidad: unidad,
        peso: peso,
        esPesable: true,
      );
    } else {
      final cant =
          int.tryParse(_cantCtrl.text.replaceAll(',', '').replaceAll(' ', '')) ??
              -1;
      if (cant <= 0) {
        _snack('Número entero mayor a 0');
        return;
      }
      item = RequisicionItem(
        productoId: id,
        ingrediente: nombre,
        cantidad: cant.toDouble(),
        unidad: unidad,
        esPesable: false,
      );
    }

    Navigator.pop(context, CantidadProductoResult(item: item, peso: peso));
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f1) {
        _abrirCalculadora();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _agregar();
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
    final p = widget.producto;
    final nombre = (p['nombre'] as String?) ?? '';
    final unidadRaw = (p['unidad_medida'] as String?) ?? '';
    final unidad = unidadRaw.isEmpty ? 'uds' : unidadRaw;
    final stockColor =
        _disponible > 0 ? Colors.green.shade700 : scheme.error;
    final isMobile = MediaQuery.of(context).size.width < 700;

    Widget stockInfo = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_rounded, size: 16, color: stockColor),
          const SizedBox(width: 5),
          Text(
            'Disponible: ${_disponible.toStringAsFixed(3)} $unidad',
            style: TextStyle(
                fontSize: 12, color: stockColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );

    final campo = _esPesable
        ? TextField(
            controller: _pesoTotalCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Peso Total (kg)',
              border: const OutlineInputBorder(),
              suffixIcon:
                  CalculadoraSuffixIcon(targetController: _pesoTotalCtrl),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _agregar(),
          )
        : TextField(
            controller: _cantCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Cantidad',
              border: const OutlineInputBorder(),
              suffixIcon: CalculadoraSuffixIcon(targetController: _cantCtrl),
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _agregar(),
          );

    return AlertDialog(
      title: Text('Agregar: $nombre'),
      content: Focus(
        onKeyEvent: _onKeyEvent,
        child: SizedBox(
          width: isMobile ? 350 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_cargado) stockInfo,
              const SizedBox(height: 10),
              Text('Unidad: $unidad',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 5),
              campo,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _agregar, child: const Text('Agregar')),
      ],
    );
  }
}
