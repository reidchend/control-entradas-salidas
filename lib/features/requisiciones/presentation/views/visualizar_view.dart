import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/requisicion.dart';
import '../../../../core/utils/web_utils.dart';
import '../../../../core/widgets/error_display.dart';
import '../../data/requisiciones_providers.dart';

class VisualizarView extends ConsumerStatefulWidget {
  const VisualizarView({
    super.key,
    required this.req,
    required this.onBack,
  });

  final Requisicion req;
  final VoidCallback onBack;

  @override
  ConsumerState<VisualizarView> createState() => _VisualizarViewState();
}

class _VisualizarViewState extends ConsumerState<VisualizarView> {
  List<RequisicionDetalle> _detalles = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final repo = ref.read(requisicionesRepoProvider);
      if (repo == null) {
        throw Exception('Supabase no configurado. Verifica la conexion.');
      }
      final detalles = await repo.getDetalles(widget.req.id);
      if (mounted) {
        setState(() {
          _detalles = detalles;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  String _mensaje() {
    final lines = <String>[
      '*Requisición #${widget.req.numero}*',
      'Estado: ${widget.req.estado.toUpperCase()}',
      'Origen: ${widget.req.origen}',
      'Destino: ${widget.req.destino}',
      if (widget.req.observaciones != null &&
          widget.req.observaciones!.isNotEmpty)
        'Observaciones: ${widget.req.observaciones}',
      '',
      '*Detalles:*',
      for (final d in _detalles)
        '• ${d.ingrediente}: ${d.cantidad.toStringAsFixed(3)} ${d.unidad}',
    ];
    return lines.join('\n');
  }

  Future<void> _compartirWhatsApp() async {
    final msg = _mensaje();
    final url =
        'https://wa.me/?text=${Uri.encodeComponent(msg)}';
    openInNewTab(url);
    _snack('Abriendo WhatsApp...');
  }

  Future<void> _copiar() async {
    final msg = _mensaje();
    await Clipboard.setData(ClipboardData(text: msg));
    if (mounted) _snack('Requisición copiada al portapapeles');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(scheme),
        const SizedBox(height: 10),
        _infoCard(scheme),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Detalles de Productos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Divider(height: 1, color: scheme.outlineVariant),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorDisplay(
                      error: Exception(_error),
                      onRetry: _cargar,
                    )
                  : _detalles.isEmpty
                      ? Center(
                          child: Text('Sin detalles',
                              style: TextStyle(color: scheme.outline)),
                        )
                      : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _detalles.length,
                  itemBuilder: (context, i) {
                    final d = _detalles[i];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(d.ingrediente,
                                style: TextStyle(color: scheme.onSurface)),
                          ),
                          Text(
                            '${d.cantidad.toStringAsFixed(3)} ${d.unidad}',
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'Volver',
            onPressed: widget.onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requisición #${widget.req.numero}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Estado: ${widget.req.estado.toUpperCase()}',
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.share_rounded),
            iconColor: scheme.primary,
            tooltip: 'Compartir',
            onSelected: (v) {
              if (v == 'whatsapp') _compartirWhatsApp();
              if (v == 'copiar') _copiar();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'whatsapp',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.chat),
                  title: Text('Compartir por WhatsApp'),
                ),
              ),
              PopupMenuItem(
                value: 'copiar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.content_copy),
                  title: Text('Copiar al portapapeles'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard(ColorScheme scheme) {
    final req = widget.req;
    Widget fila(String label, String valor) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Text(valor,
                  style: TextStyle(color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            fila('Origen:', req.origen),
            fila('Destino:', req.destino),
            fila('Observaciones:',
                (req.observaciones ?? '').isEmpty
                    ? 'Sin observaciones'
                    : req.observaciones!),
          ],
        ),
      ),
    );
  }
}
