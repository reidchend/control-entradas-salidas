import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/cantidades.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../data/validacion_repository.dart';

/// Diálogo para dividir una entrada pendiente en dos partes, de forma que cada
/// una pueda validarse con una factura distinta.
///
/// Devuelve `true` si se dividió correctamente, `null` si se canceló.
Future<bool?> mostrarDividirEntradaDialog(
  BuildContext context, {
  required ValidacionRepository repo,
  required EntradaPendiente entrada,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _DividirEntradaDialog(repo: repo, entrada: entrada),
  );
}

class _DividirEntradaDialog extends StatefulWidget {
  const _DividirEntradaDialog({required this.repo, required this.entrada});

  final ValidacionRepository repo;
  final EntradaPendiente entrada;

  @override
  State<_DividirEntradaDialog> createState() => _DividirEntradaDialogState();
}

class _DividirEntradaDialogState extends State<_DividirEntradaDialog> {
  late final TextEditingController _ctrl;
  bool _guardando = false;
  String? _error;

  bool get _usarPeso =>
      widget.entrada.esPesable && widget.entrada.pesoTotal > 0;

  double get _total =>
      _usarPeso ? widget.entrada.pesoTotal : widget.entrada.cantidad;

  String get _unidadTexto {
    if (_usarPeso) return 'kg';
    final u = widget.entrada.unidad.trim();
    return u.isEmpty ? 'und' : u;
  }

  double get _parte1 {
    final v = _ctrl.text.trim().replaceAll(',', '.');
    return double.tryParse(v) ?? 0;
  }

  double get _parte2 => _total - _parte1;

  bool get _valido => _parte1 > 0 && _parte2 > 0.000001;

  @override
  void initState() {
    super.initState();
    // Sugerencia inicial: mitad (útil para 400 -> 200 y 200).
    final mitad = _total / 2;
    _ctrl = TextEditingController(text: formatearCantidad(mitad));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dividir() async {
    if (!_valido || _guardando) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.repo.dividirEntrada(
        movimientoId: widget.entrada.id,
        cantidadPrimeraParte: _parte1,
        usarPeso: _usarPeso,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e is StateError ? e.message : 'No se pudo dividir: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.entrada;

    return AlertDialog(
      title: const Text('Dividir entrada'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              e.nombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Total recibido: ${formatearCantidad(_total)} $_unidadTexto',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Cantidad de la primera parte ($_unidadTexto)',
                helperText:
                    'La parte restante se creará como otra entrada pendiente.',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _dividir(),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parte 1: ${formatearCantidad(_parte1 > 0 ? _parte1 : 0)} $_unidadTexto',
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Parte 2: ${formatearCantidad(_parte2 > 0 ? _parte2 : 0)} $_unidadTexto',
                      style: TextStyle(
                        color: _valido ? scheme.onSurface : scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_valido && _ctrl.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Ingresa una cantidad mayor a 0 y menor a ${formatearCantidad(_total)} $_unidadTexto.',
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _valido && !_guardando ? _dividir : null,
          icon: _guardando
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.call_split, size: 18),
          label: const Text('Dividir'),
        ),
      ],
    );
  }
}
