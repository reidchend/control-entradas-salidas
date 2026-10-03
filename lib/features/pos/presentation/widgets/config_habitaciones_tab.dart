import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/pos_models.dart';
import '../../data/pos_providers.dart';
import '../dialogs/habitacion_config_dialog.dart';

/// Pestaña de habitaciones POS (port de `ConfigPOSView` sección HABITACIONES):
/// listado con número/piso/tipo y CRUD completo.
class ConfigHabitacionesTab extends ConsumerStatefulWidget {
  const ConfigHabitacionesTab({super.key});

  @override
  ConsumerState<ConfigHabitacionesTab> createState() =>
      _ConfigHabitacionesTabState();
}

class _ConfigHabitacionesTabState
    extends ConsumerState<ConfigHabitacionesTab> {
  List<Habitacion> _habs = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final habs = await ref.read(posRepoProvider)!.getHabitaciones();
    if (!mounted) return;
    setState(() {
      _habs = habs;
      _cargando = false;
    });
  }

  Future<void> _nuevaHabitacion() async {
    if (await showHabitacionConfigDialog(context)) {
      ref.invalidate(habitacionesProvider);
      await _cargar();
    }
  }

  Future<void> _editarHabitacion(Habitacion h) async {
    if (await showHabitacionConfigDialog(context, habitacion: h)) {
      ref.invalidate(habitacionesProvider);
      await _cargar();
    }
  }

  Future<void> _eliminarHabitacion(Habitacion h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar habitación'),
        content: Text("¿Eliminar la habitación '${h.numero}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(posRepoProvider)!.eliminarHabitacion(h.id);
    ref.invalidate(habitacionesProvider);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: _nuevaHabitacion,
                icon: const Icon(Icons.add),
                label: const Text('Nueva habitación'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _habs.isEmpty
                  ? Center(
                      child: Text('No hay habitaciones registradas',
                          style: TextStyle(color: scheme.outline)),
                    )
                  : ListView(
                      children: [
                        for (final h in _habs)
                          _HabitacionConfigCard(
                            habitacion: h,
                            onEdit: () => _editarHabitacion(h),
                            onDelete: () => _eliminarHabitacion(h),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}

class _HabitacionConfigCard extends StatelessWidget {
  const _HabitacionConfigCard({
    required this.habitacion,
    required this.onEdit,
    required this.onDelete,
  });

  final Habitacion habitacion;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = [habitacion.piso, habitacion.tipo]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFF26A69A),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(habitacion.numero,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Habitación ${habitacion.numero}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(sub.isEmpty ? 'Sin datos' : sub,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: const Icon(Icons.edit, color: Color(0xFFBB86FC)),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
            ),
          ],
        ),
      ),
    );
  }
}
