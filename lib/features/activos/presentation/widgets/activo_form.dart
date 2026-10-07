import 'package:flutter/material.dart';

import '../../data/activo.dart';
import '../../data/activo_tipo.dart';
import '../../data/activos_categoria.dart';
import '../dialogs/tipo_dialog.dart';
import 'activo_form_campos.dart';
import 'opciones_field.dart';
import 'tipo_selector_field.dart';

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
/// que uno quede viejo sin que se note. Quien lo usa se encarga de persistir a
/// través de [onGuardar] (que devuelve la unidad guardada, placa incluida) y de
/// cerrarse con [onCerrar]; el formulario decide si quedarse abierto en modo
/// "guardar y agregar otra".
class ActivoForm extends StatefulWidget {
  const ActivoForm({
    super.key,
    required this.tipos,
    required this.onGuardar,
    required this.onCerrar,
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

  /// Persiste la unidad (alta o edición) y devuelve el [Activo] guardado, para
  /// que el modo "agregar otra" pueda mostrar la placa recién emitida. Un
  /// `await` acá deja el botón bloqueado; ante error debe lanzar excepción.
  final Future<Activo> Function(Activo activo) onGuardar;

  /// Cierra el host (pantalla o diálogo) después de guardar o cancelar.
  final VoidCallback onCerrar;

  /// Cuando viene seteado el tipo no es editable (agregar a un tipo concreto
  /// desde su detalle).
  final int? tipoIdFijo;
  final Activo? unidad;
  final List<ActivosCategoria> categorias;

  /// Estados del catálogo. El estado actual de una unidad que no esté en la
  /// lista se ofrece igual, para no resetear a 'Activo' en silencio.
  final List<String> estados;

  /// Grupos y modelos existentes para sugerir al crear un tipo desde el alta
  /// de unidad (mismo listado que se muestra en el diálogo del catálogo).
  final List<String> grupos;
  final List<String> modelos;
  final Future<int> Function(ActivoTipo tipo)? onCrearTipo;

  /// Da de alta un estado en el catálogo (devuelve el nombre canónico).
  final Future<String> Function(String nombre)? onCrearEstado;

  /// ¿Ya existe una unidad activa de este tipo en una ubicación? Solo se
  /// consulta al buscar un posible duplicado en el alta.
  final Future<bool> Function(int tipoId, String ubicacion)? onExisteUnidad;
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

  /// Estados del catálogo; los recién creados se agregan acá.
  late final List<String> _estados = [...widget.estados];

  /// Filtro opcional por categoría para acotar la lista de tipos al elegir.
  int? _categoriaFiltro;

  late final TextEditingController _tipoCtrl;
  late final TextEditingController _ubicacionCtrl;
  late final TextEditingController _valorCtrl;
  late final TextEditingController _fechaCtrl;
  late final TextEditingController _obsCtrl;

  late String _estado;
  String? _errorTipo;
  bool _guardando = false;
  bool _agregarOtro = false;

  /// Cuando el usuario confirma un posible duplicado, no se vuelve a preguntar
  /// por la misma pareja tipo+ubicación dentro de la sesión (alta en serie).
  final Set<String> _duplicadosAceptados = {};

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
    if (_estado.isEmpty) {
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

  /// Tipos que el selector puede mostrar, acotados por el filtro de categoría.
  List<ActivoTipo> get _tiposVisibles {
    final f = _categoriaFiltro;
    if (f == null) return _tipos;
    return [
      for (final t in _tipos)
        if (t.categoriaId == f) t
    ];
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
    final nuevo = await showTipoDialog(
      context,
      categorias: widget.categorias,
      grupos: widget.grupos,
      modelos: widget.modelos,
    );
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
    setState(() => _guardando = true);
    try {
      var tipoId = _selected;
      if (tipoId == null || tipoId <= 0) {
        final nuevo = _nuevo;
        if (nuevo == null || widget.onCrearTipo == null) {
          setState(() {
            _guardando = false;
            _errorTipo = 'Selecciona o creá un tipo';
          });
          return;
        }
        try {
          tipoId = await widget.onCrearTipo!(nuevo);
        } catch (e) {
          setState(() {
            _guardando = false;
            _errorTipo = 'No se pudo crear el tipo';
          });
          return;
        }
        if (!mounted) return;
      }

      final ubi = _blanco(_ubicacionCtrl.text);

      // Advertencia (no bloqueo) de que esa unidad ya existe en la ubicación:
      // evita registrar dos veces la misma por accidente.
      if (widget.unidad == null &&
          ubi != null &&
          widget.onExisteUnidad != null) {
        final key = '$tipoId|$ubi';
        if (!_duplicadosAceptados.contains(key)) {
          final yaExiste = await widget.onExisteUnidad!(tipoId, ubi);
          if (!mounted) {
            setState(() => _guardando = false);
            return;
          }
          if (yaExiste) {
            final ok = await _confirmarDuplicado(ubi);
            if (!mounted) {
              setState(() => _guardando = false);
              return;
            }
            if (ok != true) {
              setState(() => _guardando = false);
              return;
            }
            _duplicadosAceptados.add(key);
          }
        }
      }
      if (!mounted) return;

      final guardado = await widget.onGuardar(
        Activo(
          id: widget.unidad?.id ?? 0,
          tipoId: tipoId,
          ubicacion: ubi,
          estado: _estado,
          valor: double.tryParse(_valorCtrl.text.trim()) ?? 0,
          fecha: _blanco(_fechaCtrl.text),
          observaciones: _blanco(_obsCtrl.text),
          activo: widget.unidad?.activo ?? true,
        ),
      );
      if (!mounted) return;

      if (widget.unidad == null && _agregarOtro) {
        final codigo = guardado.codigo;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(codigo == null ? 'Unidad guardada' : 'Guardada: $codigo'),
          duration: const Duration(seconds: 3),
        ));
        return;
      }
      widget.onCerrar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      // Si `onCerrar` cerró el host desmonta el formulario: `mounted` ya es
      // falso y el `setState` se omite.
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<bool?> _confirmarDuplicado(String ubicacion) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ya existe en esta ubicación'),
        content: Text(
          'Ya hay una unidad de este tipo en «$ubicacion».\n\n'
          '¿Agregar de todos modos? (Útil si son varias iguales)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agregar de todos modos'),
          ),
        ],
      ),
    );
  }

  Future<void> _crearEstado() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo estado'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del estado'),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.trim().isEmpty || !mounted) return;
    try {
      final creado = await widget.onCrearEstado!(nombre);
      if (!mounted) return;
      setState(() {
        if (!_estados.contains(creado)) _estados.add(creado);
        _estado = creado;
      });
    } catch (e) {
      if (mounted) _snack('No se pudo crear el estado: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
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
        final filtroCategoria = _campoCategoriaFiltro();
        final campos = <Widget>[
          if (filtroCategoria != null) filtroCategoria,
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
                lote: widget.unidad == null,
                agregarOtro: _agregarOtro,
                onToggleAgregarOtro: (v) => setState(() => _agregarOtro = v ?? false),
                onCancelar: widget.onCerrar,
                onGuardar: _guardar,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _campoCategoriaFiltro() {
    if (widget.tipoIdFijo != null || widget.categorias.isEmpty) return null;
    return _campo(
      DropdownButtonFormField<int?>(
        initialValue: _categoriaFiltro,
        decoration: const InputDecoration(
          labelText: 'Categoría',
          helperText: 'Acota los tipos para elegir',
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
          for (final c in widget.categorias)
            DropdownMenuItem(value: c.id, child: Text(c.nombre)),
        ],
        onChanged: (v) => setState(() {
          _categoriaFiltro = v;
          _selected = null;
          _tipoCtrl.clear();
        }),
      ),
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
        tipos: _tiposVisibles,
        onSelected: _elegirTipo,
        onCrearNuevo: widget.onCrearTipo == null ? null : _elegirNuevoTipo,
        errorText: _errorTipo,
      ),
    );
  }

  Widget _campoEstado() {
    final estados = List<String>.from(_estados);
    // Si la unidad tiene un estado que ya no está en el catálogo de la app, se
    // ofrece igual en la lista: editar no debe resetear a 'Activo' en silencio.
    if (!estados.contains(_estado)) estados.add(_estado);
    return _campo(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _estado,
            decoration: const InputDecoration(labelText: 'Estado'),
            items: [
              for (final s in estados)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _estado = v ?? _estado),
          ),
          if (widget.onCrearEstado != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.add, size: 16),
                label:
                    const Text('Crear estado', style: TextStyle(fontSize: 12)),
                onPressed: _crearEstado,
              ),
            ),
        ],
      ),
    );
  }

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
        ActivoCampoFecha(
          controller: _fechaCtrl,
          label: 'Fecha',
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
