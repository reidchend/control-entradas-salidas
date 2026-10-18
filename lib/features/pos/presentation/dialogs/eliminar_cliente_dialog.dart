import 'package:flutter/material.dart';

/// Resultado de eliminar un cliente de la comanda:
/// - `moverA: <cliente>` → sus productos pasan a ese cliente.
/// - `vaciar: true` → sus productos se eliminan de la comanda.
typedef EliminacionCliente = ({bool vaciar, int? moverA});

/// Diálogo para eliminar un cliente (sub-cuenta) de la comanda. Si el
/// cliente tiene productos, el mesonero elige moverlos a otro cliente o
/// eliminarlos. Devuelve la acción elegida, o `null` si se cancela.
Future<EliminacionCliente?> showEliminarClienteDialog(
  BuildContext context, {
  required String etiqueta,
  required int cantidadItems,
  required List<({int cliente, String etiqueta})> destinos,
}) {
  return showDialog<EliminacionCliente>(
    context: context,
    builder: (ctx) => _EliminarClienteDialog(
      etiqueta: etiqueta,
      cantidadItems: cantidadItems,
      destinos: destinos,
    ),
  );
}

class _EliminarClienteDialog extends StatefulWidget {
  const _EliminarClienteDialog({
    required this.etiqueta,
    required this.cantidadItems,
    required this.destinos,
  });
  final String etiqueta;
  final int cantidadItems;
  final List<({int cliente, String etiqueta})> destinos;

  @override
  State<_EliminarClienteDialog> createState() => _EliminarClienteDialogState();
}

class _EliminarClienteDialogState extends State<_EliminarClienteDialog> {
  /// null = mover (a `destinos.first` por defecto); true = vaciar.
  bool _vaciar = false;
  int? _destino;

  @override
  void initState() {
    super.initState();
    if (widget.destinos.isNotEmpty) _destino = widget.destinos.first.cliente;
  }

  @override
  Widget build(BuildContext context) {
    final conItems = widget.cantidadItems > 0;
    return AlertDialog(
      title: Text('Eliminar ${widget.etiqueta}'),
      content: SizedBox(
        width: 400,
        child: conItems
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.etiqueta} tiene ${widget.cantidadItems} '
                    'producto${widget.cantidadItems == 1 ? '' : 's'} en la '
                    'comanda. ¿Qué se hace con ${widget.cantidadItems == 1 ? 'él' : 'ellos'}?',
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _vaciar,
                    dense: true,
                    title: Text(
                      _destino != null
                          ? 'Mover a ${widget.destinos
                              .firstWhere((d) => d.cliente == _destino)
                              .etiqueta}'
                          : 'Mover a otro cliente',
                    ),
                    subtitle: widget.destinos.length > 1
                        ? DropdownButton<int>(
                            value: _destino,
                            isExpanded: true,
                            items: [
                              for (final d in widget.destinos)
                                DropdownMenuItem(
                                    value: d.cliente, child: Text(d.etiqueta)),
                            ],
                            onChanged: (v) => setState(() => _destino = v),
                          )
                        : null,
                    onChanged: (_) => setState(() => _vaciar = false),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _vaciar,
                    dense: true,
                    title: const Text('Eliminar sus productos'),
                    subtitle: const Text('No se pueden recuperar'),
                    onChanged: (_) => setState(() => _vaciar = true),
                  ),
                ],
              )
            : Text('¿Eliminar ${widget.etiqueta} de la comanda?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350)),
          onPressed: conItems && !_vaciar && _destino == null
              ? null
              : () => Navigator.pop(
                  context,
                  (vaciar: _vaciar, moverA: _vaciar ? null : _destino),
                ),
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}
