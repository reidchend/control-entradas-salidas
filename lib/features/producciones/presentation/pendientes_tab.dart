import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/receta.dart';
import '../../../core/widgets/error_display.dart';
import '../data/producciones_providers.dart';
import '../data/producciones_repository.dart';
import 'dialogs/cancelar_produccion_dialog.dart';
import 'dialogs/descargo_dialog.dart';
import 'dialogs/unir_producciones_dialog.dart';
import 'widgets/pendiente_card.dart';

/// Tab En Producción: producciones pendientes con acciones Descargar/Cancelar.
class PendientesTab extends ConsumerStatefulWidget {
  const PendientesTab({super.key});

  @override
  ConsumerState<PendientesTab> createState() => _PendientesTabState();
}

class _PendientesTabState extends ConsumerState<PendientesTab> {
  Future<List<PendienteCardData>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<PendienteCardData>> _cargar() async {
    final repo = ref.read(produccionesRepoProvider);
    if (repo == null) {
      throw Exception('Supabase no configurado. Verifica la conexion.');
    }
    final pendientes = await repo.getProduccionesPorEstado('pendiente');
    final recetas = await repo.getRecetas();
    final recetaPorId = {for (final r in recetas) r.id: r};

    final datos = <PendienteCardData>[];
    for (final p in pendientes) {
      final receta = recetaPorId[p.recetaId];
      if (receta == null) continue;
      final entradas = (await repo.getDetalles(p.id))
          .where((d) => d.tipo == 'entrada')
          .toList();
      datos.add(PendienteCardData(
        produccion: p,
        receta: receta,
        entradas: entradas,
      ));
    }
    return datos;
  }

  void _refresh() {
    setState(() => _future = _cargar());
  }

  /// Une la producción `produccion` (destino) con otra pendiente de la misma
  /// receta elegida por el usuario (origen).
  Future<void> _unir(ProduccionInfo produccion, Receta receta) async {
    final origenId = await showUnirProduccionesDialog(
      context: context,
      ref: ref,
      produccionActual: produccion,
      receta: receta,
    );
    if (origenId == null || !mounted) return;

    final repo = ref.read(produccionesRepoProvider)!;
    final (ok, err) = await repo.unirProducciones(
        destinoId: produccion.id, origenId: origenId, usuario: 'Sistema');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Producciones unidas: #$origenId se unió a #${produccion.id}'
                : 'No se pudieron unir: $err',
          ),
        ),
      );
      if (ok) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<PendienteCardData>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorDisplay(
            error: snap.error!,
            onRetry: _refresh,
          );
        }
        final datos = snap.data!;
        if (datos.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 48, color: scheme.outline),
                const SizedBox(height: 10),
                Text('Sin producciones pendientes',
                    style: TextStyle(fontSize: 16, color: scheme.outline)),
                const SizedBox(height: 4),
                Text(
                  'Las producciones se crean desde Inventario al hacer una entrada de producción',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: datos.length,
            itemBuilder: (context, i) {
              final d = datos[i];
              return PendienteCard(
                produccion: d.produccion,
                entradas: d.entradas,
                onDescargar: () => showDescargoDialog(
                  context,
                  ref,
                  d.produccion,
                  d.receta,
                  onCompleted: _refresh,
                ),
                onCancelar: () => showCancelarProduccionDialog(
                  context,
                  ref,
                  d.produccion,
                  d.receta,
                  onConfirmed: _refresh,
                ),
                onUnir: () => _unir(d.produccion, d.receta),
              );
            },
          ),
        );
      },
    );
  }
}

/// Datos agrupados para el tab pendientes.
class PendienteCardData {
  const PendienteCardData({
    required this.produccion,
    required this.receta,
    required this.entradas,
  });

  final ProduccionInfo produccion;
  final Receta receta;
  final List<DetalleInfo> entradas;
}
