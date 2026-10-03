import 'package:flutter/material.dart';

import '../../../../core/auth/usuarios_repository.dart';
import '../../../../core/models/usuario.dart';

/// Abre el diálogo de alta/edición de usuario. Devuelve `true` si se guardó.
Future<bool?> showUsuarioDialog(
  BuildContext context, {
  required UsuariosRepository repo,
  Usuario? usuario,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UsuarioDialog(repo: repo, usuario: usuario),
  );
}

class UsuarioDialog extends StatefulWidget {
  const UsuarioDialog({super.key, required this.repo, this.usuario});

  final UsuariosRepository repo;
  final Usuario? usuario;

  @override
  State<UsuarioDialog> createState() => _UsuarioDialogState();
}

class _UsuarioDialogState extends State<UsuarioDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _pin;
  late NivelUsuario _nivel;
  late Set<String> _modulos;
  late bool _activo;
  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.usuario == null;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    _nombre = TextEditingController(text: u?.nombre ?? '');
    _pin = TextEditingController();
    _nivel = u?.nivel ?? NivelUsuario.basico;
    _modulos = {...?u?.modulos};
    _activo = u?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final pin = _pin.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (_esNuevo && pin.isEmpty) {
      setState(() => _error = 'El PIN es obligatorio para crear el usuario.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_esNuevo) {
        await widget.repo.crear(
          nombre: nombre,
          pin: pin,
          nivel: _nivel,
          modulos: _modulos,
        );
      } else {
        await widget.repo.actualizar(
          widget.usuario!.id,
          nombre: nombre,
          pin: pin,
          nivel: _nivel,
          activo: _activo,
          modulos: _modulos,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const temas = UsuariosRepository.etiquetasModulo;
    return AlertDialog(
      title: Text(_esNuevo ? 'Nuevo usuario' : 'Editar usuario'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombre,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  border: const OutlineInputBorder(),
                  helperText: _esNuevo ? null : 'Dejar vacío para no cambiarlo',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Nivel', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<NivelUsuario>(
                segments: const [
                  ButtonSegment(value: NivelUsuario.basico, label: Text('Básico')),
                  ButtonSegment(value: NivelUsuario.admin, label: Text('Admin')),
                  ButtonSegment(
                      value: NivelUsuario.desarrollador,
                      label: Text('Desarrollador')),
                ],
                selected: {_nivel},
                onSelectionChanged: (s) => setState(() => _nivel = s.first),
              ),
              const SizedBox(height: 16),
              const Text('Módulos',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              if (_nivel == NivelUsuario.desarrollador)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'El desarrollador accede a todos los módulos.',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              else
                ...[
                  for (final e in temas.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(e.value),
                      value: _modulos.contains(e.key),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _modulos.add(e.key);
                        } else {
                          _modulos.remove(e.key);
                        }
                      }),
                    ),
                ],
              if (!_esNuevo)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  subtitle: const Text('Si está inactivo no puede ingresar'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}
