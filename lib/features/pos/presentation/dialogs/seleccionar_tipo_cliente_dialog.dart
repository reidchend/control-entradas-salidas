import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/habitacion_models.dart';
import '../../data/pos_providers.dart';

/// Resultado del diálogo de selección de tipo de cliente y habitación.
class TipoClienteSeleccion {
  const TipoClienteSeleccion({
    required this.tipo, // 'particular' o 'huesped'
    this.habitaciones, // null si particular; '101, 103' si huésped
  });

  final String tipo;
  final String? habitaciones;

  bool get esParticular => tipo == 'particular';
}

/// Diálogo de dos pasos sin teclado (óptimo para tablets en horizontal):
///
/// Paso 1: ¿El cliente es Particular o Huésped?
/// Paso 2 (solo si Huésped): selecciona una o varias habitaciones con chips.
///
/// No usa TextField: todo es táctil.
Future<TipoClienteSeleccion?> showSeleccionarTipoClienteDialog({
  required BuildContext context,
  required int mesaId,
  required String mesaNumero,
}) {
  return showDialog<TipoClienteSeleccion>(
    context: context,
    builder: (_) => _SeleccionarTipoClienteDialog(
      mesaId: mesaId,
      mesaNumero: mesaNumero,
    ),
  );
}

class _SeleccionarTipoClienteDialog extends ConsumerStatefulWidget {
  const _SeleccionarTipoClienteDialog({
    required this.mesaId,
    required this.mesaNumero,
  });

  final int mesaId;
  final String mesaNumero;

  @override
  ConsumerState<_SeleccionarTipoClienteDialog> createState() =>
      _SeleccionarTipoClienteDialogState();
}

class _SeleccionarTipoClienteDialogState
    extends ConsumerState<_SeleccionarTipoClienteDialog> {
  String? _tipo; // 'particular' | 'huesped'
  final Set<int> _habitacionesSeleccionadas = <int>{};
  List<Habitacion> _habitaciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarHabitaciones();
  }

  Future<void> _cargarHabitaciones() async {
    final repo = ref.read(posRepoProvider)!;
    final lista = await repo.getHabitaciones(soloActivos: true);
    if (!mounted) return;
    setState(() {
      _habitaciones = lista;
      _cargando = false;
    });
  }

  bool get _puedeContinuar =>
      _tipo == 'huesped' && _habitacionesSeleccionadas.isNotEmpty;

  /// Números de las habitaciones seleccionadas, en orden (ej. `101, 103`).
  String get _seleccionTexto => _habitaciones
      .where((h) => _habitacionesSeleccionadas.contains(h.id))
      .map((h) => h.numero)
      .join(', ');

  TipoClienteSeleccion? _resultado() {
    if (_tipo == 'particular') {
      return TipoClienteSeleccion(tipo: 'particular', habitaciones: null);
    }
    if (_tipo == 'huesped' && _habitacionesSeleccionadas.isNotEmpty) {
      return TipoClienteSeleccion(
        tipo: 'huesped',
        habitaciones: _seleccionTexto,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final esHuesped = _tipo == 'huesped';

    return AlertDialog(
      scrollable: true,
      title: Text('Mesa ${widget.mesaNumero}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: esHuesped ? _PasoHabitaciones(scheme) : _PasoTipo(),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: esHuesped
          ? [
              TextButton(
                onPressed: () => setState(() => _tipo = null),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: _puedeContinuar
                    ? () => Navigator.pop(context, _resultado())
                    : null,
                child: const Text('Continuar'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
    );
  }

  /// Paso 1: Particular o Huésped.
  Widget _PasoTipo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿El cliente es alojado?',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _BotonTipo(
                label: 'Particular',
                icon: Icons.person_outline,
                seleccionado: _tipo == 'particular',
                onTap: () => Navigator.pop(
                  context,
                  const TipoClienteSeleccion(tipo: 'particular'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BotonTipo(
                label: 'Huésped',
                icon: Icons.hotel,
                seleccionado: _tipo == 'huesped',
                onTap: () => setState(() => _tipo = 'huesped'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Paso 2: selección de habitaciones (chips, sin teclado).
  Widget _PasoHabitaciones(ColorScheme scheme) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seleccione la(s) habitación(es):',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in _habitaciones)
              ChoiceChip(
                label: Text(h.numero),
                selected: _habitacionesSeleccionadas.contains(h.id),
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _habitacionesSeleccionadas.add(h.id);
                    } else {
                      _habitacionesSeleccionadas.remove(h.id);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_habitacionesSeleccionadas.isNotEmpty)
          Text(
            'Seleccionadas: $_seleccionTexto',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Botón de selección de tipo de cliente (toggle visual).
class _BotonTipo extends StatelessWidget {
  const _BotonTipo({
    required this.label,
    required this.icon,
    required this.seleccionado,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: seleccionado ? scheme.primary : null,
        foregroundColor: seleccionado ? scheme.onPrimary : null,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }
}
