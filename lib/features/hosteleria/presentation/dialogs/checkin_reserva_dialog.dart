import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../data/hosteleria_repository.dart';
import '../forms/huesped_draft.dart';
import 'acompanante_dialog.dart';
import 'vehiculo_dialog.dart';
import '../widgets/huesped_form.dart';

/// Modo de operación del diálogo de estancia.
enum CheckinModo {
  /// Crear una reserva a futuro (sin ocupar la habitación).
  reserva,

  /// Check-in directo (sin reserva previa): ocupa de inmediato.
  checkinDirecto,

  /// Check-in a partir de una reserva existente.
  checkinDesdeReserva,
}

/// Diálogo orquestador de reserva/check-in con datos completos del titular,
/// acompañantes (limitados por la capacidad del tipo de habitación) y
/// vehículos. Retorna `true` si se guardó.
Future<bool> showCheckinReservaDialog(
  BuildContext context, {
  required HosteleriaRepository repo,
  required List<Habitacion> habitaciones,
  CheckinModo modo = CheckinModo.reserva,
  Habitacion? habitacionFija,
  HostelReserva? reservaExistente,
  HostelHuesped? titularExistente,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _CheckinReservaDialog(
      repo: repo,
      habitaciones: habitaciones,
      modo: modo,
      habitacionFija: habitacionFija,
      reservaExistente: reservaExistente,
      titularExistente: titularExistente,
    ),
  );
  return ok ?? false;
}

class _CheckinReservaDialog extends StatefulWidget {
  const _CheckinReservaDialog({
    required this.repo,
    required this.habitaciones,
    required this.modo,
    this.habitacionFija,
    this.reservaExistente,
    this.titularExistente,
  });

  final HosteleriaRepository repo;
  final List<Habitacion> habitaciones;
  final CheckinModo modo;
  final Habitacion? habitacionFija;
  final HostelReserva? reservaExistente;
  final HostelHuesped? titularExistente;

  @override
  State<_CheckinReservaDialog> createState() => _CheckinReservaDialogState();
}

class _CheckinReservaDialogState extends State<_CheckinReservaDialog> {
  Habitacion? _habitacion;
  HuespedDraft _titular = HuespedDraft();
  final List<HuespedDraft> _acompanantes = [];
  final List<HostelVehiculoInput> _vehiculos = [];
  late DateTime _ingreso;
  late DateTime _salida;
  ModalidadEstancia _modalidad = ModalidadEstancia.noche;
  int _bloqueHoras = 3;
  bool _cargado = false;
  bool _guardando = false;
  String _error = '';

  bool get _ocupaAhora => widget.modo != CheckinModo.reserva;

  int get _capacidad => _habitacion?.maxPersonas ?? 1;
  int get _personas => 1 + _acompanantes.length;
  bool get _puedeAgregar => _personas < _capacidad;

  @override
  void initState() {
    super.initState();
    _ingreso = DateTime.now();
    _salida = DateTime.now().add(const Duration(days: 1));
    _init();
  }

  Future<void> _init() async {
    final r = widget.reservaExistente;
    if (widget.habitacionFija != null) {
      _habitacion = widget.habitacionFija;
    } else if (r != null) {
      final match =
          widget.habitaciones.where((h) => h.id == r.habitacionId).toList();
      _habitacion = match.isEmpty ? null : match.first;
    }
    if (r != null) {
      _ingreso = r.fechaIngreso;
      _salida = r.fechaSalida;
      _modalidad = r.modalidad;
      _bloqueHoras = r.bloqueHoras ?? 3;
      try {
        var huesped = widget.titularExistente;
        huesped ??= await widget.repo.getHuespedById(r.huespedId);
        if (huesped != null) _titular = HuespedDraft.desde(huesped);
        final personas = await widget.repo.getPersonasDeReserva(r.id);
        for (final p in personas) {
          if (p.rol == 'titular') continue;
          final h = p.huesped;
          if (h != null) _acompanantes.add(HuespedDraft.desde(h));
        }
        final vehiculos = await widget.repo.getVehiculosDeReserva(r.id);
        _vehiculos.addAll(vehiculos
            .map((v) => HostelVehiculoInput(placa: v.placa, modelo: v.modelo)));
      } catch (e) {
        _error = 'No se pudieron cargar los datos: $e';
      }
    }
    if (!mounted) return;
    setState(() => _cargado = true);
  }

  Future<void> _agregarAcompanante() async {
    if (!_puedeAgregar) return;
    final d = await showAcompananteDialog(context);
    if (d != null) setState(() => _acompanantes.add(d));
  }

