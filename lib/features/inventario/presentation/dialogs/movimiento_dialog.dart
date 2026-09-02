import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:control_entradas_salidas/core/auth/session_controller.dart';
import 'package:control_entradas_salidas/core/models/producto.dart';
import 'package:control_entradas_salidas/core/models/receta.dart';
import 'package:control_entradas_salidas/core/models/existencia.dart';
import 'package:control_entradas_salidas/features/calculadora/presentation/calculadora.dart';
import 'package:control_entradas_salidas/features/inventario/data/inventario_providers.dart';
import 'package:control_entradas_salidas/features/producciones/data/producciones_providers.dart';
import 'package:control_entradas_salidas/features/producciones/data/producciones_repository.dart';

/// Diálogo para registrar movimiento (entrada/salida/ajuste) con soporte pesable.
Future<void> showMovimientoDialog(BuildContext context, WidgetRef ref, Producto p) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MovimientoDialog(producto: p),
  );
}

class _MovimientoDialog extends ConsumerStatefulWidget {
  const _MovimientoDialog({required this.producto});

  final Producto producto;

  @override
  ConsumerState<_MovimientoDialog> createState() => _MovimientoDialogState();
}

class _MovimientoDialogState extends ConsumerState<_MovimientoDialog> {
  late final bool _esProductoProduccion;

  String _tipo = 'entrada';
  String _almacen = 'principal';
  List<String> _almacenes = ['principal'];
  int? _recetaId;
  int? _produccionId;

  final _cantCtrl = TextEditingController(text: '1');
  final _pesoTotalCtrl = TextEditingController();

  final _cantFocus = FocusNode();
  final _pesoTotalFocus = FocusNode();

  bool _registrando = false;

  List<Existencia>? _existencias;
  List<Receta> _recetasQueProducen = [];

  Producto get _producto => widget.producto;
  bool get _esPesable => _producto.esPesable;
  bool get _esProduccion => _esProductoProduccion && _tipo == 'entrada';

  @override
  void initState() {
    super.initState();
    _esProductoProduccion = _producto.tipo.toLowerCase().contains('producci');
    _cargarExistencias();
    if (_esProductoProduccion) _cargarRecetas();
  }

  Future<void> _cargarExistencias() async {
    final repo = ref.read(inventarioRepoProvider)!;
    final existencias = await repo.getExistenciasByProducto(_producto.id);
    final almacenes = existencias.map((e) => e.almacen).toSet().toList();
    if (!almacenes.contains('principal')) almacenes.add('principal');
    var almacen = _producto.almacenPredeterminado;
    if (!almacenes.contains(almacen)) almacen = almacenes.first;
    if (!mounted) return;
    setState(() {
      _existencias = existencias;
      _almacenes = almacenes;
      _almacen = almacen;
    });
  }

  Future<void> _cargarRecetas() async {
    final prodRepo = ref.read(produccionesRepoProvider)!;
    final all = await prodRepo.getRecetas();
    final porFinal = all.where((r) => r.productoFinalId == _producto.id);
    final componentes = await prodRepo.getAllComponentes();
    final recetaIds = componentes
        .where((c) =>
            c.productoId == _producto.id &&
            c.tipoComponente.toUpperCase() == 'RESULTADO')
        .map((c) => c.recetaId)
        .toSet();
    final porResultado = all.where((r) => recetaIds.contains(r.id));

    final porId = <int, Receta>{};
    for (final r in [...porFinal, ...porResultado]) {
      porId[r.id] = r;
    }
    if (!mounted) return;
    setState(() {
      _recetasQueProducen = porId.values.toList();
    });
  }

  Receta? get _recetaSeleccionada {
    if (!_esProduccion || _recetasQueProducen.isEmpty) return null;
    if (_recetasQueProducen.length == 1) return _recetasQueProducen.first;
    for (final r in _recetasQueProducen) {
      if (r.id == _recetaId) return r;
    }
    return null;
  }

