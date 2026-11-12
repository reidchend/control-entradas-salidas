import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Timer? _debounce;
  int _selectedIndex = -1;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  static const double _itemExtentEstimado = 70;

  @override
  void initState() {
    super.initState();
    _searchFocus.onKeyEvent = _onSearchKey;
    _buscar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _moverSeleccion(int delta) {
    if (_resultados.isEmpty) return;
    setState(() {
      _selectedIndex =
          (_selectedIndex + delta).clamp(0, _resultados.length - 1);
    });
    _asegurarVisible(_selectedIndex);
  }

  void _asegurarVisible(int index) {
    if (!_scrollCtrl.hasClients) return;
    final objetivo = index * _itemExtentEstimado;
    final viewport = _scrollCtrl.position.viewportDimension;
    final actual = _scrollCtrl.offset;
    if (objetivo < actual) {
      _scrollCtrl.jumpTo(objetivo);
    } else if (objetivo + _itemExtentEstimado > actual + viewport) {
      _scrollCtrl.jumpTo(
        (objetivo + _itemExtentEstimado - viewport).clamp(
          0.0,
          _scrollCtrl.position.maxScrollExtent,
        ),
      );
    }
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_resultados.isEmpty) return KeyEventResult.handled;
      _moverSeleccion(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_resultados.isEmpty) return KeyEventResult.handled;
      _moverSeleccion(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_selectedIndex >= 0 && _selectedIndex < _resultados.length) {
        Navigator.pop(context, _resultados[_selectedIndex]);
        return KeyEventResult.handled;
      }
      if (_resultados.length == 1) {
        Navigator.pop(context, _resultados.first);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _buscar() async {
    final repo = ref.read(requisicionesRepoProvider);
    if (repo == null) return;
    final res = await repo.buscarProductos(_busqueda);
    if (!mounted) return;
    setState(() {
      _resultados = res;
      _selectedIndex = res.isEmpty ? -1 : 0;
    });
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
              focusNode: _searchFocus,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Usa ↑ ↓ y Enter para seleccionar',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _busqueda = v;
                _debounce?.cancel();
                _debounce =
                    Timer(const Duration(milliseconds: 350), _buscar);
              },
              onSubmitted: (_) {
                if (_selectedIndex >= 0 && _selectedIndex < _resultados.length) {
                  Navigator.pop(context, _resultados[_selectedIndex]);
                } else if (_resultados.length == 1) {
                  Navigator.pop(context, _resultados.first);
                }
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
                      controller: _scrollCtrl,
                      itemCount: _resultados.length,
                      itemBuilder: (context, i) {
                        final p = _resultados[i];
                        final nombre = (p['nombre'] as String?) ?? '';
                        final unidad = (p['unidad_medida'] as String?) ?? '';
                        final esPesable =
                            p['es_pesable'] == true || p['es_pesable'] == 1;
                        final seleccionado = i == _selectedIndex;
                        return InkWell(
                          onTap: () => Navigator.pop(context, p),
                          onHover: (hovering) {
                            if (hovering && _selectedIndex != i) {
                              setState(() => _selectedIndex = i);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: seleccionado
                                  ? scheme.primary.withValues(alpha: 0.14)
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: seleccionado
                                    ? scheme.primary
                                    : Colors.transparent,
                                width: 1.2,
                              ),
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