  Future<void> _editarAcompanante(int i) async {
    final d = await showAcompananteDialog(context, inicial: _acompanantes[i]);
    if (d != null) setState(() => _acompanantes[i] = d);
  }

  Future<void> _agregarVehiculo() async {
    final v = await showVehiculoDialog(context);
    if (v != null) setState(() => _vehiculos.add(v));
  }

  Future<void> _editarVehiculo(int i) async {
    final v = await showVehiculoDialog(context, inicial: _vehiculos[i]);
    if (v != null) setState(() => _vehiculos[i] = v);
  }

  Future<void> _fecha(bool ingreso) async {
    final base = ingreso ? _ingreso : _salida;
    final primera = ingreso ? DateTime.now() : _ingreso.add(const Duration(days: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base.isAfter(primera) ? base : primera,
      firstDate: ingreso ? DateTime.now() : primera,
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (d == null) return;
    setState(() {
      if (ingreso) {
        _ingreso = d;
        if (_salida.isBefore(d.add(const Duration(days: 1)))) {
          _salida = d.add(const Duration(days: 1));
        }
      } else {
        _salida = d;
      }
    });
  }

  Future<HostelHuesped> _guardar(HuespedDraft d) => widget.repo.saveHuesped(
        id: d.huespedId,
        nombre: d.nombre,
        apellido: d.apellido,
        tipoDocumento: d.tipoDocumento,
        numeroDocumento: d.numeroDocumento,
        fechaNacimiento: d.fechaNacimiento,
        estadoCivil: d.estadoCivil,
        nacionalidad: d.nacionalidad,
        profesion: d.profesion,
        procedencia: d.procedencia,
        destino: d.destino,
        telefono: d.telefono,
        correo: d.correo,
        notas: d.notas,
      );

  Future<void> _confirmar() async {
    setState(() => _error = '');
    if (_habitacion == null) {
      setState(() => _error = 'Seleccione una habitación.');
      return;
    }
    final errTitular = _titular.errorValidacion;
    if (errTitular != null) {
      setState(() => _error = 'Titular: $errTitular');
      return;
    }
    for (var i = 0; i < _acompanantes.length; i++) {
      final err = _acompanantes[i].errorValidacion;
      if (err != null) {
        setState(() => _error = 'Acompañante ${i + 1}: $err');
        return;
      }
    }
    if (_personas > _capacidad) {
      setState(() => _error =
          'La habitación permite $_capacidad persona(s) como máximo.');
      return;
    }
    setState(() => _guardando = true);
    try {
      final titular = await _guardar(_titular);
      final acompanantes = <HostelHuesped>[];
      for (final d in _acompanantes) {
        acompanantes.add(await _guardar(d));
      }
      final r = widget.reservaExistente;
      final esHoras = _modalidad == ModalidadEstancia.horas;
      if (widget.modo == CheckinModo.checkinDesdeReserva && r != null) {
        await widget.repo.realizarCheckInCompleto(
          reservaId: r.id,
          titular: titular,
          acompanantes: acompanantes,
          vehiculos: _vehiculos,
          capacidadMax: _capacidad,
          modalidad: _modalidad,
          bloqueHoras: esHoras ? _bloqueHoras : null,
        );
      } else {
        await widget.repo.crearEstancia(
          habitacionId: _habitacion!.id,
          fechaIngreso: _ingreso,
          fechaSalida: esHoras ? _ingreso : _salida,
          titular: titular,
          acompanantes: acompanantes,
          vehiculos: _vehiculos,
          capacidadMax: _capacidad,
          ocupar: _ocupaAhora,
          modalidad: _modalidad,
          bloqueHoras: esHoras ? _bloqueHoras : null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'Error al guardar: $e';
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get _titulo => switch (widget.modo) {
        CheckinModo.reserva => 'Nueva reserva',
        CheckinModo.checkinDirecto => 'Check-in directo',
        CheckinModo.checkinDesdeReserva => 'Check-in',
      };

  String get _accion => switch (widget.modo) {
        CheckinModo.reserva => 'Reservar',
        _ => 'Registrar check-in',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_titulo),
      content: SizedBox(
        width: 560,
        child: !_cargado
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _habitacionSelector(),
                    const SizedBox(height: 12),
                    _modalidadSelector(),
                    const SizedBox(height: 12),
                    if (_modalidad == ModalidadEstancia.noche)
                      Row(
                        children: [
                          Expanded(
                              child: _fechaBoton(
                                  'Entrada', _ingreso, () => _fecha(true))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _fechaBoton(
                                  'Salida', _salida, () => _fecha(false))),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                              child: _fechaBoton(
                                  'Entrada', _ingreso, () => _fecha(true))),
                          const SizedBox(width: 8),
                          Expanded(child: _bloqueSelector()),
                        ],
                      ),
                    const SizedBox(height: 16),
                    const _Seccion(titulo: 'Datos del titular'),
                    const SizedBox(height: 8),
                    HuespedForm(
                      draft: _titular,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _seccionAcompanantes(),
                    const SizedBox(height: 16),
                    _seccionVehiculos(),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando || !_cargado ? null : _confirmar,
          child: Text(_guardando ? 'Guardando…' : _accion),
        ),
      ],
    );
  }

  Widget _habitacionSelector() {
    final fija = widget.habitacionFija ?? widget.reservaExistente;
    if (fija != null) {
      final h = _habitacion;
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Habitación',
          border: OutlineInputBorder(),
        ),
        child: Text(h == null
            ? 'Habitación'
            : '${h.numero}${h.tipo != null ? ' · ${h.tipo}' : ''} '
                '(cap. ${h.maxPersonas})'),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: _habitacion?.id,
      decoration: const InputDecoration(
        labelText: 'Habitación',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final h in widget.habitaciones)
          DropdownMenuItem(
            value: h.id,
            child: Text('${h.numero} · ${h.tipo ?? ''} (cap. ${h.maxPersonas})'),
          ),
      ],
      onChanged: (id) => setState(() {
        _habitacion = widget.habitaciones.firstWhere((h) => h.id == id);
      }),
    );
  }

  Widget _fechaBoton(String label, DateTime fecha, VoidCallback onTap) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text('$label: ${_fmt(fecha)}'),
      onPressed: _guardando ? null : onTap,
    );
  }

  Widget _modalidadSelector() {
    return SegmentedButton<ModalidadEstancia>(
      segments: const [
        ButtonSegment(
          value: ModalidadEstancia.noche,
          label: Text('Por noche'),
          icon: Icon(Icons.nights_stay_outlined),
        ),
        ButtonSegment(
          value: ModalidadEstancia.horas,
          label: Text('Por horas (OP)'),
          icon: Icon(Icons.timer_outlined),
        ),
      ],
      selected: {_modalidad},
      onSelectionChanged: (s) {
        if (_guardando) return;
        setState(() => _modalidad = s.first);
      },
    );
  }

  Widget _bloqueSelector() {
    const opciones = [1, 2, 3, 4, 6];
    final valor = opciones.contains(_bloqueHoras) ? _bloqueHoras : 3;
    return DropdownButtonFormField<int>(
      initialValue: valor,
      decoration: const InputDecoration(
        labelText: 'Bloque',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 1, child: Text('1 hora')),
        DropdownMenuItem(value: 2, child: Text('2 horas')),
        DropdownMenuItem(value: 3, child: Text('3 horas (OP)')),
        DropdownMenuItem(value: 4, child: Text('4 horas')),
        DropdownMenuItem(value: 6, child: Text('6 horas')),
      ],
      onChanged: _guardando
          ? null
          : (v) => setState(() => _bloqueHoras = v ?? 3),
    );
  }

  Widget _seccionAcompanantes() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Seccion(titulo: 'Acompañantes ($_personas/$_capacidad)'),
            const Spacer(),
            TextButton.icon(
              onPressed:
                  _guardando || !_puedeAgregar ? null : _agregarAcompanante,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
        if (_acompanantes.isEmpty)
          Text('Sin acompañantes.',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
        for (var i = 0; i < _acompanantes.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(_acompanantes[i].etiqueta),
            subtitle: _acompanantes[i].numeroDocumento.isEmpty
                ? null
                : Text(_acompanantes[i].numeroDocumento),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed:
                      _guardando ? null : () => _editarAcompanante(i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _guardando
                      ? null
                      : () => setState(() => _acompanantes.removeAt(i)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _seccionVehiculos() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _Seccion(titulo: 'Vehículos'),
            const Spacer(),
            TextButton.icon(
              onPressed: _guardando ? null : _agregarVehiculo,
              icon: const Icon(Icons.directions_car, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
        if (_vehiculos.isEmpty)
          Text('Sin vehículos.',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
        for (var i = 0; i < _vehiculos.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.directions_car_outlined),
            title: Text(_vehiculos[i].placa),
            subtitle: (_vehiculos[i].modelo ?? '').isEmpty
                ? null
                : Text(_vehiculos[i].modelo!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: _guardando ? null : () => _editarVehiculo(i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _guardando
                      ? null
                      : () => setState(() => _vehiculos.removeAt(i)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo});
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Text(
      titulo,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
