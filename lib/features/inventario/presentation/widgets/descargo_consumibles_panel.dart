import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/existencia.dart';
import '../../../../core/models/producto.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../data/inventario_repository.dart';
import 'descargo_consumibles_item.dart';

/// Vista completa de "Descargo de consumibles" (modo toggle).
///
/// Lista solo los productos de tipo "Consumo" con existencias > 0 en algún
/// almacén distinto del principal y precarga esa cantidad en el campo de
/// texto, de modo que basta presionar "Registrar descargos" sin editar nada.
class DescargoConsumiblesPanel extends ConsumerStatefulWidget {
  const DescargoConsumiblesPanel({
    super.key,
    required this.repo,
    required this.onClose,
  });

  final InventarioRepository repo;
  final VoidCallback onClose;

  @override
  ConsumerState<DescargoConsumiblesPanel> createState() =>
      _DescargoConsumiblesPanelState();
}

class _DescargoConsumiblesPanelState
    extends ConsumerState<DescargoConsumiblesPanel> {
  List<Producto>? _productos;
  final Map<int, List<Existencia>> _existencias = {};
  final Map<int, TextEditingController> _ctrlValor = {};
  bool _registrando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _ctrlValor.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final prods = await widget.repo.getProductosConsumibles();
      final exis = <int, List<Existencia>>{};
      for (final p in prods) {
        exis[p.id] = await widget.repo.getExistenciasByProducto(p.id);
      }
      // Solo consumibles con stock > 0 fuera del almacén principal.
      final visibles = prods
          .where((p) => _almacenPara(exis[p.id] ?? const <Existencia>[]) != null)
          .toList();
      if (!mounted) return;
      setState(() {
        _productos = visibles;
        _existencias
          ..clear()
          ..addAll(exis);
        for (final p in visibles) {
          _ctrlValor
            ..removeWhere((k, _) => !visibles.any((x) => x.id == k))
            ..putIfAbsent(p.id, () => TextEditingController());
          // Precargar la existencia disponible del almacén de descarga.
          final almacen = _almacenPara(exis[p.id] ?? const <Existencia>[]);
          final cant = (exis[p.id] ?? const <Existencia>[])
              .where((e) => e.almacen == almacen)
              .map((e) => e.cantidad)
              .firstOrNull ?? 0;
          _ctrlValor[p.id]!.text = _fmtCant(cant, p.esPesable);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al cargar: $e');
    }
  }

  /// Almacén con mayor stock disponible distinto del principal, para decidir
  /// de dónde descargar.
  String? _almacenPara(List<Existencia> exis) {
    final posibles =
        exis.where((e) => e.almacen != 'principal' && e.cantidad > 0).toList();
    if (posibles.isEmpty) return null;
    return posibles.reduce((a, b) => a.cantidad >= b.cantidad ? a : b).almacen;
  }

  Future<void> _registrar() async {
    final prods = _productos;
    if (prods == null) return;

    final session = ref.read(sessionProvider);
    final usuario = session is Authenticated ? session.nombre : 'Sistema';

    final aProcesar = <(Producto, double, double, String)>[];
    for (final p in prods) {
      final valor =
          double.tryParse(_ctrlValor[p.id]!.text.replaceAll(',', '.').trim()) ??
              0;
      if (valor <= 0) continue;
      final almacen = _almacenPara(_existencias[p.id] ?? const <Existencia>[]);
      if (almacen == null) continue;
      final peso = p.esPesable ? valor : 0.0;
      aProcesar.add((p, valor, peso, almacen));
    }
    if (aProcesar.isEmpty) {
      showInfoSnackBar(context,
          'No hay cantidades por descargar en almacenes distintos del principal');
      return;
    }

    setState(() => _registrando = true);
    var ok = 0;
    final fallos = <String>[];
    for (final (p, cantidad, peso, almacen) in aProcesar) {
      final res = await widget.repo.registrarMovimiento(
        productoId: p.id,
        tipo: 'consumo',
        cantidad: cantidad,
        pesoTotal: peso,
        almacen: almacen,
        registradoPor: usuario,
        esPesable: p.esPesable,
        unidadMedida: p.unidadMedida,
        observaciones: 'Descargo consumible',
      );
      if (res) {
        ok++;
      } else {
        fallos.add('${p.nombre} ($almacen)');
      }
    }
    if (!mounted) return;
    setState(() => _registrando = false);

    if (fallos.isNotEmpty) {
      showErrorSnackBar(
        context,
        'Se descargaron $ok consumible(s). Sin stock: ${fallos.join(', ')}',
      );
    } else {
      showSuccessSnackBar(context,
          '$ok descargo(s) registrado(s)');
    }
    if (ok > 0) _cargar();
  }

  String _fmtCant(double v, bool pesable) =>
      v == v.roundToDouble() && !pesable
          ? v.toInt().toString()
          : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prods = _productos;
    final total = prods?.length ?? 0;
    final totalDisponible = _totalDisponible(prods);

    return Column(
      children: [
        _buildInfoBar(scheme, total, totalDisponible),
        Expanded(child: _buildLista(scheme)),
        _buildBarraAccion(),
      ],
    );
  }

  Widget _buildInfoBar(ColorScheme scheme, int total, double totalDisponible) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: scheme.surfaceContainerHighest,
      child: Text(
        _error != null
            ? _error!
            : _productos == null
                ? 'Cargando consumibles...'
                : total == 0
                    ? 'Sin consumibles con stock fuera del almacén principal'
                    : '$total consumible(s) con stock disponible · '
                        'Total a descargar: $totalDisponible',
        style: TextStyle(
          fontSize: 12,
          color: _error != null ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  double _totalDisponible(List<Producto>? prods) {
    if (prods == null) return 0;
    var acc = 0.0;
    for (final p in prods) {
      final almacen =
          _almacenPara(_existencias[p.id] ?? const <Existencia>[]);
      acc += (_existencias[p.id] ?? const <Existencia>[])
          .where((e) => e.almacen == almacen)
          .map((e) => e.cantidad)
          .firstOrNull ?? 0;
    }
    return acc;
  }

  Widget _buildLista(ColorScheme scheme) {
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: scheme.error)));
    }
    final prods = _productos;
    if (prods == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prods.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 60, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Sin consumibles con stock',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Solo se listan consumibles con existencias > 0 en '
              'almacenes distintos del principal',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: prods.length,
      itemBuilder: (context, i) {
        final p = prods[i];
        return DescargoConsumibleItem(
          producto: p,
          existencias: _existencias[p.id] ?? const <Existencia>[],
          almacen: _almacenPara(_existencias[p.id] ?? const <Existencia>[]),
          controller: _ctrlValor[p.id]!,
          fmtCant: (v) => _fmtCant(v, p.esPesable),
        );
      },
    );
  }

  Widget _buildBarraAccion() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _registrando ? null : _registrar,
            icon: _registrando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.output, size: 18),
            label: Text(
                _registrando ? 'Registrando...' : 'Descargar todo (+${_productos?.length ?? 0})'),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: _registrando ? null : widget.onClose,
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}