import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/data/postgres_providers.dart';
import '../../../core/models/mensaje_whatsapp.dart';
import '../data/whatsapp_providers.dart';
import 'widgets/mensaje_card.dart';

/// Bandeja de WhatsApp — porta `usr/views/whatsapp_bandeja_view.py`.
/// Muestra la cola local de mensajes (`whatsapp_queue`), permite reintentar,
/// eliminar, probar el bot y procesa reintentos en background cada 15s.
class BandejaScreen extends ConsumerStatefulWidget {
  const BandejaScreen({super.key});

  @override
  ConsumerState<BandejaScreen> createState() => _BandejaScreenState();
}

class _BandejaScreenState extends ConsumerState<BandejaScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final repo = ref.read(whatsappRepoProvider)!;
        await repo.reintentarTodos();
        _refrescar();
      } catch (_) {}
    });
    _refrescar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _procesarReintentos() async {
    try {
      final repo = ref.read(whatsappRepoProvider)!;
      final pendientes = await repo.countPending();
      if (pendientes == 0) return;
      await repo.reintentarTodos();
      _refrescar();
    } catch (_) {}
  }

  void _refrescar() {
    ref.invalidate(bandejaProvider);
    ref.invalidate(whatsappPendientesProvider);
  }

  String _nombreUsuario() {
    final s = ref.read(sessionProvider);
    return s is Authenticated ? s.nombre : 'Sistema';
  }

  Future<void> _probarBot() async {
    final repo = ref.read(whatsappRepoProvider)!;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await repo.probarBot(_nombreUsuario());
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Mensaje de prueba enviado'
            : 'No se pudo enviar. Revisa que el bot esté conectado.'),
      ),
    );
    _refrescar();
  }

  Future<void> _reintentarTodos() async {
    try {
      final repo = ref.read(whatsappRepoProvider)!;
      final enviados = await repo.reintentarTodos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$enviados mensaje(s) enviado(s)')),
        );
      }
      _refrescar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reintentar: $e')),
        );
      }
    }
  }

  Future<void> _reintentarUno(int id) async {
    try {
      final repo = ref.read(whatsappRepoProvider)!;
      final ok = await repo.reintentarUno(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Mensaje reenviado' : 'Error al reenviar')),
        );
      }
      _refrescar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reenviar: $e')),
        );
      }
    }
  }

  Future<void> _eliminar(int id) async {
    try {
      final repo = ref.read(whatsappRepoProvider)!;
      await repo.eliminar(id);
      _refrescar();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildHeader(scheme),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<MensajeWhatsapp>>(
            future: ref.watch(bandejaProvider.future),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final mensajes = snap.data ?? const [];
              if (mensajes.isEmpty) {
                return const _Vacio();
              }
              final total = mensajes.length;
              final enviados =
                  mensajes.where((m) => m.estado == 'sent').length;
              final fallidos =
                  mensajes.where((m) => m.estado == 'failed').length;
              final pendientes =
                  mensajes.where((m) => m.estado == 'pending').length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      'Total: $total  |  Pendientes: $pendientes  |  '
                      'Enviados: $enviados  |  Fallidos: $fallidos',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        final repo = ref.read(whatsappRepoProvider)!;
                        await repo.reintentarTodos();
                        _refrescar();
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: mensajes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => MensajeCard(
                          msg: mensajes[i],
                          onRetry: () => _reintentarUno(mensajes[i].id),
                          onDelete: () => _eliminar(mensajes[i].id),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: FutureBuilder<int>(
        future: ref.watch(whatsappPendientesProvider.future),
        builder: (context, snap) {
          final pendientes = snap.data ?? 0;
          return Row(
            children: [
              Expanded(
                child: Text(
                  pendientes > 0
                      ? '$pendientes pendiente(s) por enviar'
                      : 'Cola de mensajes al día',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: pendientes > 0 ? Colors.orange : Colors.green,
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.sensors, size: 16),
                label: const Text('Probar Bot'),
                onPressed: _probarBot,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.replay),
                color: scheme.primary,
                tooltip: 'Reintentar todos',
                onPressed: _reintentarTodos,
              ),
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 60, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No hay mensajes en la bandeja',
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}