import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/activo_tipo.dart';
import '../data/activos_categoria.dart';
import '../data/activos_filtro.dart';
import '../data/activos_providers.dart';
import '../data/activos_repository.dart';
import 'activo_form_screen.dart';
import 'dialogs/activos_categoria_dialog.dart';
import 'dialogs/activos_excel_dialog.dart';
import 'dialogs/tipo_dialog.dart';
import 'widgets/activos_categorias_grid.dart';
import 'widgets/activos_filtrados_panel.dart';
import 'widgets/activos_tipos_grid.dart';
import 'widgets/activos_valores_grid.dart';
import 'widgets/tipos_panel.dart';
import 'widgets/unidades_panel.dart';

/// Pantalla de Inventario de Activos (catálogo de tipos + unidades):
/// - Raíz: grilla de tipos (vista principal) agrupada por categoría, con
///   selector de dimensión (Categorías, Ubicación, Grupo, Modelo, Estado).
/// - Tipo → el detalle de sus unidades físicas (por ubicación).
/// - Categoría → el nivel de tipos del catálogo (con su conteo de unidades).
/// El selector por valor (ubicación/grupo/modelo/estado) muestra las
/// unidades que cumplen esa dimensión.
class ActivosScreen extends ConsumerStatefulWidget {
  const ActivosScreen({super.key});

  @override
  ConsumerState<ActivosScreen> createState() => _ActivosScreenState();
}

/// Metadatos de una dimensión agrupable de activos.
class _DimInfo {
  const _DimInfo(
      this.columna, this.plural, this.singular, this.icono, this.color);

  final String columna;
  final String plural;
  final String singular;
  final IconData icono;
  final Color color;
}

const _dims = <String, _DimInfo>{
  'ubicacion': _DimInfo('ubicacion', 'Ubicaciones', 'ubicación',
      Icons.place_outlined, Color(0xFF00897B)),
  'grupo': _DimInfo(
      'grupo', 'Grupos', 'grupo', Icons.folder_outlined, Color(0xFF7B1FA2)),
  'modelo': _DimInfo(
      'modelo', 'Modelos', 'modelo', Icons.memory_outlined, Color(0xFF1565C0)),
  'estado': _DimInfo(
      'estado', 'Estados', 'estado', Icons.circle_outlined, Color(0xFF455A64)),
};

class _ActivosScreenState extends ConsumerState<ActivosScreen> {
  String _dim = 'tipo';
  ActivosCategoria? _categoria;
  ActivoTipo? _tipo;
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
    final enRaiz = _categoria == null && _tipo == null && _valor == null;

    return Scaffold(
      floatingActionButton: enRaiz
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
    final tipo = _tipo;
    if (tipo != null) return _tipoUnidades(repo, colors, tipo);
    if (_categoria != null) return _categoriaPanel(repo, colors);
    final valor = _valor;
    if (valor != null) return _valorPanel(repo, colors, valor);
    return _raiz(repo, colors);
  }

  Widget _backHeader(ColorScheme colors, String titulo, VoidCallback onBack) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver',
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _volverRaiz() {
    setState(() {
      _categoria = null;
      _tipo = null;
      _valor = null;
      _search = '';
      _searchCtrl.clear();
    });
  }

  Widget _categoriaPanel(ActivosRepository repo, ColorScheme colors) {
    return Column(
      children: [
        _backHeader(colors, _categoria!.nombre, _volverRaiz),
        Expanded(
          child: TiposPanel(
            repo: repo,
            categoria: _categoria!,
            searchTerm: _search,
            onOpenTipo: (t) => setState(() {
              _tipo = t;
              _valor = null;
              _tick++;
              _search = '';
              _searchCtrl.clear();
            }),
          ),
        ),
      ],
    );
  }

  Widget _tipoUnidades(
      ActivosRepository repo, ColorScheme colors, ActivoTipo tipo) {
    return Column(
      children: [
        _backHeader(colors, tipo.nombre, () => setState(() => _tipo = null)),
        Expanded(
          child: UnidadesPanel(
            repo: repo,
            tipo: tipo,
            searchTerm: _search,
          ),
        ),
      ],
    );
  }

  Widget _valorPanel(ActivosRepository repo, ColorScheme colors, String valor) {
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
              value: 'tipo',
              label: Text('Tipos'),
              icon: Icon(Icons.dashboard_customize_outlined, size: 18),
            ),
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
    // Sin key con `_tick`: cada grid se recarga solo tras su propio cambio, y
    // poner la key acá dispararía una segunda consulta idéntica.
    if (_dim == 'tipo') {
      return ActivosTiposGrid(
        repo: repo,
        searchTerm: _search,
        onOpenTipo: (t) => setState(() {
          _tipo = t;
          _categoria = null;
          _valor = null;
          _tick++;
          _search = '';
          _searchCtrl.clear();
        }),
      );
    }
    if (_dim == 'categoria') {
      return ActivosCategoriasGrid(
        repo: repo,
        onSelect: (c) => setState(() {
          _categoria = c;
          _tipo = null;
          _valor = null;
          _tick++;
          _search = '';
          _searchCtrl.clear();
        }),
        onCreate: () => _crearCategoria(repo),
        // El grid solo se ve en la raíz, así que acá `_categoria` es siempre
        // null: los avisos son para que el encabezado y el filtro no se queden
        // apuntando a algo que ya no está.
        onEditado: () => setState(() => _tick++),
        onEliminado: (_) => setState(() {
          _categoria = null;
          _tick++;
        }),
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
      onCrear: () => _crearValor(repo, d.columna, d.singular),
      onRenombrar: (antes, despues) => setState(() {
        // Si el valor renombrado era el que estaba abierto, el filtro viejo ya
        // no matchea nada y la pantalla quedaría vacía sin avisar.
        if (_valor == antes) _valor = despues;
        _tick++;
      }),
      // El estado no se "quita" de las unidades (siempre tienen uno); se
      // desactiva en su catálogo.
      onQuitar: d.columna != 'estado'
          ? (valor) => setState(() {
                if (_valor == valor) _valor = null;
                _tick++;
              })
          : null,
    );
  }

