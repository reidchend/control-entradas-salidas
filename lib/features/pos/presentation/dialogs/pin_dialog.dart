import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../data/pos_session.dart';

/// Diálogo de PIN (4 dígitos) para cajeros protegidos. Port de
/// `POSLoginView._show_pin_dialog` / `_verify_pin_and_login` (login.py).
///
/// Si se indica [sesionId], el usuario se une a ese turno; si no, se une al
/// turno abierto (o lo abre si es la PC principal). Devuelve el resultado de
/// `iniciarSesion` o `null` si se canceló.
Future<SesionLoginResult?> showPinDialog(
  BuildContext context,
  PosUsuario usuario, {
  int? sesionId,
}) async {
  return await showDialog<SesionLoginResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PinDialog(usuario: usuario, sesionId: sesionId),
      );
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog({required this.usuario, this.sesionId});
  final PosUsuario usuario;
  final int? sesionId;

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
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
    final SesionLoginResult result;
    try {
      result = await ref
          .read(posSessionProvider.notifier)
          .iniciarSesion(widget.usuario, pin: pin, sesionId: widget.sesionId);
    } catch (e) {
      // Un fallo de conexión/consulta no debe dejar el diálogo mudo.
      if (!mounted) return;
      setState(() => _error = 'Error al iniciar sesión: $e');
      return;
    }
    if (!mounted) return;
    if (result == SesionLoginResult.pinIncorrecto) {
      setState(() {
        _error = 'PIN incorrecto';
        _ctrl.clear();
      });
    } else if (result == SesionLoginResult.soloPcPrincipal ||
        result == SesionLoginResult.sinTurno) {
      setState(() {
        _error = 'No hay turno abierto. Debe abrirse desde la PC principal.';
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
