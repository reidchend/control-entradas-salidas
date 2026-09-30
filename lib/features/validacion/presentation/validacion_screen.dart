import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../data/temporales_repository.dart';
import '../data/validacion_providers.dart';
import '../data/validacion_repository.dart';
import 'dialogs/precargar_imagen_dialog.dart';
import 'dialogs/temporales_dialog.dart';
import 'dialogs/validacion_dialog.dart';
import 'widgets/entrada_pendiente_card.dart';
import 'widgets/validacion_empty_state.dart';

/// Pantalla de Validación de Entradas (porta `usr/views/validacion_view.py`,
/// sin el asistente OCR de IA).
///
/// - Banner con el conteo de pendientes.
/// - Búsqueda por nombre de producto.
/// - Selección múltiple + "Validar N entradas" → `ValidacionDialog`.
class ValidacionScreen extends ConsumerStatefulWidget {
  const ValidacionScreen({super.key});

  @override
  ConsumerState<ValidacionScreen> createState() => _ValidacionScreenState();
}

class _ValidacionScreenState extends ConsumerState<ValidacionScreen> {
  final _searchCtrl = TextEditingController();
  final Set<int> _selected = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onValidar() async {
    final session = ref.read(sessionProvider);
    final usuario = session is Authenticated ? session.nombre : 'Sistema';
    final temporalesRepo = ref.read(temporalesRepoProvider);

    // Si hay temporales pre-cargados, el usuario elige uno (o pega una nueva
    // imagen directamente).
    ResultadoValidacion? resultado;
    TemporalData? temporalUsado;
    final temporales = await temporalesRepo.getTemporales();
    if (temporales.isNotEmpty) {
      if (!mounted) return;
      final sel = await showTemporalesDialog(context, temporales);
      if (sel == null || !mounted) return;
      temporalUsado = sel.temporal;
    }
    if (!mounted) return;

    resultado = await showValidacionDialog(
      context,
      selectedEntradas: _selected,
      usuario: usuario,
      temporal: temporalUsado,
    );
    if (resultado == null || !mounted) return;

    // El temporal usado se consume.
    if (temporalUsado?.id != null) {
      try {
        await temporalesRepo.eliminar(temporalUsado!.id!);
      } catch (e) {
        debugPrint('[validacion] eliminar temporal falló: $e');
      }
    }
    if (!mounted) return;

    // Invalidar provider de pendientes para refrescar la lista.
    ref.invalidate(entradasPendientesProvider(_search));
    setState(() => _selected.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${resultado.movimientosCount} entrada(s) validada(s). '
          'Factura ${resultado.facturaId} · ${resultado.usuario}',
        ),
      ),
    );
  }

  Future<void> _onEliminar(
      ValidacionRepository repo, EntradaPendiente entrada) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar entrada'),
        content: Text(
            '¿Eliminar la entrada de "${entrada.nombre}" sin validar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await repo.eliminarEntrada(entrada);
    if (mounted) {
      // Invalidar provider de pendientes para refrescar la lista.
      ref.invalidate(entradasPendientesProvider(_search));
      setState(() => _selected.remove(entrada.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada eliminada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(validacionRepoProvider)!;
    final scheme = Theme.of(context).colorScheme;
    final entradasAsync = ref.watch(entradasPendientesProvider(_search));

    return Column(
      children: [
        _buildHeader(repo, scheme),
        Expanded(
          child: entradasAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Error: $e', style: TextStyle(color: scheme.error)),
            ),
            data: (entradas) {
              if (entradas.isEmpty) {
                return const ValidacionEmptyState();
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entradas.length,
                itemBuilder: (context, i) {
                  final e = entradas[i];
                  return EntradaPendienteCard(
                    entrada: e,
                    selected: _selected.contains(e.id),
                    onToggle: () => setState(() {
                      _selected.contains(e.id)
                          ? _selected.remove(e.id)
                          : _selected.add(e.id);
                    }),
                    onEliminar: () => _onEliminar(repo, e),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ValidacionRepository repo, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                  ),
                  onChanged: (v) {
                    setState(() => _search = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: Text(
                    _selected.isEmpty ? 'Validar' : 'Validar ${_selected.length}'),
                onPressed: _selected.isEmpty ? null : _onValidar,
              ),
              const SizedBox(width: 4),
              Consumer(
                builder: (context, ref, _) {
                  final count =
                      ref.watch(temporalesProvider).valueOrNull?.length ?? 0;
                  return IconButton(
                    icon: count > 0
                        ? Badge(
                            label: Text('$count'),
                            child: const Icon(Icons.photo_library_outlined),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    tooltip: 'Precargar imagen temporal',
                    onPressed: () =>
                        showPrecargarImagenDialog(context),
                  );
                },
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Limpiar selección',
                  onPressed: () => setState(() => _selected.clear()),
                ),
              ],
            ],
          ),
    );
  }
}
