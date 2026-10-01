import 'package:flutter/material.dart';

import '../../data/activo.dart';
import '../../data/activo_tipo.dart';
import '../../data/activos_categoria.dart';
import '../widgets/activo_form.dart';

/// Diálogo crear/editar una unidad de activo.
///
/// Se conserva para los puntos de entrada que ya viven dentro de otra pantalla
/// (detalle de un tipo, panel de filtros), donde abrir una pantalla completa
/// taparía el contexto desde el que se está agregando la unidad. El formulario
/// en sí está en `ActivoForm`, que la pantalla nueva comparte.
Future<Activo?> showUnidadDialog(
  BuildContext context, {
  required List<ActivoTipo> tipos,
  int? tipoIdFijo,
  Activo? unidad,
  List<ActivosCategoria> categorias = const [],
  Future<int> Function(ActivoTipo tipo)? onCrearTipo,
  String? ubicacionPreset,
  String? estadoPreset,
  List<String> ubicacionesSugeridas = const [],
}) {
  return showDialog<Activo>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(unidad == null ? 'Agregar Unidad' : 'Editar Unidad'),
      content: SizedBox(
        width: 460,
        child: ActivoForm(
          tipos: tipos,
          tipoIdFijo: tipoIdFijo,
          unidad: unidad,
          categorias: categorias,
          onCrearTipo: onCrearTipo,
          ubicacionPreset: ubicacionPreset,
          estadoPreset: estadoPreset,
          ubicacionesSugeridas: ubicacionesSugeridas,
          onGuardar: (activo) async {
            Navigator.of(context).pop(activo);
          },
          onCancelar: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}
