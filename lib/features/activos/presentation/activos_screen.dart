import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/activo.dart';
import '../data/activos_categoria.dart';
import '../data/activos_filtro.dart';
import '../data/activos_providers.dart';
import '../data/activos_repository.dart';
import 'dialogs/activo_dialog.dart';
import 'dialogs/activos_categoria_dialog.dart';
import 'dialogs/activos_excel_dialog.dart';
import 'widgets/activos_categorias_grid.dart';
import 'widgets/activos_filtrados_panel.dart';
import 'widgets/activos_panel.dart';
import 'widgets/activos_valores_grid.dart';

/// Pantalla de Inventario de Activos:
/// - Raíz: grid de categorías + selector de dimensión (Ubicación, Grupo,
///   Modelo, Estado) que muestra un grid con los valores de esa dimensión.
/// - Click en un valor → panel de activos que lo usan (con back).
/// - Se pueden crear categorías nuevas y valores nuevos (ubicación, grupo,
///   modelo) entrando directamente a agregar el primer activo.
class ActivosScreen extends ConsumerStatefulWidget {
  const ActivosScreen({super.key});

  @override
  ConsumerState<ActivosScreen> createState() => _ActivosScreenState();
}

/// Metadatos de una dimensión agrupable de activos.
class _DimInfo {
  const _DimInfo(this.columna, this.plural, this.singular, this.icono,
      this.color, {this.editable = true});

  final String columna;
  final String plural;
  final String singular;
  final IconData icono;
  final Color color;
  final bool editable;
}

const _dims = <String, _DimInfo>{
  'ubicacion': _DimInfo(
      'ubicacion', 'Ubicaciones', 'ubicación', Icons.place_outlined,
      Color(0xFF00897B)),
  'grupo': _DimInfo(
      'grupo', 'Grupos', 'grupo', Icons.folder_outlined, Color(0xFF7B1FA2)),
  'modelo': _DimInfo(
      'modelo', 'Modelos', 'modelo', Icons.memory_outlined, Color(0xFF1565C0)),
  'estado': _DimInfo(
      'estado', 'Estados', 'estado', Icons.circle_outlined,
      Color(0xFF455A64),
      editable: false),
};

