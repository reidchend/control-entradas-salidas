import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/receta.dart';
import '../data/producciones_providers.dart';
import 'historial_tab.dart';
import 'pendientes_tab.dart';
import 'receta_editor_screen.dart';
import 'recetas_tab.dart';

/// Pantalla de Producciones — porta `producciones/view.py`. Tres pestañas
/// (En Producción, Recetas, Historial) y editor de receta en pantalla
/// completa cuando está abierto.
class ProduccionesScreen extends ConsumerStatefulWidget {
  const ProduccionesScreen({super.key});

  @override
  ConsumerState<ProduccionesScreen> createState() => _ProduccionesScreenState();
}

class _ProduccionesScreenState extends ConsumerState<ProduccionesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// `null` → no editor; receta no nula → edición; [Receta?] inválido
  /// controlado por [_editorAbierto].
  bool _editorAbierto = false;
  Receta? _recetaEditando;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _abrirEditor(Receta? receta) {
    setState(() {
      _editorAbierto = true;
      _recetaEditando = receta;
    });
  }

  void _cerrarEditor() {
    setState(() {
      _editorAbierto = false;
      _recetaEditando = null;
    });
  }

  void _onEditorSaved() {
    _cerrarEditor();
    ref.invalidate(recetasProvider);
    ref.invalidate(pendientesProvider);
    ref.invalidate(historialProduccionesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_editorAbierto) {
      return RecetaEditorScreen(
        key: ValueKey(_recetaEditando?.id ?? 'nueva'),
        receta: _recetaEditando,
        onSaved: _onEditorSaved,
        onCancel: _cerrarEditor,
      );
    }

    return Column(
      children: [
        _buildHeader(),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: scheme.outlineVariant,
          indicatorColor: scheme.primary,
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.pending_actions), text: 'En Producción'),
            Tab(icon: Icon(Icons.description_outlined), text: 'Recetas'),
            Tab(icon: Icon(Icons.history_outlined), text: 'Historial'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const PendientesTab(),
              RecetasTab(onEdit: _abrirEditor),
              const HistorialTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const Spacer(),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('+ Nueva Receta'),
            onPressed: () => _abrirEditor(null),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
