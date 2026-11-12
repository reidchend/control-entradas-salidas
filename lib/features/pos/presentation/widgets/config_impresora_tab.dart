import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pos_providers.dart';
import '../../data/printer_service.dart';
import '../../data/ticket_escpos.dart';
import '../../data/ticket_settings.dart';
import '../dialogs/ticket_preview_dialog.dart';

/// Pestaña Impresora (port de `_build_printer_tab` de `usr/pos/views/config.py`):
/// membrete de comandas (nombre/RIF/dirección/teléfono), tamaño del membrete,
/// correlativo inicial y dispositivo de impresora (en web se guarda el path
/// para uso nativo; la impresión web se hace por vista previa + diálogo del
/// navegador, no requiere impresora).
class ConfigImpresoraTab extends ConsumerStatefulWidget {
  const ConfigImpresoraTab({super.key});

  @override
  ConsumerState<ConfigImpresoraTab> createState() => _ConfigImpresoraTabState();
}

class _ConfigImpresoraTabState extends ConsumerState<ConfigImpresoraTab> {
  final _nombreCtrl = TextEditingController();
  final _rifCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correlativoCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();

  String _size = 'large';
  String _precioSize = '2';
  int _correlativoActual = 0;
  bool _guardando = false;
  bool _nativo = false;
  bool _escaneandoImpresoras = false;
  List<String> _impresoras = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rifCtrl.dispose();
    _direccionCtrl.dispose();
    _telefonoCtrl.dispose();
    _correlativoCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final repo = ref.read(posRepoProvider)!;
    final header = await cargarMembrete(repo);
    final corr = await getCorrelativoActual(repo);
    final device = await getPrinterDevice(repo);
    final nativo = puedeImprimirNativo;
    final impresoras = nativo ? await listarImpresoras() : const <String>[];
    if (!mounted) return;
    setState(() {
      _nombreCtrl.text = header.nombre;
      _rifCtrl.text = header.rif;
      _direccionCtrl.text = header.direccion;
      _telefonoCtrl.text = header.telefono;
      _size = header.size;
      _precioSize = header.precioSize;
      _correlativoActual = corr;
      _correlativoCtrl.text = corr.toString();
      _deviceCtrl.text = device ?? '';
      _nativo = nativo;
      _impresoras = impresoras;
    });
  }

  Future<void> _escanear() async {
    setState(() => _escaneandoImpresoras = true);
    try {
      final impresoras = await listarImpresoras();
      if (!mounted) return;
      setState(() => _impresoras = impresoras);
      _snack('${impresoras.length} impresora(s) encontrada(s)',
          color: const Color(0xFF2196F3));
    } catch (e) {
      _snack('Error al escanear: $e', color: const Color(0xFFEF5350));
    } finally {
      if (mounted) setState(() => _escaneandoImpresoras = false);
    }
  }

  void _snack(String msg, {Color color = const Color(0xFF4CAF50)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  TicketHeader _headerActual() => TicketHeader(
        nombre: _nombreCtrl.text.trim(),
        rif: _rifCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        size: _size,
        precioSize: _precioSize,
      );

  Future<void> _guardarMembrete() async {
    setState(() => _guardando = true);
    try {
      await guardarMembrete(
        ref.read(posRepoProvider)!,
        nombre: _nombreCtrl.text.trim(),
        rif: _rifCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        size: _size,
        precioSize: _precioSize,
      );
      _snack('Membrete guardado');
    } catch (e) {
      _snack('Error al guardar: $e', color: const Color(0xFFEF5350));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _cambiarPrecioSize(int delta) {
    final actual = int.tryParse(normalizarPrecioSize(_precioSize)) ?? 2;
    final nuevo = (actual + delta).clamp(1, 4);
    setState(() => _precioSize = '$nuevo');
  }

  Future<void> _guardarCorrelativo() async {
    final v = int.tryParse(_correlativoCtrl.text.trim());
    if (v == null || v < 0) {
      _snack('Ingrese un número válido', color: const Color(0xFFEF5350));
      return;
    }
    try {
      await setCorrelativoInicial(ref.read(posRepoProvider)!, v);
      setState(() => _correlativoActual = v);
      _snack('Correlativo establecido en $v');
    } catch (e) {
      _snack('Error: $e', color: const Color(0xFFEF5350));
    }
  }

  Future<void> _guardarDevice() async {
    try {
      await setPrinterDevice(ref.read(posRepoProvider)!, _deviceCtrl.text.trim());
      _snack('Dispositivo guardado');
    } catch (e) {
      _snack('Error: $e', color: const Color(0xFFEF5350));
    }
  }

  /// Prueba de impresión: en Windows envía un ticket ESC/POS real a la
  /// impresora configurada; en web muestra la vista previa con el diálogo.
  Future<void> _probar() async {
    final repo = ref.read(posRepoProvider)!;
    final header = await cargarMembrete(repo);
    if (!mounted) return;
    final items = <TicketItem>[
      const (cantidad: 1, nombre: 'PRUEBA DE IMPRESIÓN', precio: 0, contornos: <String>[]),
    ];
    if (puedeImprimirNativo) {
      final bytes = construirTicketEscpos(
        items: items,
        comandaId: 0,
        correlativo: _correlativoActual,
        header: header,
      );
      final dispositivo = _deviceCtrl.text.trim();
      try {
        await imprimirTicketNativo(dispositivo, bytes);
        _snack(dispositivo.isEmpty
            ? 'Impreso en la impresora predeterminada'
            : 'Impreso en: $dispositivo');
      } catch (e) {
        _snack('Error de impresión:\n$e', color: const Color(0xFFEF5350));
      }
      return;
    }
    final lineas = construirTicketPreview(
      items: items,
      comandaId: 0,
      correlativo: _correlativoActual,
      header: header,
    );
    await showTicketPreview(context, lineas: lineas, titulo: 'Prueba de impresión');
  }

  Widget _buildPreviewTicket() {
    final scheme = Theme.of(context).colorScheme;
    final lineas = construirTicketPreview(
      items: const [
        (cantidad: 2, nombre: 'Hamburguesa especial', precio: 5.50, contornos: <String>['Papas']),
        (cantidad: 1, nombre: 'Refresco', precio: 1.50, contornos: <String>[]),
      ],
      total: 12.50,
      comandaId: 1,
      correlativo: 1,
      tasa: 36.50,
      cajero: 'Cajero',
      mesa: 'Mesa 5',
      header: _headerActual(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VISTA PREVIA DEL TICKET',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'El tamaño del precio se aplica en la impresión ESC/POS. '
          'Tamaño actual: ${etiquetaPrecioSize(_precioSize)}.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              lineas.join('\n'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.25,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Color(0xFFBB86FC),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('MEMBRETE DE COMANDAS', style: labelStyle),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardarMembrete,
                      icon: const Icon(Icons.save),
                      label: Text(_guardando ? 'Guardando…' : 'Guardar membrete'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nombreCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la empresa',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _rifCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'RIF',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _direccionCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _telefonoCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _size,
                  decoration: const InputDecoration(
                    labelText: 'Tamaño del membrete',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'small',
                      child: Text('Pequeño (condensado)'),
                    ),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'large', child: Text('Grande')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _size = v);
                  },
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tamaño del precio en tickets',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Reducir',
                        onPressed: (int.tryParse(normalizarPrecioSize(_precioSize)) ?? 2) <= 1
                            ? null
                            : () => _cambiarPrecioSize(-1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 56,
                        child: TextFormField(
                          key: ValueKey(_precioSize),
                          initialValue: normalizarPrecioSize(_precioSize),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v.trim());
                            if (n != null && n >= 1 && n <= 4) {
                              setState(() => _precioSize = '$n');
                            }
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Aumentar',
                        onPressed: (int.tryParse(normalizarPrecioSize(_precioSize)) ?? 2) >= 4
                            ? null
                            : () => _cambiarPrecioSize(1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          etiquetaPrecioSize(_precioSize),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildPreviewTicket(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CORRELATIVO DE COMANDAS', style: labelStyle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Actual:', style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Text(
                      '$_correlativoActual',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _correlativoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Correlativo inicial',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _guardarCorrelativo,
                      child: const Text('Establecer'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'El correlativo real de cada ticket sale de las ventas '
                  'registradas (máximo + 1), por lo que este valor es solo '
                  'informativo para el arranque.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('IMPRESORA DE COMANDAS', style: labelStyle),
                const SizedBox(height: 4),
                if (_nativo) ...[
                  Text(
                    'Impresión nativa detectada: se envían los bytes ESC/POS '
                    'en modo RAW a la impresora seleccionada.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (_impresoras.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _impresoras)
                          FilterChip(
                            label: Text(p, overflow: TextOverflow.ellipsis),
                            selected: _deviceCtrl.text == p,
                            onSelected: (_) => setState(() => _deviceCtrl.text = p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _escaneandoImpresoras ? null : _escanear,
                        icon: _escaneandoImpresoras
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('Escanear impresoras'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else
                  Text(
                    'En web no se detectan impresoras USB; la impresión usa el '
                    'diálogo del navegador. En Windows, el nombre de la '
                    'impresora se configura aquí.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deviceCtrl,
                  decoration: InputDecoration(
                    labelText: 'Impresora / dispositivo',
                    hintText: _nativo ? 'ej: POS-80C' : 'nombre de impresora (solo Windows)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _guardarDevice,
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar impresora'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _probar,
                      icon: const Icon(Icons.print),
                      label: const Text('Probar impresión'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
