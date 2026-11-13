import 'package:flutter/material.dart';

import '../../data/pos_dispositivo.dart';

/// Acción elegida en el diálogo de opciones de sesión.
enum OpcionSesion { cambiarUsuario, cerrarTurno }

/// Diálogo con las acciones disponibles sobre el turno compartido.
///
/// - **Cambiar usuario**: sale del turno sin cerrarlo (`salio_en`), para que
///   otro usuario se una o para retomarlo después.
/// - **Cerrar turno**: genera el corte y lo cierra. Solo se habilita para el
///   aperturista y desde la PC principal; si no, se explica el motivo.
Future<OpcionSesion?> showOpcionesSesionDialog(
  BuildContext context, {
  required bool esAperturista,
  String? aperturistaNombre,
}) {
  return showDialog<OpcionSesion>(
    context: context,
    builder: (ctx) => _OpcionesSesionDialog(
      esAperturista: esAperturista,
      aperturistaNombre: aperturistaNombre,
    ),
  );
}

class _OpcionesSesionDialog extends StatelessWidget {
  const _OpcionesSesionDialog({
    required this.esAperturista,
    this.aperturistaNombre,
  });

  final bool esAperturista;
  final String? aperturistaNombre;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final puedeCerrar = puedeCerrarTurno(esAperturista);

    final motivo = puedeCerrar
        ? null
        : !esPcPrincipal
            ? 'Solo puede cerrarse desde la PC principal.'
            : 'Solo ${aperturistaNombre ?? 'quien abrió el turno'} '
                'puede cerrar este turno.';

    return AlertDialog(
      title: const Text('Opciones de sesión'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.switch_account_outlined, color: scheme.primary),
            title: const Text('Cambiar usuario'),
            subtitle: const Text('El turno queda abierto para los demás.'),
            onTap: () => Navigator.pop(context, OpcionSesion.cambiarUsuario),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: puedeCerrar,
            leading: Icon(
              Icons.lock_outline,
              color: puedeCerrar ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: const Text('Cerrar turno'),
            subtitle: Text(
              motivo ?? 'Genera el corte y envía los reportes.',
              style: TextStyle(
                fontSize: 12,
                color: puedeCerrar ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
            onTap: puedeCerrar
                ? () => Navigator.pop(context, OpcionSesion.cerrarTurno)
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
