import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/postgres_guard.dart';
import '../../../../core/models/usuario.dart';
import '../../../configuracion/presentation/dialogs/db_config_dialog.dart';
import '../../../configuracion/presentation/widgets/bd_no_disponible.dart';
import '../../../pos/presentation/widgets/usuario_card.dart';
import '../../data/hostel_session.dart';
import '../../data/hosteleria_providers.dart';
import '../dialogs/hostel_pin_dialog.dart';

/// Login de Hostelería: grid de recepcionistas + PIN (estilo POS, sin caja).
class HostelLoginView extends ConsumerStatefulWidget {
  const HostelLoginView({super.key});

  @override
  ConsumerState<HostelLoginView> createState() => _HostelLoginViewState();
}

class _HostelLoginViewState extends ConsumerState<HostelLoginView> {
  int? _selectedId;

  Future<void> _login(Usuario u) async {
    if (u.pinHash != null && u.pinHash!.isNotEmpty) {
      final result = await showHostelPinDialog(context, u);
      if (result != HostelLoginResult.ok) {
        if (mounted) ref.invalidate(hostelUsuariosProvider);
      }
      return;
    }
    await ref.read(hostelSessionProvider.notifier).iniciarSesion(u);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usuarios = ref.watch(hostelUsuariosProvider);
    final estadoBd = ref.watch(estadoBdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lycoris Hosteleria'),
        actions: [
          IconButton(
            tooltip: 'Configurar conexión',
            onPressed: () => showDbConfigDialog(context),
            icon: const Icon(Icons.settings_ethernet),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hotel_outlined, size: 40, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('Lycoris Hosteleria',
                      style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Seleccione el recepcionista',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              usuarios.when(
                loading: () => estadoBd == EstadoBd.conectando
                    ? const Center(child: CircularProgressIndicator())
                    : const Center(child: BdNoDisponible()),
                error: (e, _) => const Center(child: BdNoDisponible()),
                data: (lista) => lista.isEmpty
                    ? _sinRecepcionistas(scheme)
                    : Column(
                        children: [
                          for (final u in lista) ...[
                            UsuarioCard(
                              usuario: u,
                              selected: u.id == _selectedId,
                              onTap: () {
                                setState(() => _selectedId = u.id);
                                _login(u);
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sinRecepcionistas(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.person_off_outlined, size: 48),
            const SizedBox(height: 8),
            const Text('No hay recepcionistas con acceso',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Asigne el módulo Hostelería a un usuario desde la '
              'administración de usuarios (Configuración).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
