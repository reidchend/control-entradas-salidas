import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/modal_sizing.dart';

/// Diálogo de calculadora simple (operaciones + - * /, decimales).
/// Devuelve el valor calculado al cerrar con "Aceptar".
Future<double?> showCalculadoraDialog(BuildContext context, {double? initialValue}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _CalculadoraDialog(initialValue: initialValue ?? 0),
  );
}

class _CalculadoraDialog extends ConsumerStatefulWidget {
  const _CalculadoraDialog({required this.initialValue});
  final double initialValue;

  @override
  ConsumerState<_CalculadoraDialog> createState() => _CalculadoraDialogState();
}

class _CalculadoraDialogState extends ConsumerState<_CalculadoraDialog> {
  String _display = '';
  String _expression = '';
  double _operand1 = 0;
  String? _operator;
  bool _newEntry = true;

  @override
  void initState() {
    super.initState();
    _display = _fmt(widget.initialValue);
    if (widget.initialValue != 0) {
      _expression = _fmt(widget.initialValue);
    }
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  void _onDigit(String d) {
    setState(() {
      if (_newEntry || _display == '0') {
        final newDigit = d == '.' ? '0.' : d;
        _display = newDigit;
        if (_operator != null) {
          _expression = '${_fmt(_operand1)} $_operator $newDigit';
        } else {
          _expression = newDigit;
        }
        _newEntry = false;
      } else if (d == '.' && _display.contains('.')) {
        return;
      } else {
        _display += d;
        if (_operator != null) {
          _expression = '${_fmt(_operand1)} $_operator $_display';
        } else {
          _expression = _display;
        }
      }
    });
  }

  void _onOperator(String op) {
    final val = double.tryParse(_display) ?? 0;
    if (_operator != null && !_newEntry) {
      _operand1 = _compute(_operand1, val, _operator!);
      _display = _fmt(_operand1);
    } else {
      _operand1 = val;
    }
    _operator = op;
    _expression = '${_fmt(_operand1)} $op';
    _newEntry = true;
  }

  void _onEquals() {
    if (_operator == null) return;
    final val = double.tryParse(_display) ?? 0;
    final res = _compute(_operand1, val, _operator!);
    setState(() {
      _expression = '${_fmt(_operand1)} $_operator ${_fmt(val)} =';
      _display = _fmt(res);
      _operator = null;
      _operand1 = res;
      _newEntry = true;
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _expression = '';
      _operand1 = 0;
      _operator = null;
      _newEntry = true;
    });
  }

  void _onBackspace() {
    setState(() {
      if (_display.length <= 1 || (_display.length == 2 && _display.startsWith('-'))) {
        _display = '0';
      } else {
        _display = _display.substring(0, _display.length - 1);
      }
    });
  }

  double _compute(double a, double b, String op) {
    switch (op) {
      case '+': return a + b;
      case '-': return a - b;
      case '×': return a * b;
      case '÷': return b != 0 ? a / b : a;
      default: return b;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('Calculadora'),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: SizedBox(
          width: modalContentWidth(context, factor: 0.9, max: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_expression.isNotEmpty)
                      Text(
                        _expression,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _display,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Teclado
              _buildKeypad(scheme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final val = double.tryParse(_display);
            Navigator.pop(context, val);
          },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }

  /// Soporte de teclado físico: dígitos, operadores, Enter (=), Backspace,
  /// Esc (cancelar). Se usa el mismo patrón Focus(onKeyEvent) del diálogo
  /// de movimientos.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final lk = event.logicalKey;

    if (lk == LogicalKeyboardKey.enter ||
        lk == LogicalKeyboardKey.numpadEnter) {
      _onEquals();
      return KeyEventResult.handled;
    }
    if (lk == LogicalKeyboardKey.backspace) {
      _onBackspace();
      return KeyEventResult.handled;
    }
    if (lk == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (lk == LogicalKeyboardKey.numpadAdd) return _tecla('+');
    if (lk == LogicalKeyboardKey.numpadSubtract) return _tecla('-');
    if (lk == LogicalKeyboardKey.numpadMultiply) return _tecla('×');
    if (lk == LogicalKeyboardKey.numpadDivide) return _tecla('÷');
    if (lk == LogicalKeyboardKey.numpadDecimal) return _tecla('.');

    final ch = event.character;
    if (ch == null || ch.isEmpty) return KeyEventResult.ignored;
    final c = ch[0];
    if ('0123456789.'.contains(c)) return _tecla(c);
    if (c == '+' || c == '-') return _tecla(c);
    if (c == '*') return _tecla('×');
    if (c == '/') return _tecla('÷');
    if (c == '%') return _tecla('%');
    if (c == '=') {
      _onEquals();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _tecla(String k) {
    _handleKey(k);
    return KeyEventResult.handled;
  }

  Widget _buildKeypad(ColorScheme scheme) {
    const keys = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      ['00', '0', '.', '='],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: row.map((k) => Expanded(
              child: _KeyButton(
                label: k,
                onTap: () => _handleKey(k),
                isOperator: ['÷', '×', '-', '+', '='].contains(k),
                isSpecial: ['C', '⌫', '%'].contains(k),
              ),
            )).toList(),
          ),
        );
      }).toList(),
    );
  }

  void _handleKey(String k) {
    switch (k) {
      case 'C': _onClear(); break;
      case '⌫': _onBackspace(); break;
      case '=': _onEquals(); break;
      case '%':
        final v = double.tryParse(_display) ?? 0;
        setState(() => _display = _fmt(v / 100));
        break;
      case '÷': case '×': case '-': case '+':
        _onOperator(k);
        break;
      default: _onDigit(k);
    }
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.isOperator = false,
    this.isSpecial = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool isOperator;
  final bool isSpecial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg, fg;
    if (isOperator) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (isSpecial) {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurface;
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}