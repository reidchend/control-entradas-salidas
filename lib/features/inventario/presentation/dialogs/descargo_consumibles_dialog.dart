import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/existencia.dart';
import '../../../../core/models/producto.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../calculadora/presentation/calculadora_button.dart';
import '../../data/inventario_providers.dart';

/// Diálogo de descargo masivo de consumibles (productos de tipo
/// "Consumo": servilletas, bolsas, etc.).
///
/// Lista cada consumible con su stock por almacén y permite registrar la
/// salida (tipo `consumo`) de varios de una vez.
Future<void> showDescargoConsumiblesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const DescargoConsumiblesDialog(),
  );
}

class DescargoConsumiblesDialog extends ConsumerStatefulWidget {
  const DescargoConsumiblesDialog({super.key});

  @override
  ConsumerState<DescargoConsumiblesDialog> createState() =>
      _DescargoConsumiblesDialogState();
}

class _DescargoConsumiblesDialogState
    extends ConsumerState<DescargoConsumiblesDialog> {
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
    final repo = ref.read(inventarioRepoProvider);
    if (repo == null) {
      if (mounted) setState(() => _error = 'Supabase no configurado');
      return;
    }
    try {
      final prods = await repo.getProductosConsumibles();
      final exis = <int, List<Existencia>>{};
      for (final p in prods) {
        exis[p.id] = await repo.getExistenciasByProducto(p.id);
      }
      if (!mounted) return;
      setState(() {
        _productos = prods;
        _existencias
          ..clear()
          ..addAll(exis);
        for (final p in prods) {
          _ctrlValor.putIfAbsent(p.id, () => TextEditingController());
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al cargar: $e');
    }
  }

  /// Almacén con mayor stock disponible distinto del principal, para decidir
  /// de dónde descargar. El almacén principal guarda existencias sin uso, así
  /// que nunca se descarga consumibles desde allí.
  String? _almacenPara(int productoId) {
    final posibles = (_existencias[productoId] ?? const <Existencia>[])
        .where((e) => e.almacen != 'principal' && e.cantidad > 0)
        .toList();
    if (posibles.isEmpty) return null;
    return posibles.reduce((a, b) => a.cantidad >= b.cantidad ? a : b).almacen;
  }

  Future<void> _registrar() async {
    final repo = ref.read(inventarioRepoProvider);
    if (repo == null || _productos == null) return;

    final session = ref.read(sessionProvider);
    final usuario = session is Authenticated ? session.nombre : 'Sistema';

    final aProcesar = <(Producto, double, double, String)>[];
    final sinAlmacen = <String>[];
    for (final p in _productos!) {
      final valor =
          double.tryParse(_ctrlValor[p.id]!.text.replaceAll(',', '.').trim()) ??
              0;
      if (valor <= 0) continue;
      final almacen = _almacenPara(p.id);
      if (almacen == null) {
        sinAlmacen.add(p.nombre);
        continue;
      }
      final peso = p.esPesable ? valor : 0.0;
      aProcesar.add((p, valor, peso, almacen));
    }
    if (aProcesar.isEmpty) {
      if (sinAlmacen.isEmpty) {
        showInfoSnackBar(context, 'Ingrese al menos una cantidad a descargar');
      } else {
        showErrorSnackBar(
          context,
          'No hay stock disponible fuera del almacén principal en: '
          '${sinAlmacen.join(', ')}',
        );
      }
      return;
    }

    setState(() => _registrando = true);
    var ok = 0;
    final fallos = <String>[];
    for (final (p, cantidad, peso, almacen) in aProcesar) {
      final res = await repo.registrarMovimiento(
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
    } else if (ok > 0) {
      showSuccessSnackBar(context, '$ok descargo(s) registrado(s)');
      Navigator.pop(context);
    } else {
      showInfoSnackBar(context, 'No se registraron descargos');
    }
  }

  String _fmtCant(double v, bool pesable) =>
      v == v.roundToDouble() && !pesable
          ? v.toInt().toString()
          : v.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prods = _productos;
    final isMobile = MediaQuery.of(context).size.width < 700;

    final contenido = _error != null
        ? Text(_error!, style: TextStyle(color: scheme.error))
        : prods == null
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : prods.isEmpty
                ? const Text(
                    'No hay productos de tipo "Consumo". Márcalos en '
                    'Configuración → Productos → Tipo.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in prods)
                          _FilaConsumible(
                            producto: p,
                            existencias:
                                _existencias[p.id] ?? const <Existencia>[],
                            almacen: _almacenPara(p.id),
                            controller: _ctrlValor[p.id]!,
                            fmtCant: (v) => _fmtCant(v, p.esPesable),
                          ),
                      ],
                    ),
                  );

    return AlertDialog(
      title: const Text('Descargo de consumibles'),
      content: SizedBox(
        width: isMobile ? 380 : 560,
        child: contenido,
      ),
      actions: [
        TextButton(
          onPressed: _registrando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _registrando ? null : _registrar,
          icon: _registrando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.output, size: 18),
          label: Text(_registrando ? 'Registrando...' : 'Registrar descargos'),
        ),
      ],
    );
  }
}

class _FilaConsumible extends StatelessWidget {
  const _FilaConsumible({
    required this.producto,
    required this.existencias,
    required this.almacen,
    required this.controller,
    required this.fmtCant,
  });

  final Producto producto;
  final List<Existencia> existencias;
  final String? almacen;
  final TextEditingController controller;
  final String Function(double) fmtCant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disponibles = existencias
        .map((e) => '${e.almacen.capitalize()}: ${fmtCant(e.cantidad)} '
            '${e.unidad}')
        .join('  ·  ');
    final estaMarcado =
        (double.tryParse(controller.text.replaceAll(',', '.')) ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: estaMarcado ? Border.all(color: scheme.primary, width: 1.4) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(producto.nombre,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          if (disponibles.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              disponibles,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            Text(
              almacen != null
                  ? 'Descarga desde: ${almacen!.capitalize()}'
                  : 'Sin stock fuera del almacén principal',
              style: TextStyle(
                fontSize: 11,
                color: almacen != null
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: producto.esPesable ? 'Peso a descargar (kg)' : 'Cantidad a descargar',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: CalculadoraSuffixIcon(targetController: controller),
            ),
            keyboardType: TextInputType.numberWithOptions(
                decimal: producto.esPesable),
          ),
        ],
      ),
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}