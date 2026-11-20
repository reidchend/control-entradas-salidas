import 'package:flutter/material.dart';

import '../../../../core/models/hosteleria_models.dart';
import '../../../../core/models/pos_models.dart';
import '../../../../core/theme/app_theme.dart';
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
  bool _buscandoDocumento = false;

  /// `true` si el error actual proviene del buscador de documento y debe
  /// mostrarse junto a ese campo (en vez de junto al botón de confirmar).
  bool _errorCliente = false;

  /// Campo de documento del buscador (solo check-in directo).
  final TextEditingController _docCtrl = TextEditingController();

  /// Tipo de documento seleccionado en el buscador.
  String _tipoDoc = DocumentoTipo.cedula;

  /// `true` cuando ya se buscó el cliente y se puede mostrar el resto del
  /// formulario. En modos con titular/reserva previa arranca en `true`.
  bool _clienteListo = false;

  /// `true` si el documento buscado pertenece a un cliente ya registrado.
  bool _clienteExistente = false;

  /// Fuerza la reconstrucción de `HuespedForm` al reemplazar el draft.
  int _formVersion = 0;

  bool get _ocupaAhora => widget.modo != CheckinModo.reserva;

  int get _capacidad => _habitacion?.maxPersonas ?? 1;
  int get _personas => 1 + _acompanantes.length;
  bool get _puedeAgregar => _personas < _capacidad;

  /// Focus para el campo de documento en check-in directo.
  final FocusNode _docFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ingreso = DateTime.now();
    _salida = DateTime.now().add(const Duration(days: 1));
    _clienteListo = widget.modo != CheckinModo.checkinDirecto ||
        widget.titularExistente != null;
    _clienteExistente = widget.titularExistente != null;
    final t = widget.titularExistente;
    if (t != null) {
      _docCtrl.text = t.documento ?? '';
      _tipoDoc = t.tipoDocumento ?? DocumentoTipo.cedula;
    }
    _init();
    // Si es check-in directo y no hay titular existente, dar foco al documento.
    if (widget.modo == CheckinModo.checkinDirecto &&
        widget.titularExistente == null) {
      Future.delayed(Duration.zero, () => _docFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _docCtrl.dispose();
    _docFocus.dispose();
    super.dispose();
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
        if (huesped != null) {
          _titular = HuespedDraft.desde(huesped);
          _docCtrl.text = huesped.documento ?? '';
          _tipoDoc = huesped.tipoDocumento ?? DocumentoTipo.cedula;
        }
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

  /// Busca un huésped por número de documento en la base de datos.
  Future<void> _buscarHuespedPorDocumento() async {
    final doc = _docCtrl.text.trim();
    if (doc.isEmpty) {
      setState(() {
        _errorCliente = true;
        _error = 'Escriba el número de documento del cliente.';
      });
      _docFocus.requestFocus();
      return;
    }
    setState(() {
      _buscandoDocumento = true;
      _errorCliente = false;
      _error = '';
    });
    try {
      final huesped = await widget.repo.buscarHuespedPorDocumento(doc);
      if (!mounted) return;
      setState(() {
        _buscandoDocumento = false;
        _clienteListo = true;
        _formVersion++;
        if (huesped != null) {
          // Encontrado: precargar todos sus datos.
          _titular = HuespedDraft.desde(huesped);
          _tipoDoc = huesped.tipoDocumento ?? DocumentoTipo.cedula;
          _clienteExistente = true;
        } else {
          // No encontrado: conservar el documento escrito y pedir el resto.
          _titular = HuespedDraft()
            ..tipoDocumento = _tipoDoc
            ..numeroDocumento = doc;
          _clienteExistente = false;
        }
        _docCtrl.text = _titular.numeroDocumento;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscandoDocumento = false;
        _errorCliente = true;
        _error = 'Error al buscar: $e';
      });
    }
  }

  /// Limpia el cliente cargado y vuelve al paso de búsqueda por documento.
  void _limpiarCliente() {
    setState(() {
      _clienteListo = false;
      _clienteExistente = false;
      _titular = HuespedDraft();
      _tipoDoc = DocumentoTipo.cedula;
      _docCtrl.clear();
      _errorCliente = false;
      _error = '';
      _formVersion++;
    });
    _docFocus.requestFocus();
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
    setState(() {
      _error = '';
      _errorCliente = false;
    });
    if (widget.modo == CheckinModo.checkinDirecto && !_clienteListo) {
      setState(
          () => _error = 'Busque o registre al cliente antes de continuar.');
      _docFocus.requestFocus();
      return;
    }
    // El documento del check-in directo vive en el buscador: sincronizarlo.
    if (widget.modo == CheckinModo.checkinDirecto) {
      _titular.numeroDocumento = _docCtrl.text.trim();
      _titular.tipoDocumento = _tipoDoc;
    }
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
    final esDirecto = widget.modo == CheckinModo.checkinDirecto;
    final mostrarFormulario = !esDirecto || _clienteListo;
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
                    if (esDirecto) ...[
                      _resumenHabitacion(),
                      const SizedBox(height: 12),
                      _seccionCliente(),
                    ],
                    if (mostrarFormulario) ...[
                      const SizedBox(height: 16),
                      const _Seccion(titulo: 'Estadía'),
                      const SizedBox(height: 8),
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
                        key: ValueKey(_formVersion),
                        draft: _titular,
                        mostrarDocumento: !esDirecto,
                        autofocus: esDirecto && !_clienteExistente,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      _seccionAcompanantes(),
                      const SizedBox(height: 16),
                      _seccionVehiculos(),
                      if (_error.isNotEmpty && !_errorCliente) ...[
                        const SizedBox(height: 12),
                        SelectableText(_error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                    ] else ...[
                      const SizedBox(height: 16),
                      _pistaDocumento(),
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
          onPressed: _guardando ||
                  !_cargado ||
                  (widget.modo == CheckinModo.checkinDirecto && !_clienteListo)
              ? null
              : _confirmar,
          child: Text(_guardando ? 'Guardando…' : _accion),
        ),
      ],
    );
  }

  /// Encabezado compacto con la habitación fija del check-in directo.
  Widget _resumenHabitacion() {
    final h = _habitacion;
    if (h == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.meeting_room_outlined, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Habitación ${h.numero}'
            '${h.tipo != null ? ' · ${h.tipo}' : ''} '
            '(cap. ${h.maxPersonas})',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  /// Paso 1 del check-in directo: identificación del cliente por documento.
  Widget _seccionCliente() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Identificación del cliente',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('tipo-doc-$_formVersion'),
                  initialValue: DocumentoTipo.opciones.contains(_tipoDoc)
                      ? _tipoDoc
                      : DocumentoTipo.cedula,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  items: [
                    for (final t in DocumentoTipo.opciones)
                      DropdownMenuItem(
                        value: t,
                        child: Text(
                          DocumentoTipo.label(t),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() {
                            _tipoDoc = v ?? DocumentoTipo.cedula;
                            _titular.tipoDocumento = _tipoDoc;
                          }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _docCtrl,
                  focusNode: _docFocus,
                  autofocus: !_clienteListo,
                  enabled: !_guardando,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'N° de documento',
                    hintText: 'Ej: V-12345678',
                    border: const OutlineInputBorder(),
                    helperText: _clienteListo
                        ? 'Edite el documento y busque para cambiar de cliente'
                        : 'Escriba el documento y presione Enter',
                    suffixIcon: _buscandoDocumento
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Buscar cliente',
                            icon: const Icon(Icons.search),
                            onPressed:
                                _guardando ? null : _buscarHuespedPorDocumento,
                          ),
                  ),
                  onChanged: (v) {
                    _titular.numeroDocumento = v;
                    _titular.tipoDocumento = _tipoDoc;
                  },
                  onSubmitted: (_) => _buscarHuespedPorDocumento(),
                ),
              ),
            ],
          ),
          if (_clienteExistente) ...[
            const SizedBox(height: 10),
            _bannerCliente(
              color: appColor(context, 'success'),
              icon: Icons.verified_user_outlined,
              texto: 'Cliente registrado: ${_titular.etiqueta}. '
                  'Revise o actualice sus datos.',
              accion: TextButton(
                onPressed: _guardando ? null : _limpiarCliente,
                child: const Text('Cambiar'),
              ),
            ),
          ] else if (_clienteListo) ...[
            const SizedBox(height: 10),
            _bannerCliente(
              color: appColor(context, 'info'),
              icon: Icons.person_add_alt_1_outlined,
              texto: 'Cliente nuevo: complete los datos para registrarlo.',
            ),
          ],
          if (_error.isNotEmpty && _errorCliente) ...[
            const SizedBox(height: 10),
            SelectableText(
              _error,
              style: TextStyle(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerCliente({
    required Color color,
    required IconData icon,
    required String texto,
    Widget? accion,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (accion != null) accion,
        ],
      ),
    );
  }

  /// Ayuda mostrada mientras no se ha buscado el documento del cliente.
  Widget _pistaDocumento() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Busque al cliente por documento para continuar con el '
              'check-in. Si no existe, se abrirá el formulario para '
              'registrarlo.',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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
