import 'package:flutter/material.dart';

import '../data/activo.dart';
import '../data/activo_tipo.dart';
import '../data/activos_categoria.dart';
import 'widgets/activo_form.dart';

/// Abre el formulario como pantalla completa en vez de diálogo.
///
/// Devuelve el [Activo] armado, igual que el diálogo, para que quien llama
/// siga guardando con su repositorio y sus mensajes de error.
///
/// Va como pantalla y no como diálogo porque seis campos no entran cómodo en un
/// `AlertDialog`: con scroll queda medio formulario a la vista, que es cuando
/// no se sabe qué falta.
Future<Activo?> showActivoFormScreen(
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
  return Navigator.of(context).push<Activo>(
    MaterialPageRoute(
      builder: (_) => ActivoFormScreen(
        tipos: tipos,
        tipoIdFijo: tipoIdFijo,
        unidad: unidad,
        categorias: categorias,
        onCrearTipo: onCrearTipo,
        ubicacionPreset: ubicacionPreset,
        estadoPreset: estadoPreset,
        ubicacionesSugeridas: ubicacionesSugeridas,
      ),
    ),
  );
}

class ActivoFormScreen extends StatelessWidget {
  const ActivoFormScreen({
    super.key,
    required this.tipos,
    this.tipoIdFijo,
    this.unidad,
    this.categorias = const [],
    this.onCrearTipo,
    this.ubicacionPreset,
    this.estadoPreset,
    this.ubicacionesSugeridas = const [],
  });

  final List<ActivoTipo> tipos;
  final int? tipoIdFijo;
  final Activo? unidad;
  final List<ActivosCategoria> categorias;
  final Future<int> Function(ActivoTipo tipo)? onCrearTipo;
  final String? ubicacionPreset;
  final String? estadoPreset;
  final List<String> ubicacionesSugeridas;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(unidad == null ? 'Agregar Unidad' : 'Editar Unidad'),
      ),
      body: SafeArea(
        child: Center(
          // El formulario se estira hasta un tope para que en pantallas anchas
          // los campos no queden pegados a los bordes.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
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
      ),
    );
  }
}
