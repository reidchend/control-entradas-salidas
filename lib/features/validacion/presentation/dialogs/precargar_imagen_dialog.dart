import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clipboard_utils.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../../../core/utils/web_utils.dart';
import '../../data/ocr_service.dart';
import '../../data/temporales_repository.dart';
import '../../data/validacion_providers.dart';

const _prefijos = {'Factura': 'F-', 'Nota de Entrega': 'NE-', 'Entrada': 'EV-'};

/// Diálogo para pre-cargar una imagen (pegar o seleccionar), extraer sus datos
/// por OCR, corregirlos y guardarla como temporal. Devuelve `true` si se guardó.
Future<bool> showPrecargarImagenDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => const _PrecargarImagenDialog(),
      ) ??
      false;
}

class _PrecargarImagenDialog extends ConsumerStatefulWidget {
  const _PrecargarImagenDialog();

  @override
  ConsumerState<_PrecargarImagenDialog> createState() =>
      _PrecargarImagenDialogState();
}

class _PrecargarImagenDialogState extends ConsumerState<_PrecargarImagenDialog> {
  final _facturaCtrl = TextEditingController();
  final _proveedorCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();

  String _tipoDocumento = 'Factura';
  Uint8List? _imagen;
  bool _extrayendo = false;
  bool _guardando = false;

  PasteCancel? _pasteCancel;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initWebPasteListener();
    }
  }

  void _initWebPasteListener() {
    _pasteCancel = setupPasteImageListener((bytes) => _procesarImagen(bytes));
  }

  @override
  void dispose() {
    _pasteCancel?.call();
    _facturaCtrl.dispose();
    _proveedorCtrl.dispose();
    _montoCtrl.dispose();
    _fechaCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarImagen() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Imágenes',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    _procesarImagen(bytes);
  }

  Future<void> _pegarImagen() async {
    try {
      final bytes = await readClipboardImage();
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró imagen en el portapapeles')),
          );
        }
        return;
      }
      _procesarImagen(bytes);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Error al leer portapapeles'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _procesarImagen(Uint8List bytes) async {
    setState(() {
      _imagen = bytes;
      _extrayendo = true;
    });
    final parsed = await OcrService.extractFactura(bytes);
    if (!mounted) return;
    setState(() {
      _extrayendo = false;
      if (parsed != null) {
        if (parsed['tipo_documento'] != null &&
            _prefijos.containsKey(parsed['tipo_documento'])) {
          _tipoDocumento = parsed['tipo_documento']!;
        }
        final nro = parsed['nro_factura'] ?? '';
        _facturaCtrl.text = nro.isNotEmpty
            ? '${_prefijos[_tipoDocumento] ?? 'F-'}$nro'
            : _facturaCtrl.text;
        final prov = parsed['proveedor'] ?? '';
        if (prov.isNotEmpty) _proveedorCtrl.text = prov;
        final fecha = parsed['fecha'] ?? '';
        if (fecha.isNotEmpty) _fechaCtrl.text = fecha;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parsed != null
              ? 'Datos extraídos de la imagen'
              : 'No se pudo extraer texto de la imagen (OCR).',
        ),
      ),
    );
  }

  String _conPrefijo(String raw) {
    for (final prefix in ['NE-', 'EV-', 'F-']) {
      if (raw.toUpperCase().startsWith(prefix)) return raw;
    }
    return '${_prefijos[_tipoDocumento] ?? 'F-'}$raw';
  }

  Future<void> _guardar() async {
    final imagen = _imagen;
    if (imagen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero pega o selecciona una imagen.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final fechaStr = _fechaCtrl.text.trim();
    DateTime? fecha;
    if (fechaStr.isNotEmpty) {
      final parts = fechaStr.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          fecha = DateTime(y, m, d);
        }
      }
      if (fecha == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fecha inválida, usa formato dd/mm/aaaa.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _guardando = true);
    try {
      final repo = ref.read(temporalesRepoProvider);
      await repo.guardar(
        imagen: imagen,
        tipoDocumento: _tipoDocumento,
        nroFactura: _facturaCtrl.text.trim(),
        proveedor: _proveedorCtrl.text.trim(),
        monto: double.tryParse(_montoCtrl.text.trim()),
        fecha: fecha,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar temporal: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _seccionTemporalesGuardados(ColorScheme scheme) {
    return Consumer(
      builder: (context, ref, _) {
        final lista = ref.watch(temporalesProvider).valueOrNull;
        if (lista == null || lista.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Temporales guardados (${lista.length})',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: lista.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = lista[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    leading: t.imagen != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              t.imagen!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.image_not_supported_outlined,
                            size: 28),
                    title: Text(
                      t.nroFactura?.isNotEmpty == true
                          ? t.nroFactura!
                          : 'Sin número',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (t.proveedor?.isNotEmpty == true) t.proveedor!,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Eliminar temporal',
                      onPressed: () => _eliminarTemporal(ref, t),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _eliminarTemporal(WidgetRef ref, TemporalData t) async {
    await ref.read(temporalesRepoProvider).eliminar(t.id!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temporal eliminado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Precargar imagen (temporal)'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pega la imagen desde el portapapeles o selecciónala. '
                'Se extraen los datos por OCR y quedan guardados para usarlos '
                'al validar.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _seccionTemporalesGuardados(scheme),
              const SizedBox(height: 12),
              if (_imagen == null)
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                    color: scheme.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: _extrayendo
                        ? const CircularProgressIndicator()
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: _pegarImagen,
                                icon: const Icon(Icons.paste),
                                label: const Text('Pegar imagen'),
                              ),
                              const SizedBox(width: 12),
                              TextButton.icon(
                                onPressed: _seleccionarImagen,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Seleccionar imagen'),
                              ),
                            ],
                          ),
                  ),
                )
              else
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: Image.memory(
                          _imagen!,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (_extrayendo) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _seleccionarImagen,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Cambiar imagen'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _imagen = null),
                          child: const Text('Quitar'),
                        ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipoDocumento,
                decoration: const InputDecoration(
                  labelText: 'Tipo de documento',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final t in _prefijos.keys)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() {
                  _tipoDocumento = v ?? _tipoDocumento;
                  _facturaCtrl.text = _conPrefijo(_facturaCtrl.text.trim());
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _facturaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de factura',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _proveedorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Proveedor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fechaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fecha (dd/mm/aaaa)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _montoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Monto (VES)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Guardar temporal'),
        ),
      ],
    );
  }
}
