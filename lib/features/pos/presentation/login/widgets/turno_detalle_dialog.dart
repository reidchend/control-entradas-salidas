import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/pos_providers.dart';
import '../../../data/pos_turno_models.dart';
import '../../../data/reporte_cierre_texto.dart';

/// Detalle de solo lectura de un turno (abierto o cerrado): participantes y
/// sus ventas. Se usa desde la vista pública de Turnos del login.
Future<void> showTurnoDetalleDialog(
  BuildContext context, {
  required int sesionId,
  String? titulo,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TurnoDetalleDialog(
      sesionId: sesionId,
      titulo: titulo ?? 'Turno #$sesionId',
    ),
  );
}

class _TurnoDetalleDialog extends ConsumerStatefulWidget {
  const _TurnoDetalleDialog({required this.sesionId, required this.titulo});

  final int sesionId;
  final String titulo;

  @override
  ConsumerState<_TurnoDetalleDialog> createState() =>
      _TurnoDetalleDialogState();
}

class _TurnoDetalleDialogState extends ConsumerState<_TurnoDetalleDialog> {
  late Future<List<ParticipanteTurno>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(posRepoProvider)!.getParticipantes(widget.sesionId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.groups_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.titulo)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<ParticipanteTurno>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                'No se pudieron cargar los participantes: ${snapshot.error}',
              );
            }
            final participantes = snapshot.data ?? const <ParticipanteTurno>[];
            if (participantes.isEmpty) {
              return Text(
                'Sin participantes registrados. Este turno es anterior al '
                'modelo de turnos compartidos.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in participantes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        p.esAperturista ? Icons.star : Icons.person_outline,
                        color: p.esAperturista
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        '${p.nombre}${p.esAperturista ? ' · aperturó' : ''}',
                      ),
                      subtitle: Text(
                        '${p.ventas} ventas · \$${fmtNumCierre(p.total)}'
                        '${p.comandas > 0 ? ' · ${p.comandas} comandas' : ''}',
                      ),
                      trailing: Text(
                        p.enTurno ? 'En turno' : 'Salió',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
