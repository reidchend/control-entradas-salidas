import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/usuario.dart';
import '../../data/hostel_session.dart';

/// Diálogo de PIN del login de Hostelería.
Future<HostelLoginResult?> showHostelPinDialog(
    BuildContext context, Usuario usuario) async {
  return await showDialog<HostelLoginResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _HostelPinDialog(usuario: usuario),
  );
}

class _HostelPinDialog extends ConsumerStatefulWidget {
  const _HostelPinDialog({required this.usuario});
  final Usuario usuario;

  @override
  ConsumerState<_HostelPinDialog> createState() => _HostelPinDialogState();
}

class _HostelPinDialogState extends ConsumerState<_HostelPinDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final pin = _ctrl.text.trim();
    if (pin.isEmpty) return;
    final result = await ref
        .read(hostelSessionProvider.notifier)
        .iniciarSesion(widget.usuario, pin: pin);
    if (!mounted) return;
    if (result == HostelLoginResult.pinIncorrecto) {
      setState(() {
        _error = 'PIN incorrecto';
        _ctrl.clear();
      });
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('PIN de ${widget.usuario.nombre}'),
      content: Focus(
        autofocus: true,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'PIN',
            counterText: '',
            errorText: _error,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => _entrar(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _entrar,
          child: const Text('Entrar'),
        ),
      ],
    );
  }
}
