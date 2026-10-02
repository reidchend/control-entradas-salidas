import 'package:flutter/material.dart';

import '../../data/activo.dart';
import '../../data/activo_tipo.dart';
import '../../data/activos_categoria.dart';
import '../dialogs/tipo_dialog.dart';
import 'activo_form_campos.dart';
import 'opciones_field.dart';
import 'tipo_selector_field.dart';

const _estados = [
  'Activo',
  'Mantenimiento',
  'Baja',
  'Reservado',
  'Traslado',
];

/// Ancho a partir del cual los campos pasan a dos columnas.
///
/// El formulario viene de un `AlertDialog`, donde seis campos en una columna no
/// entran sin hacer scroll. Como pantalla tiene el ancho completo, así que se
/// aprovecha en vez de dejar la mitad vacía.
const _anchoDosColumnas = 720.0;

/// Formulario de alta y edición de una unidad de activo.
///
/// Va aparte de la pantalla y del diálogo a propósito: los dos necesitan los
/// mismos campos y las mismas reglas, y mantener una sola implementación evita
/// que uno quede viejo sin que se note. Quien lo usa decide qué hacer con el
/// [Activo] armado a través de [onGuardar].
class ActivoForm extends StatefulWidget {
  const ActivoForm({
    super.key,
    required this.tipos,
    required this.onGuardar,
    required this.onCancelar,
    this.tipoIdFijo,
    this.unidad,
    this.categorias = const [],
    this.onCrearTipo,
    this.ubicacionPreset,
    this.estadoPreset,
    this.ubicacionesSugeridas = const [],
  });

  final List<ActivoTipo> tipos;

  /// Recibe el activo ya validado. Un `await` en esta etapa deja el botón
  /// bloqueado, así que sirve tanto para cerrar la pantalla como para persistir.
  final Future<void> Function(Activo activo) onGuardar;

  final VoidCallback onCancelar;

  /// Cuando viene seteado el tipo no es editable (agregar a un tipo concreto
  /// desde su detalle).
  final int? tipoIdFijo;
  final Activo? unidad;
  final List<ActivosCategoria> categorias;
  final Future<int> Function(ActivoTipo tipo)? onCrearTipo;
  final String? ubicacionPreset;
  final String? estadoPreset;
  final List<String> ubicacionesSugeridas;

  @override
  State<ActivoForm> createState() => _ActivoFormState();
}

class _ActivoFormState extends State<ActivoForm> {
  /// Copia local: se le agregan los tipos que ya no vinieron del catálogo, para
  /// no dejar sin poder editar una unidad cuyo tipo quedó borrado.
  late final List<ActivoTipo> _tipos = [...widget.tipos];

  late int? _selected = widget.tipoIdFijo ?? widget.unidad?.tipoId;

  /// Tipo recién creado y todavía no persistido: se guarda junto con la unidad.
  ActivoTipo? _nuevo;

  late final TextEditingController _tipoCtrl;
  late final TextEditingController _ubicacionCtrl;
  late final TextEditingController _valorCtrl;
  late final TextEditingController _fechaCtrl;
  late final TextEditingController _obsCtrl;

