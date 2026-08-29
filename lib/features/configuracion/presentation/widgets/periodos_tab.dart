import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/periodo.dart';
import '../../data/configuracion_providers.dart';

/// Pestaña de Periodos (porta `usr/views/configuracion/periodos.py`).
class PeriodosTab extends ConsumerStatefulWidget {
  const PeriodosTab({super.key});

  @override
  ConsumerState<PeriodosTab> createState() => _PeriodosTabState();
}

class _PeriodosTabState extends ConsumerState<PeriodosTab> {
  final _periodosAsync = FutureProvider<List<Periodo>>((ref) {
    return ref.read(configuracionRepoProvider)!.getPeriodos();
  });

  bool _aperturando = false;
  bool _recalculando = false;
  bool _forzando = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final periodosAsync = ref.watch(_periodosAsync);
    final periodoActual = _periodoActual();
    const yaAbierto = false; // Se actualizará al cargar

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.calendar_month, color: scheme.onPrimaryContainer, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Periodos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Archive movimientos anteriores a 3 meses por periodo mensual',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                periodosAsync.when(
                  data: (periodos) {
                    final abierto = periodos.any((p) => p.periodo == periodoActual);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Periodo actual: $periodoActual — ${abierto ? 'Abierto' : 'Cerrado'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: abierto ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.lock_open),
                                label: const Text('Aperturar Periodo'),
                                onPressed: (_aperturando || abierto) ? null : _aperturarPeriodo,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Recalcular stock'),
                                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                                onPressed: _recalculando ? null : _recalcularDesdeCero,
                              ),
                            ),
                          ],
                        ),
                        if (abierto) ...[
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.replay),
                            label: const Text('Forzar archivo'),
                            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                            onPressed: _forzando ? null : _forzarArchivo,
                          ),
                        ],
                        const Divider(height: 20),
                        const Text('Historial de Periodos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (periodos.isEmpty)
                          Text('No hay periodos archivados aún', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: periodos.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final p = periodos[i];
                              String fecha = '';
                              try {
                                final d = DateTime.parse(p.fechaApertura).toLocal();
                                fecha = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                              } catch (_) {
                                fecha = p.fechaApertura;
                              }
                              return ListTile(
                                leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                title: Text(p.periodo, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Aperturado: $fecha', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              );
                            },
                          ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e', style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _periodoActual() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _aperturarPeriodo() async {
    setState(() => _aperturando = true);
    try {
      final repo = ref.read(configuracionRepoProvider)!;
      final periodo = _periodoActual();

      if (await repo.periodoExiste(periodo)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('El periodo $periodo ya fue aperturado')));
        return;
      }

      await repo.archivarMovimientos(mesesActivos: 3, mesesRetencion: 7);
      await repo.crearPeriodo(periodo, registradoPor: 'sistema');
      await repo.recalcularExistencias();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Periodo $periodo aperturado')));
        ref.invalidate(_periodosAsync);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _aperturando = false);
    }
  }

  Future<void> _recalcularDesdeCero() async {
    setState(() => _recalculando = true);
    try {
      final repo = ref.read(configuracionRepoProvider)!;
      await repo.clearCheckpoints();
      await repo.recalcularExistencias();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock recalculado desde todos los movimientos')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _recalculando = false);
    }
  }

  Future<void> _forzarArchivo() async {
    setState(() => _forzando = true);
    try {
      final repo = ref.read(configuracionRepoProvider)!;
      await repo.archivarMovimientos(mesesActivos: 3, mesesRetencion: 7);
      await repo.recalcularExistencias();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archivo forzado completado')));
        ref.invalidate(_periodosAsync);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _forzando = false);
    }
  }


}