import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../forms/huesped_draft.dart';

/// Formulario reutilizable de datos de huésped (titular o acompañante).
///
/// Escribe directamente sobre [draft]; el llamador solo necesita conservar la
/// referencia y leer el draft al guardar. [onChanged] permite reconstruir el
/// contenedor (p. ej. para refrescar contadores de capacidad).
class HuespedForm extends StatefulWidget {
  const HuespedForm({
    super.key,
    required this.draft,
    this.onChanged,
    this.autofocus = false,
  });

  final HuespedDraft draft;
  final VoidCallback? onChanged;
  final bool autofocus;

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
    super.dispose();
  }

  void _cambio() => widget.onChanged?.call();

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
                autofocus: widget.autofocus,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  d.nombre = v;
                  _cambio();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _apellido,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Apellido *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  d.apellido = v;
                  _cambio();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: DocumentoTipo.opciones.contains(d.tipoDocumento)
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
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _documento,
                decoration: const InputDecoration(
                  labelText: 'N° documento',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  d.numeroDocumento = v;
                  _cambio();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _fechaNacimiento(context, d)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
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
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _texto(_nacionalidad, 'Nacionalidad', d,
                (v) => d.nacionalidad = v)),
            const SizedBox(width: 8),
            Expanded(child: _texto(_profesion, 'Profesión u oficio', d,
                (v) => d.profesion = v)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child:
                    _texto(_procedencia, 'Procedencia', d, (v) => d.procedencia = v)),
            const SizedBox(width: 8),
            Expanded(
                child: _texto(_destino, 'Destino', d, (v) => d.destino = v)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _texto(_telefono, 'Teléfono', d, (v) => d.telefono = v)),
            const SizedBox(width: 8),
            Expanded(
                child: _texto(_correo, 'Correo', d, (v) => d.correo = v)),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notas,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notas (opcional)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            d.notas = v;
            _cambio();
          },
        ),
      ],
    );
  }

  Widget _texto(
    TextEditingController c,
    String label,
    HuespedDraft d,
    void Function(String) set,
  ) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        set(v);
        _cambio();
      },
    );
  }

  Widget _fechaNacimiento(BuildContext context, HuespedDraft d) {
    final f = d.fechaNacimiento;
    final txt = f == null
        ? 'Fecha de nacimiento'
        : '${f.day.toString().padLeft(2, '0')}/'
            '${f.month.toString().padLeft(2, '0')}/${f.year}';
    return InkWell(
      onTap: () async {
        final hoy = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: f ?? DateTime(hoy.year - 30),
          firstDate: DateTime(1900),
          lastDate: hoy,
        );
        if (picked != null) {
          setState(() => d.fechaNacimiento = picked);
          _cambio();
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fecha de nacimiento',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(txt, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
