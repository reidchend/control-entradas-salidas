import 'package:flutter/material.dart';

/// Diálogo para renombrar un valor de dimensión (ubicación, modelo, grupo).
///
/// Devuelve el nombre nuevo, o `null` si se canceló. Si el nombre escrito ya
/// existe como otro valor, avisa que las dos quedan juntas en vez de dejarlo
/// descubrir después: casi siempre es justo lo que se quiere para corregir
/// `hab01` contra `Hab01`.
Future<String?> showRenombrarValorDialog(
  BuildContext context, {
  required String singular,
  required String valor,
  required int afectados,
  required List<String> existentes,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RenombrarValorDialog(
      singular: singular,
      valor: valor,
      afectados: afectados,
      existentes: existentes,
    ),
  );
}

class _RenombrarValorDialog extends StatefulWidget {
  const _RenombrarValorDialog({
    required this.singular,
    required this.valor,
    required this.afectados,
    required this.existentes,
  });

  final String singular;
  final String valor;
  final int afectados;
  final List<String> existentes;

  @override
  State<_RenombrarValorDialog> createState() => _RenombrarValorDialogState();
}

class _RenombrarValorDialogState extends State<_RenombrarValorDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.valor);
  String? _error;

  @override
  void initState() {
    super.initState();
    // Todo el texto viene seleccionado: la intención casi siempre es reemplazarlo
    // entero, no corregir una letra en el medio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// ¿El texto escrito ya existe como OTRO valor?
  ///
  /// El propio valor se excluye por comparación exacta, no sin mayúsculas: el
  /// caso interesante es renombrar `hab01` a `Hab01`, donde `Hab01` ya existe y
  /// las dos se van a juntar. Comparar sin distinguir mayúsculas lo tomaría por
  /// "el mismo nombre, no cambia nada" y perdería el aviso justo cuando importa.
  bool _chocaConOtro(String texto) {
    final t = texto.trim();
    if (t.isEmpty || t == widget.valor.trim()) return false;
    return widget.existentes
        .any((e) => e.trim().toLowerCase() == t.toLowerCase());
  }

  /// Texto de ayuda bajo el campo: dice cuántas unidades quedan con el nombre
  /// nuevo y avisa si el nombre escrito ya existe como otro valor.
  String get _ayuda {
    final n = widget.afectados;
    final unidades = n == 1 ? '1 unidad' : '$n unidades';
    if (_chocaConOtro(_ctrl.text)) {
      return 'Ya existe ese valor: las $unidades de las dos quedan juntas.';
    }
    return 'Se renombra en $unidades.';
  }

  void _aceptar() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'El nombre no puede quedar vacío');
      return;
    }
    // Solo se corta si el nombre es idéntico, también en mayúsculas: cambiar
    // `hab01` a `Hab01` sí es un cambio, y es el que junta los dos valores.
    if (v == widget.valor.trim()) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Renombrar ${widget.singular}'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _aceptar(),
        decoration: InputDecoration(
          labelText: 'Nombre de la ${widget.singular}',
          errorText: _error,
          helperText: _ayuda,
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _aceptar,
          child: const Text('Renombrar'),
        ),
      ],
    );
  }
}
