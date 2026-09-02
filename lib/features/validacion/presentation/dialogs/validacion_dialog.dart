import 'dart:async';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clipboard_utils.dart';
import '../../../../core/utils/web_utils.dart';
import '../../data/ocr_service.dart';
import '../../data/temporales_repository.dart';
import '../../data/validacion_providers.dart';
import '../../data/validacion_repository.dart';
import '../../../whatsapp/data/whatsapp_providers.dart';
import '../../../whatsapp/data/whatsapp_repository.dart';
import '../widgets/pagos_panel.dart';

const _prefijos = {'Factura': 'F-', 'Nota de Entrega': 'NE-', 'Entrada': 'EV-'};

/// Diálogo de validación de entradas (porta `ValidacionDialog` de dialog.py +
/// `ValidacionFields` de fields.py; sin el asistente OCR de IA).
/// Devuelve un [ResultadoValidacion] si se validó, o `null` si se canceló.
/// Si se pasa [temporal], el diálogo arranca con esa imagen pre-cargada y sus
/// datos extraídos por OCR.
Future<ResultadoValidacion?> showValidacionDialog(
  BuildContext context, {
  required Set<int> selectedEntradas,
  required String usuario,
  TemporalData? temporal,
}) {
  return showDialog<ResultadoValidacion>(
    context: context,
    builder: (ctx) => _ValidacionDialog(
      selectedEntradas: selectedEntradas,
      usuario: usuario,
      temporal: temporal,
    ),
  );
}

class _ValidacionDialog extends ConsumerStatefulWidget {
  const _ValidacionDialog({
    required this.selectedEntradas,
    required this.usuario,
    this.temporal,
  });

  final Set<int> selectedEntradas;
  final String usuario;
  final TemporalData? temporal;

  @override
  ConsumerState<_ValidacionDialog> createState() => _ValidacionDialogState();
}

class _ValidacionDialogState extends ConsumerState<_ValidacionDialog> {
  final _facturaCtrl = TextEditingController();
  final _nuevoProveedorCtrl = TextEditingController();
  final _nuevoRifCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();

  String _tipoDocumento = 'Factura';
  String? _proveedor; // valor del dropdown; '__nuevo__' abre campos nuevos
  DateTime _fecha = DateTime.now();
  bool _validando = false;
  Uint8List? _imagenPegada;

  final _pagosKey = GlobalKey<PagosPanelState>();
  PasteCancel? _pasteCancel;

  @override
  void initState() {
    super.initState();
    _fecha = DateTime.now();
    // El campo ya entra con el prefijo del tipo por defecto ('Factura' → F-).
    _facturaCtrl.text = _conPrefijo('');
    if (kIsWeb) {
      _initWebPasteListener();
    }
    _aplicarTemporal();
  }

  /// Si el diálogo se abrió con un temporal, precarga la imagen y los datos
  /// extraídos por OCR. El proveedor extraído que no exista en la lista se
  /// muestra como "nuevo proveedor" con el nombre pre-llenado.
  Future<void> _aplicarTemporal() async {
    final t = widget.temporal;
    if (t == null) return;
    _imagenPegada = t.imagen;
    if (t.tipoDocumento != null && _prefijos.containsKey(t.tipoDocumento)) {
      _tipoDocumento = t.tipoDocumento!;
    }
    final nro = (t.nroFactura ?? '').trim();
    _facturaCtrl.text = nro.isEmpty ? _conPrefijo('') : _conPrefijo(nro);
    if (t.monto != null) {
      _montoCtrl.text = t.monto!.toStringAsFixed(2);
    }
    if (t.fecha != null) {
      _fecha = t.fecha!;
    }
    final prov = (t.proveedor ?? '').trim();
    if (prov.isEmpty) {
      return;
    }
    await _resolverProveedor(prov);
    if (mounted) setState(() {});
  }

