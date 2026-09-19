import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Diálogo de calculadora optimizado (estilo nativo Android).
/// Usa bottom sheet modal sin chrome de AlertDialog, botones con feedback
/// háptico y visual inmediato, y rebuild mínimo.
Future<double?> showCalculadoraDialog(BuildContext context, {double? initialValue}) {
  return showGeneralDialog<double>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Calculadora',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (ctx, anim, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
    pageBuilder: (_, __, ___) => _CalculadoraSheet(initialValue: initialValue ?? 0),
  );
}

class _CalculadoraSheet extends ConsumerStatefulWidget {
  const _CalculadoraSheet({required this.initialValue});
  final double initialValue;

  @override
  ConsumerState<_CalculadoraSheet> createState() => _CalculadoraSheetState();
}

class _CalculadoraSheetState extends ConsumerState<_CalculadoraSheet> {
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

  void _haptic() => HapticFeedback.lightImpact();

  void _onDigit(String d) {
    _haptic();
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
    _haptic();
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
    _haptic();
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
    _haptic();
    setState(() {
      _display = '0';
      _expression = '';
      _operand1 = 0;
      _operator = null;
      _newEntry = true;
    });
  }

  void _onBackspace() {
    _haptic();
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
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_expression.isNotEmpty)
                        Text(
                          _expression,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 18,
                            fontFamily: 'monospace',
                            color: scheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        _display,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace',
                          color: scheme.onSurface,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                // Keypad
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomPadding + 8),
                      child: _buildKeypad(scheme),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      mainAxisSize: MainAxisSize.min,
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            children: row.map((k) => Expanded(
              child: _FastKeyButton(
                label: k,
                onTap: () => _handleKey(k),
                isOperator: ['÷', '×', '-', '+', '='].contains(k),
                isSpecial: ['C', '⌫', '%'].contains(k),
                scheme: scheme,
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

class _FastKeyButton extends StatefulWidget {
  const _FastKeyButton({
    required this.label,
    required this.onTap,
    required this.isOperator,
    required this.isSpecial,
    required this.scheme,
  });
  final String label;
  final VoidCallback onTap;
  final bool isOperator;
  final bool isSpecial;
  final ColorScheme scheme;

  @override
  State<_FastKeyButton> createState() => _FastKeyButtonState();
}

class _FastKeyButtonState extends State<_FastKeyButton> {
  bool _pressed = false;

  Color get _bgColor {
    if (widget.isOperator) return widget.scheme.primaryContainer;
    if (widget.isSpecial) return widget.scheme.secondaryContainer;
    return widget.scheme.surfaceContainerHighest;
  }

  Color get _fgColor {
    if (widget.isOperator) return widget.scheme.onPrimaryContainer;
    if (widget.isSpecial) return widget.scheme.onSecondaryContainer;
    return widget.scheme.onSurface;
  }

  Color get _pressedBg {
    if (widget.isOperator) {
      return widget.scheme.primaryContainer.withValues(alpha: 0.7);
    }
    if (widget.isSpecial) {
      return widget.scheme.secondaryContainer.withValues(alpha: 0.7);
    }
    return widget.scheme.surfaceContainerHighest.withValues(alpha: 0.7);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          height: 64,
          decoration: BoxDecoration(
            color: _pressed ? _pressedBg : _bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: _fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}