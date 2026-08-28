import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/models/mensaje_whatsapp.dart';
import 'whatsapp_repository.dart';

final whatsappRepoProvider = Provider<WhatsappRepository?>((ref) {
  final db = ref.watch(supabaseServiceProvider);
  if (db == null) return null;
  final repo = WhatsappRepository(db);
  repo.startRetryTimer();
  ref.onDispose(() => repo.stopRetryTimer());
  return repo;
});

/// Mensajes de la bandeja (los más recientes primero).
final bandejaProvider = FutureProvider.autoDispose<List<MensajeWhatsapp>>(
    (ref) {
  return ref.watch(whatsappRepoProvider)!.getMensajes(limit: 100);
});

/// Pendientes por reintentar (badge/contador).
final whatsappPendientesProvider =
    FutureProvider.autoDispose<int>((ref) {
  return ref.watch(whatsappRepoProvider)!.countPending();
});

/// Estado de conexión del bot (GET /config).
final whatsappStatusProvider = FutureProvider.autoDispose<
    ({bool connected, String? groupId, String? reportGroupId})>((ref) {
  return ref.watch(whatsappRepoProvider)!.getStatus();
});