  late String _estado;
  String? _errorTipo;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final unidad = widget.unidad;
    final tipoActual = unidad?.tipoId;
    if (tipoActual != null && !_tipos.any((t) => t.id == tipoActual)) {
      _tipos.insert(
        0,
        ActivoTipo(
          id: tipoActual,
          nombre: (unidad?.tipoNombre ?? '').trim().isNotEmpty
              ? unidad!.tipoNombre!.trim()
              : 'Tipo $tipoActual',
          grupo: unidad?.grupo,
          modelo: unidad?.modelo,
          categoriaId: unidad?.categoriaId,
        ),
      );
    }
    _tipoCtrl = TextEditingController(text: _textoTipoActual);
    // Si la persona edita el texto a mano, lo que queda escrito ya no es el tipo
    // elegido: se suelta la selección para no guardar una unidad con el texto
    // de un tipo y el id de otro.
    _tipoCtrl.addListener(_alEditarTipo);
    _ubicacionCtrl = TextEditingController(
      text: unidad?.ubicacion?.trim() ?? widget.ubicacionPreset ?? '',
    );
    _estado = (unidad?.estado ?? widget.estadoPreset ?? 'Activo').trim();
    if (_estado.isEmpty || !_estados.contains(_estado)) {
      _estado = 'Activo';
    }
    _valorCtrl = TextEditingController(
      text: unidad != null && unidad.valor > 0
          ? unidad.valor.toStringAsFixed(2)
          : '',
    );
    _fechaCtrl = TextEditingController(text: unidad?.fecha ?? '');
    _obsCtrl = TextEditingController(text: unidad?.observaciones?.trim() ?? '');
  }

  @override
  void dispose() {
    _tipoCtrl
      ..removeListener(_alEditarTipo)
      ..dispose();
    _ubicacionCtrl.dispose();
    _valorCtrl.dispose();
    _fechaCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  ActivoTipo? get _tipoSeleccionado {
    final id = _selected;
    if (id == null) return null;
    for (final t in _tipos) {
      if (t.id == id) return t;
    }
    return null;
  }

  String get _textoTipoActual {
    final t = _tipoSeleccionado ?? _nuevo;
    // Sin tipo todavía el campo arranca vacío: es el caso normal al agregar.
    return t == null ? '' : textoTipo(t);
  }

  /// Se dispara cada vez que cambia el texto del campo de tipo.
  ///
  /// `TextEditingController.addListener` entrega un `VoidCallback` (sin
  /// argumentos), así que el texto se lee del controller en vez de recibirse.
  void _alEditarTipo() {
    final sel = _tipoSeleccionado;
    final cambio = sel != null && _tipoCtrl.text != textoTipo(sel);
    if (cambio) {
      _selected = null;
      _nuevo = null;
    }
    if (!cambio && _errorTipo == null) return;
    if (mounted) setState(() => _errorTipo = null);
  }

  Future<void> _elegirNuevoTipo() async {
    final nuevo = await showTipoDialog(context, categorias: widget.categorias);
    if (nuevo == null || !mounted) return;
    setState(() {
      _nuevo = nuevo;
      _selected = null;
      _errorTipo = null;
    });
    // Fuera del `setState`: asignar `text` dispara `_alEditarTipo`, que llama
    // `setState` por su cuenta, y anidarlos es frágil.
    _tipoCtrl.text = textoTipo(nuevo);
  }

  void _elegirTipo(ActivoTipo t) => setState(() {
        _nuevo = null;
        _selected = t.id;
        _errorTipo = null;
      });

  Future<void> _guardar() async {
    var tipoId = _selected;
    if (tipoId == null || tipoId <= 0) {
      final nuevo = _nuevo;
      if (nuevo == null || widget.onCrearTipo == null) {
        setState(() => _errorTipo = 'Selecciona o creá un tipo');
        return;
      }
      try {
        tipoId = await widget.onCrearTipo!(nuevo);
      } catch (e) {
        setState(() => _errorTipo = 'No se pudo crear el tipo');
        return;
      }
    }
    if (!mounted) return;
    setState(() => _guardando = true);
    try {
      await widget.onGuardar(
        Activo(
          id: widget.unidad?.id ?? 0,
          tipoId: tipoId,
          ubicacion: _blanco(_ubicacionCtrl.text),
          estado: _estado,
          valor: double.tryParse(_valorCtrl.text.trim()) ?? 0,
          fecha: _blanco(_fechaCtrl.text),
          observaciones: _blanco(_obsCtrl.text),
          activo: widget.unidad?.activo ?? true,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  static String? _blanco(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Widget _campo(Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dosColumnas = constraints.maxWidth >= _anchoDosColumnas;
        final campos = <Widget>[
          _campoTipo(),
          _campoEstado(),
          _campoUbicacion(),
          _campoValor(),
          _campoFecha(),
        ];

        Widget cuerpo;
        if (dosColumnas) {
          cuerpo = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < campos.length; i += 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: campos[i]),
                    const SizedBox(width: 16),
                    Expanded(
                      child: i + 1 < campos.length
                          ? campos[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
            ],
          );
        } else {
          cuerpo = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: campos,
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cuerpo,
              _campoObservaciones(),
              const SizedBox(height: 4),
              ActivoAcciones(
                guardando: _guardando,
                onCancelar: widget.onCancelar,
                onGuardar: _guardar,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _campoTipo() {
    final fijo = widget.tipoIdFijo;
    if (fijo != null) {
      return _campo(
        ActivoFilaTipoFijo(
          nombre: _tipoSeleccionado?.nombre ??
              widget.unidad?.tipoNombre ??
              'Tipo $fijo',
        ),
      );
    }
    return _campo(
      TipoSelectorField(
        controller: _tipoCtrl,
        tipos: _tipos,
        onSelected: _elegirTipo,
        onCrearNuevo: widget.onCrearTipo == null ? null : _elegirNuevoTipo,
        errorText: _errorTipo,
      ),
    );
  }

  Widget _campoEstado() => _campo(
        DropdownButtonFormField<String>(
          initialValue: _estado,
          decoration: const InputDecoration(labelText: 'Estado'),
          items: [
            if (!_estados.contains(_estado))
              DropdownMenuItem(value: _estado, child: Text(_estado)),
            for (final s in _estados)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) => setState(() => _estado = v ?? _estado),
        ),
      );

  Widget _campoUbicacion() => _campo(
        OpcionesField<String>(
          controller: _ubicacionCtrl,
          label: 'Ubicación',
          opciones: widget.ubicacionesSugeridas,
          textoDe: (s) => s,
          icono: Icons.place_outlined,
        ),
      );

  Widget _campoValor() => _campo(
        ActivoCampoTexto(
          controller: _valorCtrl,
          label: 'Valor (Bs)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      );

  Widget _campoFecha() => _campo(
        ActivoCampoTexto(
          controller: _fechaCtrl,
          label: 'Fecha (AAAA-MM-DD)',
          hintText: '2025-01-15',
        ),
      );

  Widget _campoObservaciones() => _campo(
        ActivoCampoTexto(
          controller: _obsCtrl,
          label: 'Observaciones',
          minLines: 3,
          maxLines: 6,
        ),
      );
}