  /// Resuelve si un nombre de proveedor existe en BD.
  /// Si existe → lo selecciona en el dropdown.
  /// Si no existe → activa modo "__nuevo__" prellenando el campo.
  Future<void> _resolverProveedor(String provNombre) async {
    if (provNombre.isEmpty || provNombre == 'Varios') {
      setState(() => _proveedor = provNombre);
      return;
    }
    try {
      final proveedores = await ref.read(proveedoresProvider.future);
      if (!mounted) return;
      if (proveedores.any((p) => p['nombre'] == provNombre)) {
        setState(() => _proveedor = provNombre);
      } else {
        setState(() {
          _proveedor = '__nuevo__';
          _nuevoProveedorCtrl.text = provNombre;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _proveedor = '__nuevo__';
        _nuevoProveedorCtrl.text = provNombre;
      });
    }
  }

  void _initWebPasteListener() {
    _pasteCancel = setupPasteImageListener((bytes) => _procesarBytesOcr(bytes));
  }

  @override
  void dispose() {
    _pasteCancel?.call();
    _facturaCtrl.dispose();
    _nuevoProveedorCtrl.dispose();
    _nuevoRifCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTipoDocumento(String tipo) async {
    setState(() => _tipoDocumento = tipo);
    if (tipo == 'Entrada') {
      final repo = ref.read(validacionRepoProvider)!;
      final correlativo = await repo.getNextEntradaCorrelativo();
      if (mounted) setState(() => _facturaCtrl.text = correlativo);
    } else {
      _aplicarPrefijo();
    }
  }

  void _aplicarPrefijo() {
    _facturaCtrl.text = _conPrefijo(_facturaCtrl.text.trim());
    setState(() {});
  }

  /// Devuelve el número de factura con el prefijo del tipo de documento si no
  /// lo tiene (NE-, EV-, F-). Se aplica al cambiar el tipo y al validar, NO en
  /// cada tecla: reasignar `controller.text` en `onChanged` resetea el cursor
  /// y rompe la escritura en el campo.
  String _conPrefijo(String raw) {
    for (final prefix in ['NE-', 'EV-', 'F-']) {
      if (raw.toUpperCase().startsWith(prefix)) return raw;
    }
    return '${_prefijos[_tipoDocumento] ?? 'F-'}$raw';
  }

  void _onMontoChanged(String value) {
    final monto = double.tryParse(value.trim()) ?? 0;
    _pagosKey.currentState?.setMontoTotal(monto);
  }

  bool _puedeValidar() {
    if (_proveedor == '__nuevo__') {
      return _nuevoProveedorCtrl.text.trim().isNotEmpty;
    }
    return _proveedor != null && _proveedor!.isNotEmpty;
  }

  Future<void> _validar() async {
    final repo = ref.read(validacionRepoProvider)!;
    setState(() => _validando = true);
    try {
      final esNuevo = _proveedor == '__nuevo__';
      final proveedor = esNuevo
          ? _nuevoProveedorCtrl.text.trim()
          : (_proveedor ?? 'Varios');
      final rif = esNuevo ? _nuevoRifCtrl.text.trim() : '';

      final factura = _conPrefijo(_facturaCtrl.text.trim());
      final monto = double.tryParse(_montoCtrl.text.trim()) ?? 0;
      final pagos = _pagosKey.currentState?.pagos ?? [];

      // Capturar los productos ANTES de procesar (tras validar dejan de ser
      // entradas pendientes) para armar el mensaje de WhatsApp.
      final entradas = await repo.getEntradasPendientes();
      final seleccionadas = entradas
          .where((e) => widget.selectedEntradas.contains(e.id))
          .toList();
      final nombres = <String>[];
      for (final e in seleccionadas) {
        if (e.esPesable && e.pesoTotal > 0) {
          nombres.add('${e.nombre}: ${e.pesoTotal.toStringAsFixed(3)} kg');
        } else {
          nombres.add('${e.nombre}: ${e.cantidad.toInt()} ${e.unidad}');
        }
      }
      final productosStr =
          nombres.isEmpty ? 'Productos variados' : nombres.join('\n');

      final resultado = await repo.procesar(
        selectedEntradas: widget.selectedEntradas,
        proveedor: proveedor,
        rif: rif,
        factura: factura,
        monto: monto,
        fecha: _fecha,
        tipoDocumento: _tipoDocumento,
        pagos: pagos,
        usuario: widget.usuario,
      );

      // Envío WhatsApp en background (fire-and-forget): si el bot está apagado,
      // el envío directo falla y el mensaje queda encolado en la bandeja.
      final msg = formatValidationMessage(
        productos: productosStr,
        proveedor: proveedor,
        factura: factura,
        monto: monto,
        usuario: resultado.usuario,
        // Fecha de la factura (la que se guarda como `fecha_factura`), no la de
        // registro de los movimientos: el mensaje debe reflejar la factura.
        fechaEntrada: _fecha,
      );
      final waRepo = ref.read(whatsappRepoProvider)!;
      if (_imagenPegada != null) {
        unawaited(waRepo.enviarImagen(
          imagenBase64: base64Encode(_imagenPegada!),
          caption: msg,
        ));
      } else {
        unawaited(waRepo.enviarMensaje(msg));
      }

      if (mounted) Navigator.pop(context, resultado);
    } catch (e) {
      if (mounted) {
        setState(() => _validando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al validar entradas: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.of(context).size;
    final isMobile = screen.width < 600;
    final maxW = isMobile ? screen.width - 16 : 460.0;
    final maxH = isMobile ? screen.height * 0.82 : 620.0;
    final imgMaxH = isMobile ? 90.0 : 140.0;
    final pad = isMobile ? 12.0 : 16.0;
    return AlertDialog(
      title: const Text('Validar Entradas'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Validado por: ${widget.usuario}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                'Se validarán ${widget.selectedEntradas.length} entrada(s)',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _seccionDoc(scheme, isMobile: isMobile),
              const SizedBox(height: 10),
              if (_imagenPegada != null) ...[
                _seccionImagen(scheme, imgMaxH: imgMaxH),
                const SizedBox(height: 10),
              ],
              _seccionMonto(scheme),
              const SizedBox(height: 10),
              PagosPanel(key: _pagosKey),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _puedeValidar() && !_validando ? _validar : null,
          icon: _validando
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check, size: 18),
          label: const Text('Validar'),
        ),
      ],
    );
  }

  Widget _seccionDoc(ColorScheme scheme, {bool isMobile = false}) {
    return _section(
      scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título + botones OCR en fila adaptable
          if (isMobile) ...[
            const Text('Datos del Documento',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.paste, size: 16),
                    label: const Text('Pegar'),
                    onPressed: _validando ? null : _pegarImagen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.document_scanner, size: 16),
                    label: const Text('Escanear'),
                    onPressed: _validando ? null : _escanearOcr,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Datos del Documento',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.paste, size: 16),
                      label: const Text('Pegar'),
                      onPressed: _validando ? null : _pegarImagen,
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.document_scanner, size: 16),
                      label: const Text('Escanear'),
                      onPressed: _validando ? null : _escanearOcr,
                    ),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Tipo de documento: Wrap en móvil, SegmentedButton en PC
          if (isMobile)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _tipoChip('Factura'),
                _tipoChip('N. Entrega'),
                _tipoChip('Entrada'),
              ],
            )
          else
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Factura', label: Text('Factura')),
                ButtonSegment(
                    value: 'Nota de Entrega', label: Text('N. Entrega')),
                ButtonSegment(value: 'Entrada', label: Text('Entrada')),
              ],
              selected: {_tipoDocumento},
              onSelectionChanged: _validando
                  ? null
                  : (sel) => _onTipoDocumento(sel.first),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _facturaCtrl,
            decoration: const InputDecoration(
              labelText: 'Nro. Factura',
              hintText: 'Ej: F-2024-001',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Consumer(
            builder: (context, ref, _) {
              final prov = ref.watch(proveedoresProvider);
              return prov.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e',
                    style: const TextStyle(color: Colors.red)),
                data: (proveedores) => DropdownButtonFormField<String>(
                  initialValue: _proveedor,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'Varios',
                      child: Text('Varios (sin proveedor)'),
                    ),
                    for (final p in proveedores)
                      DropdownMenuItem(
                        value: p['nombre'] as String,
                        child: Text(
                          p['nombre'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const DropdownMenuItem(
                      value: '__nuevo__',
                      child: Text('+ Agregar nuevo'),
                    ),
                  ],
                  onChanged: _validando
                      ? null
                      : (v) => setState(() => _proveedor = v),
                ),
              );
            },
          ),
          if (_proveedor == '__nuevo__') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _nuevoProveedorCtrl,
              decoration: const InputDecoration(
                labelText: 'Nuevo Proveedor',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nuevoRifCtrl,
              decoration: const InputDecoration(
                labelText: 'Nuevo RIF',
                hintText: 'J-XXXXXXXX-X',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: const Text('Fecha'),
                onPressed: _validando
                    ? null
                    : () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _fecha,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _fecha = d);
                      },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fecha: ${_fmtFecha(_fecha)}',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tipoChip(String label) {
    final selected = _tipoDocumento ==
        (label == 'N. Entrega' ? 'Nota de Entrega' : label);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: _validando
          ? null
          : (_) {
              final tipo =
                  label == 'N. Entrega' ? 'Nota de Entrega' : label;
              _onTipoDocumento(tipo);
            },
    );
  }

  Widget _seccionImagen(ColorScheme scheme, {double imgMaxH = 140}) {
    return _section(
      scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Imagen del Documento',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Quitar imagen',
                onPressed: () => setState(() => _imagenPegada = null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: imgMaxH),
                child: Image.memory(
                  _imagenPegada!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionMonto(ColorScheme scheme) {
    return _section(
      scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.attach_money, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Monto Total',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _montoCtrl,
            decoration: const InputDecoration(
              labelText: 'Monto Total (VES)',
              hintText: '1000.00',
              prefixIcon: Icon(Icons.attach_money),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _onMontoChanged,
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme scheme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }

  String _fmtFecha(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }

  Future<void> _procesarBytesOcr(Uint8List bytes) async {
    setState(() {
      _validando = true;
      _imagenPegada = bytes;
    });
    try {
      final parsed = await OcrService.extractFactura(bytes);
      if (parsed == null) return;
      if (mounted) {
        setState(() {
          if (parsed['tipo_documento'] != null && _prefijos.containsKey(parsed['tipo_documento'])) {
            _tipoDocumento = parsed['tipo_documento']!;
          }
          if (parsed['nro_factura'] != null && parsed['nro_factura']!.isNotEmpty) {
            _facturaCtrl.text = '${_prefijos[_tipoDocumento] ?? 'F-'}${parsed['nro_factura']}';
          }
          if (parsed['fecha'] != null && parsed['fecha']!.isNotEmpty) {
            final parts = parsed['fecha']!.split('/');
            if (parts.length == 3) {
              final d = int.tryParse(parts[0]);
              final m = int.tryParse(parts[1]);
              final y = int.tryParse(parts[2]);
              if (d != null && m != null && y != null) {
                _fecha = DateTime(y, m, d);
              }
            }
          }
          final provNombre = parsed['proveedor'] ?? '';
          if (provNombre.isNotEmpty) {
            _proveedor = provNombre;
          }
        });
        // Resolver proveedor: si no existe en BD → modo "__nuevo__"
        final provNombre = parsed['proveedor'] ?? '';
        if (provNombre.isNotEmpty) {
          await _resolverProveedor(provNombre);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR (Portapapeles): Doc ${parsed['nro_factura']} - ${parsed['proveedor']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error OCR portapapeles: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _validando = false);
    }
  }

  Future<void> _escanearOcr() async {
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
    setState(() {
      _validando = true;
      _imagenPegada = bytes;
    });
    try {
      final parsed = await OcrService.extractFactura(bytes);
      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo extraer texto de la imagen (OCR).')),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          if (parsed['tipo_documento'] != null && _prefijos.containsKey(parsed['tipo_documento'])) {
            _tipoDocumento = parsed['tipo_documento']!;
          }
          if (parsed['nro_factura'] != null && parsed['nro_factura']!.isNotEmpty) {
            _facturaCtrl.text = '${_prefijos[_tipoDocumento] ?? 'F-'}${parsed['nro_factura']}';
          }
          if (parsed['fecha'] != null && parsed['fecha']!.isNotEmpty) {
            final parts = parsed['fecha']!.split('/');
            if (parts.length == 3) {
              final d = int.tryParse(parts[0]);
              final m = int.tryParse(parts[1]);
              final y = int.tryParse(parts[2]);
              if (d != null && m != null && y != null) {
                _fecha = DateTime(y, m, d);
              }
            }
          }
          final provNombre = parsed['proveedor'] ?? '';
          if (provNombre.isNotEmpty) {
            _proveedor = provNombre;
          }
        });
        // Resolver proveedor: si no existe en BD → modo "__nuevo__"
        final provNombre = parsed['proveedor'] ?? '';
        if (provNombre.isNotEmpty) {
          await _resolverProveedor(provNombre);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR exitoso: Doc ${parsed['nro_factura']} - ${parsed['proveedor']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en OCR: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _validando = false);
    }
  }

  static const String _clipBuildTag = '[CB-8b77408]';

  Future<void> _pegarImagen() async {
    try {
      final bytes = await readClipboardImage();
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_clipBuildTag No se encontró imagen en el portapapeles.\n'
                  'Copie con la Herramienta de Recortes y luego haga click en Pegar.'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      _procesarBytesOcr(bytes);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText('$_clipBuildTag ${e.message ?? 'Error al leer portapapeles'}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } on FlutterError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText('$_clipBuildTag Canal no disponible: ${e.message}\n'
                'Reinstale la aplicación.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText('$_clipBuildTag Diagnóstico:\n$e'),
            backgroundColor: Colors.purple,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }
}
