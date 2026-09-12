import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/modal_sizing.dart';
import '../../data/requisiciones_providers.dart';

Future<Map<String, dynamic>?> showBuscadorProductos(BuildContext context) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => const _BuscadorProductosDialog(),
  );
}

class _BuscadorProductosDialog extends ConsumerStatefulWidget {
  const _BuscadorProductosDialog();

  @override
  ConsumerState<_BuscadorProductosDialog> createState() =>
      _BuscadorProductosDialogState();
}

class _BuscadorProductosDialogState
    extends ConsumerState<_BuscadorProductosDialog> {
  String _busqueda = '';
  List<Map<String, dynamic>> _resultados = [];

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    final repo = ref.read(requisicionesRepoProvider);
    if (repo == null) return;
    final res = await repo.buscarProductos(_busqueda);
    if (mounted) setState(() => _resultados = res);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Buscar producto'),
      content: SizedBox(
        width: modalContentWidth(context),
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _busqueda = v;
                _buscar();
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _resultados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 42, color: scheme.outline),
                          const SizedBox(height: 8),
                          Text('Sin resultados',
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _resultados.length,
                      itemBuilder: (context, i) {
                        final p = _resultados[i];
                        final nombre = (p['nombre'] as String?) ?? '';
                        final unidad = (p['unidad_medida'] as String?) ?? '';
                        final esPesable = p['es_pesable'] == true || p['es_pesable'] == 1;
                        return InkWell(
                          onTap: () => Navigator.pop(context, p),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: scheme.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                      Icons.inventory_2_outlined,
                                      size: 19,
                                      color: scheme.primary),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(nombre,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                        'Unidad: $unidad · ${esPesable ? 'pesable' : 'no pesable'}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.add_circle,
                                    color: Colors.green.shade600),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
