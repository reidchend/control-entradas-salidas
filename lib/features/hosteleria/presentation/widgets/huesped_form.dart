import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../forms/huesped_draft.dart';

/// Formulario reutilizable de datos de huésped (titular o acompañante).
///
/// Escribe directamente sobre [draft]; el llamador solo necesita conservar la
/// referencia y leer el draft al guardar. [onChanged] permite reconstruir el
/// contenedor (p. ej. para refrescar contadores de capacidad).
///
/// Al presionar Enter en cualquier campo se mueve el foco al siguiente,
/// incluidos los selectores de documento/estado civil y la fecha de nacimiento.
class HuespedForm extends StatefulWidget {
  const HuespedForm({
    super.key,
    required this.draft,
    this.onChanged,
    this.autofocus = false,
    this.mostrarDocumento = true,
  });

  final HuespedDraft draft;
  final VoidCallback? onChanged;
  final bool autofocus;

  /// Si es `false`, oculta los campos tipo/número de documento. Se usa cuando
  /// el documento ya se captura en un buscador externo (check-in directo).
  final bool mostrarDocumento;

  @override
  State<HuespedForm> createState() => _HuespedFormState();
}

class _HuespedFormState extends State<HuespedForm> {
  late final TextEditingController _nombre;
  late final TextEditingController _apellido;
  late final TextEditingController _documento;
  late final TextEditingController _nacionalidad;
  late final TextEditingController _profesion;
  late final TextEditingController _procedencia;
  late final TextEditingController _destino;
  late final TextEditingController _telefono;
  late final TextEditingController _correo;
  late final TextEditingController _notas;

  // Focos en el orden en que se recorren los campos con Enter.
  final _fNombre = FocusNode();
  final _fApellido = FocusNode();
  final _fTipoDocumento = FocusNode();
  final _fDocumento = FocusNode();
  final _fFecha = FocusNode();
  final _fEstadoCivil = FocusNode();
  final _fNacionalidad = FocusNode();
  final _fProfesion = FocusNode();
  final _fProcedencia = FocusNode();
  final _fDestino = FocusNode();
  final _fTelefono = FocusNode();
  final _fCorreo = FocusNode();
  final _fNotas = FocusNode();

  late final List<FocusNode> _todosLosFocos;
  late final List<FocusNode> _ordenConDocumento;
  late final List<FocusNode> _ordenSinDocumento;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _nombre = TextEditingController(text: d.nombre);
    _apellido = TextEditingController(text: d.apellido);
    _documento = TextEditingController(text: d.numeroDocumento);
    _nacionalidad = TextEditingController(text: d.nacionalidad);
    _profesion = TextEditingController(text: d.profesion);
    _procedencia = TextEditingController(text: d.procedencia);
    _destino = TextEditingController(text: d.destino);
    _telefono = TextEditingController(text: d.telefono);
    _correo = TextEditingController(text: d.correo);
    _notas = TextEditingController(text: d.notas);