  Widget _buildHeader(ActivosRepository repo, ColorScheme colors) {
    final hint = _categoria != null
        ? 'Buscar en ${_categoria!.nombre}...'
        : _tipo != null
            ? 'Buscar unidad...'
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
          if (_categoria == null && _tipo == null && _valor == null) ...[
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

  Future<List<ActivoTipo>> _tipos(ActivosRepository repo) async {
    final maps = await repo.getTipos();
    return [for (final m in maps) m['tipo'] as ActivoTipo];
  }

  Future<void> _crearActivo(ActivosRepository repo) async {
    final tipos = await _tipos(repo);
    final categorias = await repo.getCategorias();
    final ubicaciones = await repo.getUbicaciones();
    final estados = await repo.getEstados();
    if (!mounted) return;
    await showActivoFormScreen(
      context,
      tipos: tipos,
      categorias: categorias,
      estados: estados,
      onGuardar: (a) => repo.createActivo(a),
      onCrearTipo: (t) => repo.createTipo(t),
      onCrearEstado: (n) => repo.createEstado(n),
      onExisteUnidad: (t, u) => repo.existeUnidad(t, u),
      ubicacionesSugeridas: ubicaciones,
    );
    if (mounted) setState(() {});
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

  /// Crea un valor nuevo (ubicación/grupo/modelo/estado) y entra al detalle.
  ///
  /// Para un estado se da de alta en el catálogo y se entra a la vista de la
  /// dimensión; para las demás dimensiones se abre el alta de una unidad con
  /// ese valor prefijado.
  Future<void> _crearValor(
      ActivosRepository repo, String columna, String singular) async {
    final nombre = await _pedirNuevoValor(singular);
    if (nombre == null) return;
    if (columna == 'estado') {
      try {
        final creado = await repo.createEstado(nombre);
        if (!mounted) return;
        setState(() {
          _valor = creado;
          _categoria = null;
          _tipo = null;
          _tick++;
        });
      } catch (e) {
        _snack('Error al crear estado: $e');
      }
      return;
    }
    await _agregarAValor(repo, columna, nombre);
  }

  /// Agrega una unidad prefijando [columna]=[valor].
  /// - ubicación/estado: nueva unidad (elige o crea el tipo) con ese valor.
  /// - grupo/modelo: nuevo tipo con ese valor prefijado, y entra a su detalle.
  Future<void> _agregarAValor(
      ActivosRepository repo, String columna, String valor) async {
    if (columna == 'ubicacion' || columna == 'estado') {
      final esUbicacion = columna == 'ubicacion';
      final tipos = await _tipos(repo);
      final categorias = await repo.getCategorias();
      final ubicaciones = await repo.getUbicaciones();
      final estados = await repo.getEstados();
      if (!mounted) return;
      await showActivoFormScreen(
        context,
        tipos: tipos,
        categorias: categorias,
        estados: estados,
        onGuardar: (a) => repo.createActivo(a),
        onCrearTipo: (t) => repo.createTipo(t),
        onCrearEstado: (n) => repo.createEstado(n),
        onExisteUnidad: (t, u) => repo.existeUnidad(t, u),
        ubicacionPreset: esUbicacion ? valor : null,
        estadoPreset: esUbicacion ? null : valor,
        ubicacionesSugeridas: ubicaciones,
      );
      if (!mounted) return;
      setState(() {
        _categoria = null;
        _tipo = null;
        _valor = valor;
        _search = '';
        _searchCtrl.clear();
        _tick++;
      });
      return;
    }

    final categorias = await repo.getCategorias();
    final grupos = await repo.getGrupos();
    final modelos = await repo.getModelos();
    if (!mounted) return;
    final tipo = await showTipoDialog(
      context,
      categorias: categorias,
      grupos: grupos,
      modelos: modelos,
      grupoPreset: columna == 'grupo' ? valor : null,
      modeloPreset: columna == 'modelo' ? valor : null,
    );
    if (tipo == null) return;
    try {
      final id = await repo.createTipo(tipo);
      if (mounted) {
        setState(() {
          _tipo = ActivoTipo(
            id: id,
            nombre: tipo.nombre,
            grupo: tipo.grupo,
            modelo: tipo.modelo,
            categoriaId: tipo.categoriaId,
          );
          _categoria = null;
          _valor = null;
          _tick++;
          _search = '';
          _searchCtrl.clear();
        });
      }
    } catch (e) {
      _snack('Error al crear tipo: $e');
    }
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
