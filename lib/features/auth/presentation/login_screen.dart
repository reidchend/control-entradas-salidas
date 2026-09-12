import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/updater/auto_update_checker.dart';

/// Pantalla de login / registro (porta `usr/views/login_view.py`).
///
/// El operador se identifica por nombre + PIN (no por device_id): si el
/// nombre ya existe en la BD se pide solo el PIN (login) y se re-vincula el
/// dispositivo actual; si no existe se muestra el flujo de registro. Así una
/// reinstalación no obliga a registrar un usuario nuevo.
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
  bool _existeNombre = false;

  @override
  void initState() {
    super.initState();
    Future(() => _autodetectarOperador());
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Si este dispositivo ya tiene un operador registrado (misma device_id),
  // precarga el nombre para que el login sea solo el PIN. Si el dispositivo
  // es nuevo (reinstalación), sigue el flujo de registro por nombre.
  Future<void> _autodetectarOperador() async {
    try {
      final session = ref.read(sessionProvider.notifier);
      final nombre = await session.nombrePorDeviceId();
      if (mounted && nombre != null && nombre.isNotEmpty) {
        _nombreCtrl.text = nombre;
        if (!_existeNombre) {
          setState(() => _existeNombre = true);
        }
      }
    } catch (_) {
      // Sin conexión: el usuario podrá escribir el nombre manualmente.
    }
  }

  // Determina si el nombre ingresado ya es un operador registrado.
  Future<void> _verificarNombreExistente() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      if (_existeNombre) {
        setState(() => _existeNombre = false);
      }
      return;
    }
    try {
      final session = ref.read(sessionProvider.notifier);
      final existe = await session.existeOperador(nombre);
      if (mounted && existe != _existeNombre) {
        setState(() => _existeNombre = existe);
      }
    } catch (_) {
      // Sin conexión: mantener el estado actual; _submit volverá a decidir.
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      final nombre = _nombreCtrl.text.trim();
      final session = ref.read(sessionProvider.notifier);
      final yaExiste = await session.existeOperador(nombre);
      bool ok = false;
      final esRegistro = !yaExiste;
      if (esRegistro) {
        // Registro
        if (nombre.isEmpty) {
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
          nombre: nombre,
          pin: _pinCtrl.text,
        );
        if (!ok) {
          setState(() => _error = 'No se pudo registrar. Verifica la conexión.');
        }
      } else {
        // Login
        if (nombre.isEmpty) {
          setState(() => _error = 'Ingresa el nombre del operador');
          return;
        }
        if (_pinCtrl.text.length != 4) {
          setState(() => _error = 'El PIN debe tener 4 digitos');
          return;
        }
        ok = await session.verificarPin(
          nombre: nombre,
          pin: _pinCtrl.text,
        );
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
    // Modo según si el nombre ya está registrado (verificado en vivo).
    final esRegistro = !_existeNombre;
    final pinLabel = esRegistro ? 'PIN de 4 dígitos' : 'Ingresa tu PIN';

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
                    esRegistro ? 'Registro de Operador' : 'Bienvenido',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    esRegistro
                        ? 'Configure el operador principal del dispositivo'
                        : 'Ingresa tu PIN para continuar',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del operador',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => _verificarNombreExistente(),
                    onSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinCtrl,
                    decoration: InputDecoration(
                      labelText: pinLabel,
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    onSubmitted: (_) => !esRegistro
                        ? _submit()
                        : FocusScope.of(context).nextFocus(),
                  ),
                  if (esRegistro) const SizedBox(height: 12),
                  if (esRegistro)
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
                        : Text(esRegistro ? 'Registrar' : 'Desbloquear'),
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
  }
}