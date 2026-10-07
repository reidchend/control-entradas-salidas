import 'package:flutter/material.dart';

import '../data/activo.dart';
import '../data/activo_tipo.dart';
import '../data/activos_categoria.dart';
import 'widgets/activo_form.dart';

/// Abre el formulario como pantalla completa en vez de diálogo.
///
/// Va como pantalla y no como diálogo porque seis campos no entran cómodo en un
/// `AlertDialog`: con scroll queda medio formulario a la vista, que es cuando
/// no se sabe qué falta.
///
/// La persistencia queda en manos de quien llama vía [onGuardar] (que devuelve
/// la unidad guardada, placa incluida, para mostrar en el modo "agregar otra").
Future<void> showActivoFormScreen(
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
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ActivoFormScreen(
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
      ),
    ),
  );
}

class ActivoFormScreen extends StatelessWidget {
  const ActivoFormScreen({
    super.key,
    required this.tipos,
    required this.onGuardar,
    this.tipoIdFijo,
    this.unidad,
    this.categorias = const [],
    this.estados = const ['Activo'],
    this.grupos = const [],
    this.modelos = const [],
    this.onCrearTipo,
    this.onCrearEstado,
    this.onExisteUnidad,
    this.ubicacionPreset,
    this.estadoPreset,
    this.ubicacionesSugeridas = const [],
  });

  final List<ActivoTipo> tipos;
  final Future<Activo> Function(Activo activo) onGuardar;
  final int? tipoIdFijo;
  final Activo? unidad;
  final List<ActivosCategoria> categorias;
  final List<String> estados;
  final List<String> grupos;
  final List<String> modelos;
  final Future<int> Function(ActivoTipo tipo)? onCrearTipo;
  final Future<String> Function(String nombre)? onCrearEstado;
  final Future<bool> Function(int tipoId, String ubicacion)? onExisteUnidad;
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
      ),
    );
  }
}
