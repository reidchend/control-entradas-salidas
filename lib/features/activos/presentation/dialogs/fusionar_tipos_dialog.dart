import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';

/// Resultado de la fusión: el tipo que sobrevive y los tipos origen cuyas
/// unidades se mueven a él.
typedef FusionTipos = ({int destinoId, List<int> origenIds});

/// Diálogo para fusionar varios tipos del catálogo en uno solo.
///
/// Se eligen dos o más tipos; uno de los seleccionados se marca como el que
/// sobrevive (destino) y las unidades de los demás se mueven a él. El diálogo
/// solo decide *qué* fusionar: el movimiento/borrado lo hace el repositorio.
///
/// [tipos] es la salida de `getTipos()` (mapas con `'tipo'`, `'unidades'` y
/// `'categoria_nombre'`). Devuelve `null` si se cancela.
Future<FusionTipos?> showFusionarTiposDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> tipos,
}) {
  return showDialog<FusionTipos>(
    context: context,
    builder: (_) => _FusionarTiposDialog(tipos: tipos),
  );
}

class _FusionarTiposDialog extends StatefulWidget {
  const _FusionarTiposDialog({required this.tipos});

  final List<Map<String, dynamic>> tipos;

  @override
  State<_FusionarTiposDialog> createState() => _FusionarTiposDialogState();
}

class _FusionarTiposDialogState extends State<_FusionarTiposDialog> {
  final _searchCtrl = TextEditingController();
  final Set<int> _seleccion = {};
  int? _destinoId;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  ActivoTipo _tipoDe(Map<String, dynamic> it) => it['tipo'] as ActivoTipo;
  int _unidadesDe(Map<String, dynamic> it) =>
      (it['unidades'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get _filtrados {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.tipos;
    return [
      for (final it in widget.tipos)
        if (_coincide(it, q)) it,
    ];
  }

  bool _coincide(Map<String, dynamic> it, String q) {
    final t = _tipoDe(it);
    final campos = [
      t.nombre,
      t.grupo ?? '',
      t.modelo ?? '',
      (it['categoria_nombre'] as String?) ?? '',
    ];
    return campos.any((c) => c.toLowerCase().contains(q));
  }

  /// Unidades que se moverían al destino (los seleccionados menos el destino).
  int get _unidadesMover {
    var total = 0;
    for (final it in widget.tipos) {
      final id = _tipoDe(it).id;
      if (_seleccion.contains(id) && id != _destinoId) total += _unidadesDe(it);
    }
    return total;
  }

  void _toggle(int id, bool? on) {
    setState(() {
      if (on ?? false) {
        _seleccion.add(id);
        _destinoId ??= id;
      } else {
        _seleccion.remove(id);
        if (_destinoId == id) {
          _destinoId = _seleccion.isEmpty ? null : _seleccion.first;
        }
      }
    });
  }

  String _subtitulo(Map<String, dynamic> it) {
    final t = _tipoDe(it);
    final partes = <String>[
      (it['categoria_nombre'] as String?) ?? 'Sin categoría',
      if ((t.grupo ?? '').trim().isNotEmpty) t.grupo!.trim(),
      if ((t.modelo ?? '').trim().isNotEmpty) t.modelo!.trim(),
      '${_unidadesDe(it)} unid.',
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final ancho = size.width < 620 ? size.width * 0.92 : 560.0;
    final alto = (size.height * 0.72).clamp(320.0, 520.0).toDouble();
    final seleccionados = _seleccion.length;

    return AlertDialog(
      title: const Text('Fusionar tipos'),
      content: SizedBox(
        width: ancho,
        height: alto,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Elegí dos o más tipos. Las unidades de los demás se mueven al '
              'tipo que sobrevive y los tipos sobrantes se eliminan. Las '
              'placas y los datos de cada unidad no cambian.',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            if (seleccionados >= 2) ...[
              const SizedBox(height: 10),
              _destinoPicker(colors),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar tipo...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(child: _lista()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: seleccionados >= 2 && _destinoId != null
              ? () => Navigator.pop(
                    context,
                    (destinoId: _destinoId!, origenIds: _seleccion.toList()),
                  )
              : null,
          icon: const Icon(Icons.call_merge, size: 18),
          label: Text(
            seleccionados >= 2 ? 'Fusionar $seleccionados tipos' : 'Fusionar',
          ),
        ),
      ],
    );
  }

  Widget _destinoPicker(ColorScheme colors) {
    final seleccionados = [
      for (final it in widget.tipos)
        if (_seleccion.contains(_tipoDe(it).id)) it,
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tipo que sobrevive',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: colors.primary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final it in seleccionados)
                ChoiceChip(
                  label: Text(
                    _tipoDe(it).nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: _destinoId == _tipoDe(it).id,
                  onSelected: (_) =>
                      setState(() => _destinoId = _tipoDe(it).id),
                ),
            ],
          ),
          if (_destinoId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Se moverán $_unidadesMover unidades desde ${seleccionados.length - 1} '
              'tipo(s) origen.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lista() {
    final items = _filtrados;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        final t = _tipoDe(it);
        return CheckboxListTile(
          dense: true,
          value: _seleccion.contains(t.id),
          onChanged: (v) => _toggle(t.id, v),
          title: Text(t.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _subtitulo(it),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}