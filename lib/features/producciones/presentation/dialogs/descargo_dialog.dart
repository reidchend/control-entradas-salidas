import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/receta.dart';
import '../../data/producciones_providers.dart';
import '../../data/producciones_repository.dart';

/// Diálogo para registrar el descargo de ingredientes de una producción
/// pendiente (porta `descargo_dialog` de `dialogs.py`).
Future<void> showDescargoDialog(
  BuildContext context,
  WidgetRef ref,
  ProduccionInfo produccion,
  Receta receta, {
  VoidCallback? onCompleted,
}) async {
  final repo = ref.read(produccionesRepoProvider)!;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DescargoDialog(
      repo: repo,
      produccion: produccion,
      receta: receta,
      onCompleted: onCompleted,
    ),
  );
}

class _DescargoDialog extends ConsumerStatefulWidget {
  const _DescargoDialog({
    required this.repo,
    required this.produccion,
    required this.receta,
    this.onCompleted,
  });

  final ProduccionesRepository repo;
  final ProduccionInfo produccion;
  final Receta receta;
  final VoidCallback? onCompleted;

  @override
  ConsumerState<_DescargoDialog> createState() => _DescargoDialogState();
}

class _DescargoDialogState extends ConsumerState<_DescargoDialog> {
  late Future<_DescargoData> _future;
  final _cocinerosCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  @override
  void dispose() {
    _cocinerosCtrl.dispose();
    super.dispose();
  }

  Future<_DescargoData> _cargar() async {
    final items = await widget.repo.planificarDescargo(
        widget.produccion, widget.receta);
    var producidos = await widget.repo
        .productosProducidos(widget.produccion.id);
    if (producidos.isEmpty) {
      producidos = [
        Producido(
          productoId: widget.receta.productoFinalId ?? 0,
          nombre: widget.receta.nombre,
          cantidad: widget.produccion.cantidad,
          unidad: 'unidad',
        ),
      ];
    }
    final almacenes = await widget.repo.getAlmacenes();
    final defaultAlmacen = await widget.repo.almacenProduccionDefault();
    return _DescargoData(
      items: items,
      producidos: producidos,
      almacenes: almacenes.isEmpty ? ['principal', 'restaurante'] : almacenes,
      almacenDefault:
          almacenes.contains(defaultAlmacen) ? defaultAlmacen : almacenes.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DescargoData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AlertDialog(
            content: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError) {
          return AlertDialog(
            title: const Text('Error'),
            content: Text('${snap.error}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        }
        final data = snap.data!;
        if (data.items.isEmpty) {
          return const AlertDialog(
            title: Text('Sin ingredientes'),
            content: Text('Esta receta no tiene ingredientes definidos para descargar.'),
            actions: [
              TextButton(
                onPressed: _noop,
                child: Text('Cerrar'),
              ),
            ],
          );
        }
        return _DescargoBody(
          repo: widget.repo,
          produccion: widget.produccion,
          receta: widget.receta,
          data: data,
          cocinerosCtrl: _cocinerosCtrl,
          onCompleted: widget.onCompleted,
        );
      },
    );
  }

  static void _noop() {}
}

class _DescargoData {
  const _DescargoData({
    required this.items,
    required this.producidos,
    required this.almacenes,
    required this.almacenDefault,
  });

  final List<DescargoItem> items;
  final List<Producido> producidos;
  final List<String> almacenes;
  final String almacenDefault;
}

class _DescargoBody extends ConsumerStatefulWidget {
  const _DescargoBody({
    required this.repo,
    required this.produccion,
    required this.receta,
    required this.data,
    required this.cocinerosCtrl,
    this.onCompleted,
  });

  final ProduccionesRepository repo;
  final ProduccionInfo produccion;
  final Receta receta;
  final _DescargoData data;
  final TextEditingController cocinerosCtrl;
  final VoidCallback? onCompleted;

  @override
  ConsumerState<_DescargoBody> createState() => _DescargoBodyState();
}

class _DescargoBodyState extends ConsumerState<_DescargoBody> {
  late String _almacen;
  late final List<TextEditingController> _cantCtrls;
  final List<GlobalKey> _stockKeys = [];

  @override
  void initState() {
    super.initState();
    _almacen = widget.data.almacenDefault;
    _cantCtrls = [
      for (final item in widget.data.items)
        TextEditingController(
          text: item.pesoVariable
              ? ''
              : _fmtSugerida(item.cantidadSugerida),
        ),
    ];
    for (final _ in widget.data.items) {
      _stockKeys.add(GlobalKey());
    }
    // Cargar stock inicial para el almacén por defecto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _actualizarStock();
    });
  }