  Future<void> _registrar() async {
    if (_registrando) return;
    setState(() => _registrando = true);
    try {
      await _doRegistrar();
    } catch (e, st) {
      debugPrint('Error al registrar: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _doRegistrar() async {
    final almacenSel = _almacen.trim().isEmpty ? 'principal' : _almacen.trim();
    final session = ref.read(sessionProvider);
    final usuario = session is Authenticated ? session.nombre : 'Sistema';

    double cantidad;
    double pesoTotal;
    if (_esPesable) {
      final peso =
          double.tryParse(_pesoTotalCtrl.text.replaceAll(',', '.')) ?? 0;
      if (peso <= 0) {
        _mostrarError('Peso total mayor a 0');
        return;
      }
      cantidad = peso;
      pesoTotal = peso;
    } else {
      final cant = double.tryParse(_cantCtrl.text.replaceAll(',', '.')) ?? 0;
      if (cant <= 0) {
        _mostrarError('Cantidad mayor a 0');
        return;
      }
      cantidad = cant;
      pesoTotal = 0;
    }

    final repo = ref.read(inventarioRepoProvider)!;

    if (_esProduccion) {
      final receta = _recetaSeleccionada;
      if (receta == null) {
        _mostrarError(
            'Este producto es de producción pero no tiene una receta asociada. '
            'Créala primero en Producciones > Recetas.');
        return;
      }
      final prodRepo = ref.read(produccionesRepoProvider)!;
      final res = await prodRepo.registrarProduccionPendienteRaw(
        productoId: _producto.id,
        esPesable: _esPesable,
        unidadMedida: _producto.unidadMedida,
        receta: receta,
        cantidad: _esPesable ? pesoTotal : cantidad,
        pesoTotal: pesoTotal,
        almacen: almacenSel,
        produccionId: _produccionId,
        usuario: usuario,
      );
      if (!mounted) return;
      if (res.movimientoId == null) {
        _mostrarError('No se pudo registrar la entrada de producción');
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada de producción registrada')),
      );
      return;
    }

    final ok = await repo.registrarMovimiento(
      productoId: _producto.id,
      tipo: _tipo,
      cantidad: cantidad,
      pesoTotal: pesoTotal,
      almacen: almacenSel,
      registradoPor: usuario,
      esPesable: _esPesable,
      unidadMedida: _producto.unidadMedida,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock insuficiente')),
      );
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Movimiento registrado')),
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _cantCtrl.dispose();
    _pesoTotalCtrl.dispose();
    _cantFocus.dispose();
    _pesoTotalFocus.dispose();
    super.dispose();
  }

  TextEditingController? get _campoFocalizado {
    if (_pesoTotalFocus.hasFocus) return _pesoTotalCtrl;
    if (_cantFocus.hasFocus) return _cantCtrl;
    return null;
  }

  TextEditingController get _campoPrincipal =>
      _esPesable ? _pesoTotalCtrl : _cantCtrl;

  void _abrirCalculadora() {
    final controller = _campoFocalizado ?? _campoPrincipal;
    final initial = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
    showCalculadoraDialog(context, initialValue: initial).then((result) {
      if (result != null && mounted) {
        final formatted = _formatearResultado(result);
        controller.text = formatted;
        controller.selection =
            TextSelection.collapsed(offset: formatted.length);
      }
    });
  }

  String _formatearResultado(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f1) {
        _abrirCalculadora();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _registrar();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final existencias = _existencias;
    return AlertDialog(
      title: Text(_producto.nombre),
      content: Focus(
        onKeyEvent: _onKeyEvent,
        child: SingleChildScrollView(
        child: existencias == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'entrada',
                          label: Text('Entrada'),
                          icon: Icon(Icons.input)),
                      ButtonSegment(
                          value: 'salida',
                          label: Text('Salida'),
                          icon: Icon(Icons.output)),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (s) => setState(() {
                      _tipo = s.first;
                      _recetaId = null;
                      _produccionId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Almacén'),
                    initialValue: _almacen,
                    items: [
                      for (final a in _almacenes)
                        DropdownMenuItem(value: a, child: Text(a.capitalize())),
                    ],
                    onChanged: (v) =>
                        setState(() => _almacen = v ?? 'principal'),
                  ),
                  const SizedBox(height: 12),
                  _StockInfoPanel(existencias: existencias),
                  const SizedBox(height: 12),
                  if (!_esPesable)
                    TextField(
                      controller: _cantCtrl,
                      focusNode: _cantFocus,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Cantidad',
                        suffixIcon:
                            CalculadoraSuffixIcon(targetController: _cantCtrl),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onSubmitted: (_) => _registrar(),
                    )
                  else
                    TextField(
                      controller: _pesoTotalCtrl,
                      focusNode: _pesoTotalFocus,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Peso Total (kg)',
                        suffixIcon: CalculadoraSuffixIcon(
                            targetController: _pesoTotalCtrl),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onSubmitted: (_) => _registrar(),
                    ),
                  if (_esProduccion) ...[
                    const SizedBox(height: 16),
                    if (_recetasQueProducen.length > 1)
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Receta'),
                        initialValue: _recetaSeleccionada?.id,
                        items: [
                          for (final r in _recetasQueProducen)
                            DropdownMenuItem(
                                value: r.id, child: Text(r.nombre)),
                        ],
                        onChanged: (v) => setState(() {
                          _recetaId = v;
                          _produccionId = null;
                        }),
                      )
                    else
                      Text(
                        'Receta: ${_recetaSeleccionada?.nombre ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 8),
                    _LoteSelector(
                      key: ValueKey(_recetaSeleccionada?.id),
                      repo: ref.read(produccionesRepoProvider)!,
                      recetaId: _recetaSeleccionada?.id,
                      produccionId: _produccionId,
                      onChanged: (id) => setState(() => _produccionId = id),
                    ),
                  ],
                ],
              ),
          ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _registrando ? null : _registrar,
          child: _registrando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Registrar'),
        ),
      ],
    );
  }
}