class _ActivosScreenState extends ConsumerState<ActivosScreen> {
  String _dim = 'categoria';
  ActivosCategoria? _categoria;
  String? _valor;
  int _tick = 0;
  String _search = '';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(activosRepoProvider)!;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: _categoria == null && _valor == null
          ? FloatingActionButton.extended(
              onPressed: () => _crearActivo(repo),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo activo'),
            )
          : null,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onScreenKey,
        child: Column(
          children: [
            _buildHeader(repo, colors),
            Expanded(child: _buildCuerpo(repo, colors)),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onScreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildCuerpo(ActivosRepository repo, ColorScheme colors) {
    if (_categoria != null) {
      return _categoriaPanel(repo, colors);
    }
    final valor = _valor;
    if (valor != null) {
      return _valorPanel(repo, colors, valor);
    }
    return _raiz(repo, colors);
  }

  Widget _categoriaPanel(ActivosRepository repo, ColorScheme colors) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver',
                onPressed: () => setState(() {
                  _categoria = null;
                  _valor = null;
                  _search = '';
                  _searchCtrl.clear();
                }),
              ),
              Expanded(
                child: Text(
                  _categoria!.nombre,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ActivosPanel(
            repo: repo,
            categoria: _categoria!,
            searchTerm: _search,
          ),
        ),
      ],
    );
  }

  Widget _valorPanel(
      ActivosRepository repo, ColorScheme colors, String valor) {
    final dim = _dims[_dim]!;
    final sing = dim.singular[0].toUpperCase() + dim.singular.substring(1);
    return ActivosFiltradosPanel(
      key: ValueKey('$_dim/$valor/$_tick'),
      repo: repo,
      filtro: ActivosFiltro.deValor(_dim, valor),
      titulo: '$sing · $valor',
      searchTerm: _search,
      onAgregar: () => _agregarAValor(repo, _dim, valor),
      onLimpiar: () => setState(() {
        _valor = null;
        _search = '';
        _searchCtrl.clear();
      }),
    );
  }

  Widget _raiz(ActivosRepository repo, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelector(colors),
        Expanded(child: _buildGrid(repo, colors)),
      ],
    );
  }

  Widget _buildSelector(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'categoria',
              label: Text('Categorías'),
              icon: Icon(Icons.category_outlined, size: 18),
            ),
            ButtonSegment(
              value: 'ubicacion',
              label: Text('Ubicaciones'),
              icon: Icon(Icons.place_outlined, size: 18),
            ),
            ButtonSegment(
              value: 'grupo',
              label: Text('Grupos'),
              icon: Icon(Icons.folder_outlined, size: 18),
            ),
            ButtonSegment(
              value: 'modelo',
              label: Text('Modelos'),
              icon: Icon(Icons.memory_outlined, size: 18),
            ),
            ButtonSegment(
              value: 'estado',
              label: Text('Estados'),
              icon: Icon(Icons.circle_outlined, size: 18),
            ),
          ],
          selected: {_dim},
          showSelectedIcon: false,
          onSelectionChanged: (sel) => setState(() => _dim = sel.first),
        ),
      ),
    );
  }

  Widget _buildGrid(ActivosRepository repo, ColorScheme colors) {
    if (_dim == 'categoria') {
      return ActivosCategoriasGrid(
        repo: repo,
        onSelect: (c) => setState(() {
          _categoria = c;
          _valor = null;
          _tick++;
          _search = '';
          _searchCtrl.clear();
        }),
        onCreate: () => _crearCategoria(repo),
      );
    }
    final d = _dims[_dim]!;
    return ActivosValoresGrid(
      repo: repo,
      columna: d.columna,
      singular: d.singular,
      icono: d.icono,
      color: d.color,
      onSelect: (v) => setState(() {
        _valor = v;
        _tick++;
        _search = '';
        _searchCtrl.clear();
      }),
      onCrear: d.editable ? () => _crearValor(repo, d.columna, d.singular) : null,
    );
  }

  Widget _buildHeader(ActivosRepository repo, ColorScheme colors) {
    final hint = _categoria != null
        ? 'Buscar en ${_categoria!.nombre}...'
        : _valor != null
            ? 'Buscar activos...'
            : 'Buscar activo... (F1)';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_categoria == null && _valor == null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Exportar a Excel',
              onPressed: () => showActivosExcelDialog(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _crearActivo(ActivosRepository repo) async {
    final categorias = await repo.getCategorias();
    final grupos = await repo.getGrupos();
    final ubicaciones = await repo.getUbicaciones();
    final modelos = await repo.getModelos();
    if (!mounted) return;
    final nuevo = await showActivoDialog(context,
        categorias: categorias,
        grupos: grupos,
        ubicaciones: ubicaciones,
        modelos: modelos);
    if (nuevo == null) return;
    try {
      await repo.createActivo(nuevo);
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Error al crear activo: $e');
    }
  }

  Future<void> _crearCategoria(ActivosRepository repo) async {
    final nueva = await showActivosCategoriaDialog(context);
    if (nueva == null) return;
    try {
      final id = await repo.createCategoria(nueva.nombre, color: nueva.color);
      setState(() {});
      if (mounted) {
        // Entra directo a la categoría recién creada.
        _categoria = ActivosCategoria(
          id: id,
          nombre: nueva.nombre,
          color: nueva.color,
        );
      }
    } catch (e) {
      _snack('Error al crear categoría: $e');
    }
  }

  /// Crea un valor nuevo (ubicación/grupo/modelo) y entra con el primer
  /// activo ya prefijado a ese valor para agregarlo de inmediato.
  Future<void> _crearValor(
      ActivosRepository repo, String columna, String singular) async {
    final nombre = await _pedirNuevoValor(singular);
    if (nombre == null) return;
    await _agregarAValor(repo, columna, nombre);
  }

  /// Abre el diálogo de activo con [columna]=[valor] prefijado y, al guardar,
  /// entra a la vista del valor.
  Future<void> _agregarAValor(ActivosRepository repo, String columna,
      String valor) async {
    final categorias = await repo.getCategorias();
    final grupos = await repo.getGrupos();
    final ubicaciones = await repo.getUbicaciones();
    final modelos = await repo.getModelos();
    if (!mounted) return;
    final plantilla = _activoParaValor(columna, valor);
    final nuevo = await showActivoDialog(context,
        activo: plantilla,
        categorias: categorias,
        grupos: grupos,
        ubicaciones: ubicaciones,
        modelos: modelos);
    if (nuevo == null) return;
    try {
      await repo.createActivo(nuevo);
      if (mounted) {
        setState(() {
          _categoria = null;
          _valor = valor;
          _tick++;
        });
      }
    } catch (e) {
      _snack('Error al crear activo: $e');
    }
  }

  Activo _activoParaValor(String columna, String valor) {
    switch (columna) {
      case 'ubicacion':
        return Activo(id: 0, nombre: '', ubicacion: valor);
      case 'grupo':
        return Activo(id: 0, nombre: '', grupo: valor);
      case 'modelo':
        return Activo(id: 0, nombre: '', modelo: valor);
    }
    return const Activo(id: 0, nombre: '');
  }

  Future<String?> _pedirNuevoValor(String singular) async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nueva $singular'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nombre de la $singular',
            hintText: 'Ej: Oficina 2',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return nombre;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}