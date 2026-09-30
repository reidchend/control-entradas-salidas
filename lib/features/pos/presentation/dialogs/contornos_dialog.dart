import 'package:flutter/material.dart';

import '../../../../core/models/pos_models.dart';
import '../../../../core/utils/modal_sizing.dart';

/// Contorno seleccionado con su cantidad de porciones: 1 = simple,
/// 2 = doble ("doble tostón"), 3 = triple.
typedef ContornoSeleccion = ({PosPlato plato, int cantidad});

/// Diálogo de selección de contornos (port de `_show_contornos_dialog`):
/// checkboxes de contornos activos, máximo 2 por plato, y cada uno con
/// stepper de porciones (simple/doble/triple). Devuelve la lista de contornos
/// seleccionados con su cantidad.
Future<List<ContornoSeleccion>> showContornosDialog(
  BuildContext context,
  PosPlato plato,
  List<PosPlato> contornos,
) async {
  return await showDialog<List<ContornoSeleccion>>(
        context: context,
        builder: (_) => _ContornosDialog(plato: plato, contornos: contornos),
      ) ??
      const [];
}

class _ContornosDialog extends StatefulWidget {
  const _ContornosDialog({required this.plato, required this.contornos});
  final PosPlato plato;
  final List<PosPlato> contornos;

  @override
  State<_ContornosDialog> createState() => _ContornosDialogState();
}

class _ContornosDialogState extends State<_ContornosDialog> {
  static const _maxSel = 2;
  static const _maxPorcion = 3;

  /// contorno id -> cantidad de porciones (ausente = no seleccionado).
  final _cantidades = <int, int>{};
  String? _error;

  void _toggle(PosPlato c) {
    setState(() {
      if (_cantidades.containsKey(c.id)) {
        _cantidades.remove(c.id);
      } else {
        _cantidades[c.id] = 1;
      }
      _error = null;
    });
  }

  void _cambiarPorcion(int id, int delta) {
    if (!_cantidades.containsKey(id)) return;
    setState(() {
      final nuevo = (_cantidades[id]! + delta).clamp(1, _maxPorcion);
      _cantidades[id] = nuevo;
    });
  }

  void _confirmar() {
    if (_cantidades.isEmpty) {
      setState(() => _error = 'Seleccione al menos un contorno');
      return;
    }
    if (_cantidades.length > _maxSel) {
      setState(() => _error = 'Máximo $_maxSel contornos');
      return;
    }
    Navigator.pop(context, [
      for (final c in widget.contornos)
        if (_cantidades.containsKey(c.id))
          (plato: c, cantidad: _cantidades[c.id]!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Contornos para ${widget.plato.nombre}'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seleccione hasta $_maxSel contornos. Si quiere porción doble '
                'de uno, súbala con el +.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(fontSize: 11, color: scheme.error),
                ),
              const SizedBox(height: 8),
              for (final c in widget.contornos) _buildFila(c, scheme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const <ContornoSeleccion>[]),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Agregar'),
        ),
      ],
    );
  }

  Widget _buildFila(PosPlato c, ColorScheme scheme) {
    final cantidad = _cantidades[c.id];
    final seleccionado = cantidad != null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: seleccionado,
        onChanged: (_) => _toggle(c),
      ),
      title: Text(c.nombre),
      subtitle: Text(
        '\$${c.precioVenta.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: seleccionado
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: cantidad > 1
                      ? () => _cambiarPorcion(c.id, -1)
                      : null,
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    cantidad > 1 ? '${cantidad}x' : '1',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: cantidad < _maxPorcion
                      ? () => _cambiarPorcion(c.id, 1)
                      : null,
                  tooltip: 'Porción doble',
                ),
              ],
            )
          : null,
    );
  }
}