    _todosLosFocos = [
      _fNombre,
      _fApellido,
      _fTipoDocumento,
      _fDocumento,
      _fFecha,
      _fEstadoCivil,
      _fNacionalidad,
      _fProfesion,
      _fProcedencia,
      _fDestino,
      _fTelefono,
      _fCorreo,
      _fNotas,
    ];
    _ordenConDocumento = List.unmodifiable(_todosLosFocos);
    _ordenSinDocumento = List.unmodifiable([
      _fNombre,
      _fApellido,
      _fFecha,
      _fEstadoCivil,
      _fNacionalidad,
      _fProfesion,
      _fProcedencia,
      _fDestino,
      _fTelefono,
      _fCorreo,
      _fNotas,
    ]);
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _apellido,
      _documento,
      _nacionalidad,
      _profesion,
      _procedencia,
      _destino,
      _telefono,
      _correo,
      _notas,
    ]) {
      c.dispose();
    }
    for (final f in _todosLosFocos) {
      f.dispose();
    }
    super.dispose();
  }

  void _cambio() => widget.onChanged?.call();

  List<FocusNode> get _orden =>
      widget.mostrarDocumento ? _ordenConDocumento : _ordenSinDocumento;

  /// Pasa el foco al siguiente campo; en el último lo libera.
  void _siguiente(FocusNode actual) {
    final orden = _orden;
    final i = orden.indexOf(actual);
    if (i >= 0 && i + 1 < orden.length) {
      orden[i + 1].requestFocus();
    } else {
      actual.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nombre,
                focusNode: _fNombre,
                autofocus: widget.autofocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  d.nombre = v;
                  _cambio();
                },
                onSubmitted: (_) => _siguiente(_fNombre),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _apellido,
                focusNode: _fApellido,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Apellido *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  d.apellido = v;
                  _cambio();
                },
                onSubmitted: (_) => _siguiente(_fApellido),
              ),
            ),
          ],
        ),
        if (widget.mostrarDocumento) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  focusNode: _fTipoDocumento,
                  initialValue:
                      DocumentoTipo.opciones.contains(d.tipoDocumento)
                          ? d.tipoDocumento
                          : DocumentoTipo.cedula,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de documento',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in DocumentoTipo.opciones)
                      DropdownMenuItem(
                          value: t, child: Text(DocumentoTipo.label(t))),
                  ],
                  onChanged: (v) {
                    d.tipoDocumento = v ?? DocumentoTipo.cedula;
                    _cambio();
                    _siguiente(_fTipoDocumento);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _documento,
                  focusNode: _fDocumento,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'N° documento',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    d.numeroDocumento = v;
                    _cambio();
                  },
                  onSubmitted: (_) => _siguiente(_fDocumento),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _fechaNacimiento(context, d)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                focusNode: _fEstadoCivil,
                initialValue: EstadoCivil.opciones.contains(d.estadoCivil)
                    ? d.estadoCivil
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Estado civil',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in EstadoCivil.opciones)
                    DropdownMenuItem(value: e, child: Text(e)),
                ],
                onChanged: (v) {
                  d.estadoCivil = v;
                  _cambio();
                  _siguiente(_fEstadoCivil);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _texto(_nacionalidad, _fNacionalidad, 'Nacionalidad', d,
                  (v) => d.nacionalidad = v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _texto(_profesion, _fProfesion, 'Profesión u oficio', d,
                  (v) => d.profesion = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _texto(_procedencia, _fProcedencia, 'Procedencia', d,
                  (v) => d.procedencia = v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _texto(
                  _destino, _fDestino, 'Destino', d, (v) => d.destino = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _texto(
                  _telefono, _fTelefono, 'Teléfono', d, (v) => d.telefono = v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _texto(
                  _correo, _fCorreo, 'Correo', d, (v) => d.correo = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notas,
          focusNode: _fNotas,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Notas (opcional)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            d.notas = v;
            _cambio();
          },
          onSubmitted: (_) => _siguiente(_fNotas),
        ),
      ],
    );
  }

  Widget _texto(
    TextEditingController c,
    FocusNode foco,
    String label,
    HuespedDraft d,
    void Function(String) set,
  ) {
    return TextField(
      controller: c,
      focusNode: foco,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        set(v);
        _cambio();
      },
      onSubmitted: (_) => _siguiente(foco),
    );
  }

  Widget _fechaNacimiento(BuildContext context, HuespedDraft d) {
    final f = d.fechaNacimiento;
    final txt = f == null
        ? 'Fecha de nacimiento'
        : '${f.day.toString().padLeft(2, '0')}/'
            '${f.month.toString().padLeft(2, '0')}/${f.year}';
    return Focus(
      focusNode: _fFecha,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _elegirFecha(context, d);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: () => _elegirFecha(context, d),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Fecha de nacimiento',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(txt, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Future<void> _elegirFecha(BuildContext context, HuespedDraft d) async {
    final f = d.fechaNacimiento;
    final hoy = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: f ?? DateTime(hoy.year - 30),
      firstDate: DateTime(1900),
      lastDate: hoy,
    );
    if (picked == null || !mounted) return;
    setState(() => d.fechaNacimiento = picked);
    _cambio();
    _siguiente(_fFecha);
  }
}
