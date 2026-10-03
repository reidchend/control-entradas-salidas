import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/usuarios_providers.dart';
import '../../../../core/auth/usuarios_repository.dart';
import '../../../../core/models/usuario.dart';
import '../../data/usuarios_admin_providers.dart';
import '../dialogs/usuario_dialog.dart';
import '../dialogs/usuario_dispositivos_dialog.dart';

/// Administración del directorio central de usuarios. Solo visible para
/// usuarios con nivel admin o desarrollador (lo controla ConfiguracionScreen).
class UsuariosTab extends ConsumerStatefulWidget {
  const UsuariosTab({super.key});

  @override
  ConsumerState<UsuariosTab> createState() => _UsuariosTabState();
}

class _UsuariosTabState extends ConsumerState<UsuariosTab> {
  String _filtro = '';

  Future<void> _nuevo(UsuariosRepository repo) async {
    final ok = await showUsuarioDialog(context, repo: repo);
    if (ok == true) ref.invalidate(usuariosAdminProvider);
  }

  Future<void> _editar(UsuariosRepository repo, Usuario u) async {
    final ok = await showUsuarioDialog(context, repo: repo, usuario: u);
    if (ok == true) ref.invalidate(usuariosAdminProvider);
  }

  Future<void> _eliminar(UsuariosRepository repo, Usuario u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar a "${u.nombre}"? Esta acción no se puede '
            'deshacer (se quitan sus módulos y equipos).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.eliminar(u.id);
    ref.invalidate(usuariosAdminProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Usuario ${u.nombre} eliminado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(usuariosRepoProvider);
    final async = ref.watch(usuariosAdminProvider);

    if (repo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por nombre',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _nuevo(repo),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Nuevo usuario'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error al cargar usuarios: $e')),
            data: (usuarios) {
              final lista = _filtro.isEmpty
                  ? usuarios
                  : usuarios
                      .where((u) => u.nombre.toLowerCase().contains(_filtro))
                      .toList();
              if (lista.isEmpty) {
                return const Center(child: Text('Sin usuarios.'));
              }
              return ListView.separated(
                itemCount: lista.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _UsuarioTile(
                  usuario: lista[i],
                  onEditar: () => _editar(repo, lista[i]),
                  onEliminar: () => _eliminar(repo, lista[i]),
                  onDispositivos: () => showUsuarioDispositivosDialog(
                    context,
                    repo: repo,
                    usuario: lista[i],
                  ),
                  onActivo: (v) async {
                    await repo.actualizar(lista[i].id, activo: v);
                    ref.invalidate(usuariosAdminProvider);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UsuarioTile extends StatelessWidget {
  const _UsuarioTile({
    required this.usuario,
    required this.onEditar,
    required this.onEliminar,
    required this.onDispositivos,
    required this.onActivo,
  });

  final Usuario usuario;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final VoidCallback onDispositivos;
  final ValueChanged<bool> onActivo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const etiquetas = UsuariosRepository.etiquetasModulo;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(usuario.nombre.characters.first.toUpperCase()),
      ),
      title: Row(
        children: [
          Flexible(child: Text(usuario.nombre)),
          const SizedBox(width: 8),
          _chip(scheme, usuario.nivel.label),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: usuario.esDesarrollador
              ? [_chip(scheme, 'Todos los módulos')]
              : [
                  for (final m in usuario.modulos)
                    _chip(scheme, etiquetas[m] ?? m),
                ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: usuario.activo,
            onChanged: onActivo,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'editar' => onEditar(),
              'equipos' => onDispositivos(),
              'eliminar' => onEliminar(),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'editar', child: Text('Editar')),
              PopupMenuItem(value: 'equipos', child: Text('Equipos')),
              PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme scheme, String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSecondaryContainer,
          ),
        ),
      );
}
