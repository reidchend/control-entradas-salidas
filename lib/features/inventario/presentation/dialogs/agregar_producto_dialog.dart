import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/inventario_providers.dart';

/// Diálogo para agregar un nuevo producto.
Future<void> showAgregarProductoDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(inventarioRepoProvider)!;
  final categorias = await repo.getAllCategorias();

  final nombreCtrl = TextEditingController();
  final codigoCtrl = TextEditingController();
  final precioCtrl = TextEditingController();
  final stockMinCtrl = TextEditingController(text: '0');
  int? categoriaId = categorias.isNotEmpty ? categorias.first.id : null;
  bool esPesable = false;
  String unidad = 'unidad';

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nuevo Producto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              autofocus: true,
            ),
            TextField(controller: codigoCtrl, decoration: const InputDecoration(labelText: 'Código')),
            if (categorias.isNotEmpty)
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Categoría'),
                initialValue: categoriaId,
                items: categorias
                    .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.activo
                            ? c.nombre
                            : '${c.nombre} (inactiva)')))
                    .toList(),
                onChanged: (v) => categoriaId = v,
              ),
            TextField(
              controller: precioCtrl,
              decoration: const InputDecoration(labelText: 'Precio venta'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: stockMinCtrl,
              decoration: const InputDecoration(labelText: 'Stock mínimo'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Unidad'),
              initialValue: 'unidad',
              items: ['unidad', 'kg', 'litro', 'caja', 'paquete']
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => unidad = v ?? 'unidad',
            ),
            SwitchListTile(
              title: const Text('Producto pesable (kg)'),
              value: esPesable,
              onChanged: (v) => esPesable = v,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            if (nombreCtrl.text.trim().isEmpty) return;
            await repo.insertProducto(
              nombre: nombreCtrl.text.trim(),
              codigo: codigoCtrl.text.trim().isEmpty ? null : codigoCtrl.text.trim(),
              categoriaId: categoriaId,
              precioVenta: double.tryParse(precioCtrl.text) ?? 0,
              stockMinimo: double.tryParse(stockMinCtrl.text) ?? 0,
              unidadMedida: unidad,
              esPesable: esPesable,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Crear'),
        ),
      ],
    ),
  );
}