  @override
  void dispose() {
    for (final c in _cantCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtSugerida(double v) => v.toStringAsFixed(3);

  String _fmtStock(double v) {
    final s = v.toStringAsFixed(3);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  void _actualizarStock() async {
    final repo = widget.repo;
    for (var i = 0; i < widget.data.items.length; i++) {
      final state = _stockKeys[i].currentState as _StockTextState?;
      if (state == null) continue;
      final cant =
          await repo.getExistencia(widget.data.items[i].productoId, _almacen);
      if (!mounted) return;
      state.actualizar(
        cant,
        widget.data.items[i].unidadLabel,
      );
    }
  }

  Future<void> _confirmar() async {
    final itemsCantidades = <DescargoItem>[];
    final errores = <String>[];

    for (var i = 0; i < widget.data.items.length; i++) {
      final item = widget.data.items[i];
      final raw = _cantCtrls[i].text.trim().replaceAll(',', '.');
      double cantidad;
      try {
        cantidad = double.tryParse(raw) ?? 0;
      } catch (_) {
        errores.add('Cantidad inválida para producto ${item.productoId}');
        continue;
      }
      if (cantidad <= 0) {
        errores.add('Cantidad debe ser > 0 para producto ${item.productoId}');
        continue;
      }
      itemsCantidades.add(DescargoItem(
        productoId: item.productoId,
        nombre: item.nombre,
        cantidadSugerida: cantidad,
        pesoVariable: item.esPesable,
        unidad: item.unidad,
        esPesable: item.esPesable,
        almacen: _almacen,
      ));
    }

    if (errores.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errores.join('\n'))),
        );
      }
      return;
    }

    try {
      final (ok, errs) = await widget.repo.ejecutarDescargo(
        produccion: widget.produccion,
        receta: widget.receta,
        items: itemsCantidades,
        cocineros: widget.cocinerosCtrl.text.trim().isNotEmpty
            ? widget.cocinerosCtrl.text.trim()
            : null,
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'No se pudo completar el descargo:\n${errs.map((e) => '• $e').join('\n')}'),
            ),
          );
        }
        return;
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Producción #${widget.produccion.id} completada')),
        );
      }
      widget.onCompleted?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al ejecutar descargo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = widget.data;

    return AlertDialog(
      title: const Text('Descargar Producción'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Receta: ${widget.receta.nombre} · Producción #${widget.produccion.id}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Cantidades producidas:',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('Almacén:',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _almacen,
                    items: [
                      for (final a in data.almacenes)
                        DropdownMenuItem(value: a, child: Text(a.capitalize())),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _almacen = v);
                        _actualizarStock();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final p in data.producidos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.nombre,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_fmtStock(p.cantidad)} ${p.unidad}',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Cocineros:',
                      style:
                          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: widget.cocinerosCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cocineros',
                        hintText: 'Nombre del cocinero que realizó la producción',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                'Ingresa el peso/cantidad real usado de cada ingrediente:',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < data.items.length; i++)
                _buildItemRow(scheme, data.items[i], i),
            ],
          ),
        ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar Descargo'),
        ),
      ],
    );
  }

  Widget _buildItemRow(ColorScheme scheme, DescargoItem item, int index) {
    final unidadLabel = item.unidadLabel;
    final esVariable = item.pesoVariable;

    return LayoutBuilder(
      builder: (context, constraints) {
        final angosto = constraints.maxWidth < 400;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: angosto
              ? _buildItemRowAngosto(scheme, item, index, unidadLabel, esVariable)
              : _buildItemRowAncho(scheme, item, index, unidadLabel, esVariable),
        );
      },
    );
  }

  Widget _buildItemRowAncho(
    ColorScheme scheme,
    DescargoItem item,
    int index,
    String unidadLabel,
    bool esVariable,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  Text(
                    esVariable ? 'Variable · $unidadLabel' : 'Sugerido · $unidadLabel',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  Text(' · ',
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
                  _StockText(
                    key: _stockKeys[index],
                    scheme: scheme,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _cantCtrls[index],
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: esVariable,
            decoration: InputDecoration(
              suffixText: unidadLabel,
              isDense: true,
              hintText: esVariable ? 'Peso real (kg)' : 'Sugerido',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRowAngosto(
    ColorScheme scheme,
    DescargoItem item,
    int index,
    String unidadLabel,
    bool esVariable,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 2,
          children: [
            Text(
              esVariable ? 'Variable · $unidadLabel' : 'Sugerido · $unidadLabel',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            _StockText(
              key: _stockKeys[index],
              scheme: scheme,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextField(
            controller: _cantCtrls[index],
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: esVariable,
            decoration: InputDecoration(
              suffixText: unidadLabel,
              isDense: true,
              hintText: esVariable ? 'Peso real (kg)' : 'Sugerido',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _StockText extends StatefulWidget {
  const _StockText({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  State<_StockText> createState() => _StockTextState();
}

class _StockTextState extends State<_StockText> {
  double _cant = -1;
  String _unidad = '';

  void actualizar(double cant, String unidad) {
    setState(() {
      _cant = cant;
      _unidad = unidad;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _cant <= 0 ? widget.scheme.error : Colors.green;
    final texto = _cant < 0
        ? '—'
        : 'Stock disponible: ${_fmt(_cant)} $_unidad';
    return Text(
      texto,
      style: TextStyle(fontSize: 11, color: color),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(3);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}

extension _Capitalize on String {
  String capitalize() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
}
