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
///
/// La persistencia va por [onGuardar] (devuelve la unidad guardada para que el
/// modo "agregar otra" pueda mostrar la placa); el diálogo solo se cierra.
Future<void> showUnidadDialog(
  BuildContext context, {
  required List<ActivoTipo> tipos,
  required Future<Activo> Function(Activo activo) onGuardar,
  int? tipoIdFijo,
  Activo? unidad,
  List<ActivosCategoria> categorias = const [],
  List<String> estados = const ['Activo'],
  List<String> grupos = const [],
  List<String> modelos = const [],
  Future<int> Function(ActivoTipo tipo)? onCrearTipo,
  Future<String> Function(String nombre)? onCrearEstado,
  Future<bool> Function(int tipoId, String ubicacion)? onExisteUnidad,
  String? ubicacionPreset,
  String? estadoPreset,
  List<String> ubicacionesSugeridas = const [],
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(unidad == null ? 'Agregar Unidad' : 'Editar Unidad'),
      content: SizedBox(
        width: 460,
        child: ActivoForm(
          tipos: tipos,
          tipoIdFijo: tipoIdFijo,
          unidad: unidad,
          categorias: categorias,
          estados: estados,
          grupos: grupos,
          modelos: modelos,
          onGuardar: onGuardar,
          onCrearTipo: onCrearTipo,
          onCrearEstado: onCrearEstado,
          onExisteUnidad: onExisteUnidad,
          ubicacionPreset: ubicacionPreset,
          estadoPreset: estadoPreset,
          ubicacionesSugeridas: ubicacionesSugeridas,
          onCerrar: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}
