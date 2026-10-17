import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Selección de ítems a separar: índice en la lista original + cantidad.
typedef ItemSeparado = ({int index, int cantidad});

/// Diálogo para elegir qué productos (y cuántas unidades de cada uno) se
/// mueven a otra casilla. Devuelve `null` si se cancela.
Future<List<ItemSeparado>?> showSepararItemsDialog(
  BuildContext context, {
  required List<ComandaItem> items,
}) {
  return showDialog<List<ItemSeparado>>(
    context: context,
    builder: (ctx) => _SepararItemsDialog(items: items),
  );
}

class _SepararItemsDialog extends StatefulWidget {
  const _SepararItemsDialog({required this.items});
  final List<ComandaItem> items;

  @override
  State<_SepararItemsDialog> createState() => _SepararItemsDialogState();
}

class _SepararItemsDialogState extends State<_SepararItemsDialog> {
  final _sel = <int>{};
  final _cant = <int, int>{};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.items.length; i++) {
      _cant[i] = widget.items[i].cantidad;
    }
  }

  int get _total => _sel.fold(
      0, (s, i) => s + widget.items[i].precio * (_cant[i] ?? 1));

  void _toggle(int i, bool? on) {
    setState(() {
      if (on == true) {
        _sel.add(i);
        _cant[i] = widget.items[i].cantidad;
      } else {
        _sel.remove(i);
      }
    });
  }

  void _cantidad(int i, int delta) {
    final max = widget.items[i].cantidad;
    setState(() {
      final v = ((_cant[i] ?? 1) + delta).clamp(1, max).toInt();
      _cant[i] = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Separar productos'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marque los productos que pasarán a otra casilla.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (_, i) => _fila(i),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Text('${_sel.length} seleccionado${_sel.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('\$${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _sel.isEmpty
              ? null
              : () => Navigator.pop(context, [
                    for (final i in _sel) (index: i, cantidad: _cant[i] ?? 1),
                  ]),
          icon: const Icon(Icons.call_split),
          label: const Text('Continuar'),
        ),
      ],
    );
  }

  Widget _fila(int i) {
    final item = widget.items[i];
    final marcado = _sel.contains(i);
    return CheckboxListTile(
      dense: true,
      value: marcado,
      onChanged: (v) => _toggle(i, v),
      title: Text(
        item.cuenta > 1 ? '${item.nombre}  ·  Cliente ${item.cuenta}' : item.nombre,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      subtitle: Text('\$${item.precio.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 11)),
      secondary: item.cantidad > 1
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: marcado ? () => _cantidad(i, -1) : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                ),
                Text('${_cant[i] ?? 1}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: marcado ? () => _cantidad(i, 1) : null,
                  icon: const Icon(Icons.add_circle_outline,
                      size: 18, color: Color(0xFF4CAF50)),
                ),
              ],
            )
          : null,
    );
  }
}
