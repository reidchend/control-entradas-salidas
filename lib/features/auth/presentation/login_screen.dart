import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/device_id_service.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/updater/auto_update_checker.dart';

/// Pantalla de login / registro (porta `usr/views/login_view.py`).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nombreCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String _error = '';
  bool _loading = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Determina si este dispositivo tiene operador registrado.
  Future<bool> _hayOperador() async {
    try {
      final db = ref.read(supabaseServiceProvider);
      if (db == null) return false;
      final deviceId = await DeviceIdService.instance.id;
      final rows = await db.client
          .from('dispositivo_usuario')
          .select('id')
          .eq('device_id', deviceId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      final hayOperador = await _hayOperador();
      final session = ref.read(sessionProvider.notifier);
      bool ok = false;
      if (!hayOperador) {
        // Registro
        if (_nombreCtrl.text.trim().isEmpty) {
          setState(() => _error = 'Ingresa el nombre del operador');
          return;
        }
        if (_pinCtrl.text.length != 4) {
          setState(() => _error = 'El PIN debe tener 4 digitos');
          return;
        }
        if (_pinCtrl.text != _confirmCtrl.text) {
          setState(() => _error = 'Los PIN no coinciden');
          return;
        }
        ok = await session.registrarOperador(
          nombre: _nombreCtrl.text.trim(),
          pin: _pinCtrl.text,
        );
        if (!ok) {
          setState(() => _error = 'No se pudo registrar. Verifica la conexion a Supabase.');
        }
      } else {
        // Login
        if (_pinCtrl.text.length != 4) {
          setState(() => _error = 'El PIN debe tener 4 digitos');
          return;
        }
        ok = await session.verificarPin(_pinCtrl.text);
        if (!ok) setState(() => _error = 'PIN incorrecto');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hayOperador(),
      builder: (context, snapshot) {
        final hayOperador = snapshot.data ?? false;
        final isRegistro = !hayOperador;
        final pinLabel = isRegistro ? 'PIN de 4 dígitos' : 'Ingresa tu PIN';

        return Scaffold(
          body: Stack(
            children: [
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 56, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        isRegistro ? 'Registro de Operador' : 'Bienvenido',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRegistro
                            ? 'Configure el operador principal del dispositivo'
                            : 'Ingresa tu PIN para continuar',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      if (isRegistro)
                        TextField(
                          controller: _nombreCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre del operador',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                        ),
                      if (isRegistro) const SizedBox(height: 12),
                      TextField(
                        controller: _pinCtrl,
                        decoration: InputDecoration(
                          labelText: pinLabel,
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: true,
                        onSubmitted: (_) => !isRegistro
                            ? _submit()
                            : FocusScope.of(context).nextFocus(),
                      ),
                      if (isRegistro) const SizedBox(height: 12),
                      if (isRegistro)
                        TextField(
                          controller: _confirmCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar PIN',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          obscureText: true,
                          onSubmitted: (_) => _submit(),
                        ),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _error));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error copiado al portapapeles'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.error),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SelectableText(
                                    _error,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Icon(Icons.copy,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.error),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isRegistro ? 'Registrar' : 'Desbloquear'),
                      ),
                    ],
                  ),
                ),
              ),
              // Verificar actualizaciones antes del login (Windows/Android).
              const Align(alignment: Alignment.topRight, child: AutoUpdateChecker()),
            ],
          ),
        );
      },
    );
  }
}