class _LoteSelector extends StatefulWidget {
  const _LoteSelector({
    super.key,
    required this.repo,
    required this.recetaId,
    required this.produccionId,
    required this.onChanged,
  });

  final ProduccionesRepository repo;
  final int? recetaId;
  final int? produccionId;
  final ValueChanged<int?> onChanged;

  @override
  State<_LoteSelector> createState() => _LoteSelectorState();
}

class _LoteSelectorState extends State<_LoteSelector> {
  late Future<List<ProduccionInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  @override
  void didUpdateWidget(_LoteSelector old) {
    super.didUpdateWidget(old);
    if (old.recetaId != widget.recetaId) {
      _future = _cargar();
    }
  }

  Future<List<ProduccionInfo>> _cargar() async {
    final recetaId = widget.recetaId;
    if (recetaId == null) return [];
    final pendientes = await widget.repo.getProduccionesPorEstado('pendiente');
    return pendientes.where((p) => p.recetaId == recetaId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final recetaId = widget.recetaId;
    if (recetaId == null) return const SizedBox.shrink();

    return FutureBuilder<List<ProduccionInfo>>(
      future: _future,
      builder: (context, snap) {
        final lotes = snap.data ?? const <ProduccionInfo>[];
        final tieneLotes = lotes.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int?>(
              decoration:
                  const InputDecoration(labelText: 'Vincular a producción'),
              initialValue: widget.produccionId ?? 0,
              items: [
                const DropdownMenuItem<int?>(
                  value: 0,
                  child: Text('Nueva producción (crear lote)'),
                ),
                if (tieneLotes)
                  for (final l in lotes)
                    DropdownMenuItem<int?>(
                      value: l.id,
                      child: Text(
                          'Lote #${l.id} · ${l.cantidad.toStringAsFixed(3)}'),
                    ),
              ],
              onChanged: (v) => widget.onChanged(v == 0 ? null : v),
            ),
            if (tieneLotes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Default: lote más reciente (#${lotes.first.id})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StockInfoPanel extends StatelessWidget {
  const _StockInfoPanel({required this.existencias});

  final List<Existencia> existencias;

  @override
  Widget build(BuildContext context) {
    if (existencias.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Sin stock registrado', style: TextStyle(fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stock por almacén:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final e in existencias)
                Text(
                  '${e.almacen.capitalize()}: ${e.cantidad.toStringAsFixed(e.cantidad % 1 == 0 ? 0 : 2)} ${e.unidad}',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
