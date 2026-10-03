import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/usuarios_repository.dart';
import '../../../../core/models/usuario.dart';
import '../../data/usuarios_admin_providers.dart';

Future<void> showUsuarioDispositivosDialog(
  BuildContext context, {
  required UsuariosRepository repo,
  required Usuario usuario,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        UsuarioDispositivosDialog(repo: repo, usuario: usuario),
  );
}

class UsuarioDispositivosDialog extends ConsumerWidget {
  const UsuarioDispositivosDialog({
    super.key,
    required this.repo,
    required this.usuario,
  });

  final UsuariosRepository repo;
  final Usuario usuario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dispositivosUsuarioProvider(usuario.id));
    return AlertDialog(
      title: Text('Equipos de ${usuario.nombre}'),
      content: SizedBox(
        width: 420,
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error al cargar equipos: $e'),
          data: (equipos) {
            if (equipos.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Sin equipos vinculados.'),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: equipos.length,
              itemBuilder: (_, i) {
                final d = equipos[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(d.deviceId),
                  subtitle: Text(d.configuradoEn == null
                      ? 'Sin fecha'
                      : 'Desde ${_fecha(d.configuradoEn!)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Desvincular',
                    onPressed: () async {
                      await repo.desvincularDeUsuario(usuario.id, d.deviceId);
                      ref.invalidate(dispositivosUsuarioProvider(usuario.id));
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
