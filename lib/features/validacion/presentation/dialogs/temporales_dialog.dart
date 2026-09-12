import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/modal_sizing.dart';
import '../../data/temporales_repository.dart';
import '../../data/validacion_providers.dart';

/// Resultado de la selección en el diálogo de temporales.
/// `temporal == null` significa que el usuario optó por pegar una imagen nueva
/// directamente en el diálogo de validación.
class SeleccionTemporal {
  final TemporalData? temporal;
  const SeleccionTemporal(this.temporal);
}

/// Diálogo que muestra los temporales pre-cargados para que el usuario elija
/// uno (validar + enviar el mensaje con esa imagen) o pegar una imagen nueva.
/// Devuelve `null` si se canceló.
Future<SeleccionTemporal?> showTemporalesDialog(
  BuildContext context,
  List<TemporalData> temporales,
) {
  return showDialog<SeleccionTemporal>(
    context: context,
    builder: (ctx) => _TemporalesDialog(temporales: temporales),
  );
}

class _TemporalesDialog extends ConsumerStatefulWidget {
  const _TemporalesDialog({required this.temporales});

  final List<TemporalData> temporales;

  @override
  ConsumerState<_TemporalesDialog> createState() => _TemporalesDialogState();
}

class _TemporalesDialogState extends ConsumerState<_TemporalesDialog> {
  String _fmtFecha(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Temporales (${widget.temporales.length})'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Elige la imagen pre-cargada para validar estas entradas, o '
              'pega una nueva directamente.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.temporales.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = widget.temporales[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: t.imagen != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              t.imagen!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.image_not_supported_outlined),
                    title: Text(
                      t.nroFactura?.isNotEmpty == true
                          ? t.nroFactura!
                          : 'Sin número',
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (t.proveedor?.isNotEmpty == true) t.proveedor!,
                        if (t.fecha != null) _fmtFecha(t.fecha!),
                        if (t.monto != null)
                          'Bs ${t.monto!.toStringAsFixed(2)}',
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Eliminar temporal',
                          onPressed: () async {
                            final repo = ref.read(temporalesRepoProvider);
                            await repo.eliminar(t.id!);
                            if (mounted) {
                              setState(() {
                                widget.temporales.removeWhere(
                                    (e) => e.id == t.id);
                              });
                            }
                          },
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                              context, SeleccionTemporal(t)),
                          child: const Text('Usar'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, const SeleccionTemporal(null)),
          icon: const Icon(Icons.content_paste_go, size: 18),
          label: const Text('Pegar nueva imagen'),
        ),
      ],
    );
  }
}
