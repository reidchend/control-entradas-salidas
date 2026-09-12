import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_models.dart';
import '../../../core/utils/modal_sizing.dart';
import '../data/pos_comanda_models.dart';
import '../data/pos_providers.dart';
import '../data/pos_session.dart';
import 'widgets/pos_top_bar.dart';

/// Turnos y cajas del POS (port de `VentasView` de ventas.py, flujo de turnos):
/// lista los turnos de caja (con apertura/cierre, ventas del turno y monto
/// final de caja); al entrar a un turno se ven sus ventas, su detalle, la
/// anulación (restaura stock, reabre comanda y permite corregir) y el cierre.
class VentasScreen extends ConsumerStatefulWidget {
  const VentasScreen({
    super.key,
    required this.sesion,
    required this.onBack,
    required this.onLogout,
    required this.onCorregirVenta,
  });

  final PosSesionActiva sesion;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  /// Después de anular: navega a la comanda de la mesa/habitación devuelta.
  final void Function(int? mesaId, int? habitacionId) onCorregirVenta;

  @override
  ConsumerState<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends ConsumerState<VentasScreen> {
  static const _limite = 40;

  final _turnos =
      <({PosSesion sesion, String? usuarioNombre, int ventas, double totalVentas})>[];
  Map<int, String> _mesas = {};
  Map<int, String> _habs = {};
  int? _bordeId;
  bool _tieneMas = true;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargarUbicaciones();
    _cargarPagina(reset: true);
  }

  /// Mapa {id: numero} de mesas y habitaciones para las tarjetas de venta.
  Future<void> _cargarUbicaciones() async {
    final repo = ref.read(posRepoProvider)!;
    final mesas = await repo.getMesas();
    final habs = await repo.getHabitaciones();
    if (!mounted) return;
    setState(() {
      _mesas = {for (final m in mesas) m.id: m.numero};
      _habs = {for (final h in habs) h.id: h.numero};
    });
  }

  String _lugar(PosVenta v) {
    if (v.mesaId != null) {
      final n = _mesas[v.mesaId];
      return n != null ? 'Mesa $n' : 'Mesa ${v.mesaId}';
    }
    if (v.habitacionId != null) {
      final n = _habs[v.habitacionId];
      return n != null ? 'Habitación $n' : 'Habitación ${v.habitacionId}';
    }
    return 'Sin mesa';
  }

  Future<void> _cargarPagina({required bool reset}) async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
      if (reset) {
        _turnos.clear();
        _bordeId = null;
        _tieneMas = true;
      }
    });
    try {
      final repo = ref.read(posRepoProvider)!;
      final turnos = await repo.getSesiones(
          limit: _limite, beforeId: _bordeId);
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _turnos.addAll(turnos);
        if (turnos.isNotEmpty) {
          _bordeId = turnos.last.sesion.id;
        }
        _tieneMas = turnos.length >= _limite;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _tieneMas = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar los turnos: $e')),
      );
    }
  }

  Future<void> _verTurno(
    ({PosSesion sesion, String? usuarioNombre, int ventas, double totalVentas}) turno,
  ) async {
    final repo = ref.read(posVentasRepoProvider)!;
    final ventas = await repo.getVentasPorSesion(turno.sesion.id);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _DetalleTurnoDialog(
        turno: turno,
        ventas: ventas,
        lugar: _lugar,
        onAnular: _anularVenta,
        onVerDetalle: _verDetalle,
      ),
    );
  }

  Future<void> _anularVenta(PosVenta venta) async {
    if (!mounted) return;
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => _AnularVentaDialog(venta: venta),
    );
    if (motivo == null || !mounted) return;
    final repo = ref.read(posVentasRepoProvider)!;
    try {
      await repo.revertirMovimientosVenta(venta.id,
          registradoPor: widget.sesion.usuario.nombre);
      await repo.anularVenta(venta.id,
          anuladaPor: widget.sesion.usuario.nombre, motivo: motivo);
      final comandaId = venta.comandaId;
      if (comandaId != null) await repo.reabrirComanda(comandaId);
      ref.invalidate(ventasProvider);
      ref.invalidate(ultimaVentaVigenteProvider);
      ref.invalidate(mesasOcupadasProvider);
      ref.invalidate(habitacionesOcupadasProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Venta anulada. Corrija la comanda y cobre de nuevo.')),
      );
      widget.onCorregirVenta(venta.mesaId, venta.habitacionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al anular: $e')),
      );
    }
  }

  Future<void> _verDetalle(PosVenta venta) async {
    final repo = ref.read(posVentasRepoProvider)!;
    final posRepo = ref.read(posRepoProvider)!;
    final vendedor = venta.usuarioId == null
        ? null
        : (await posRepo.getUsuario(venta.usuarioId!))?.nombre;
    final corr = venta.ventaAnulaId == null
        ? null
        : (await repo.getVenta(venta.ventaAnulaId!))?.correlativo;
    final movs = await repo.getMovimientosVenta(venta.id);
    final lugar = _lugar(venta);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _DetalleVentaDialog(
        venta: venta,
        vendedor: vendedor,
        correlativoAnulada: corr,
        descargos: movs,
        lugar: lugar,
      ),
    );
  }

  void _anularUltima(PosVenta? ultima) {
    if (ultima != null) _anularVenta(ultima);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ultima = ref.watch(ultimaVentaVigenteProvider).valueOrNull;

    return Scaffold(
      body: Column(
        children: [
          PosTopBar(
            usuario: widget.sesion.usuario,
            titulo: 'Ventas',
            onBack: widget.onBack,
            onLogout: widget.onLogout,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Turnos y cajas',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cada turno agrupa las ventas de un cajero y su cierre de caja',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF5350),
                  ),
                  onPressed: ultima == null ? null : () => _anularUltima(ultima),
                  icon: const Icon(Icons.undo),
                  label: const Text('Anular última venta'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _turnos.isEmpty && _cargando
                ? const Center(child: CircularProgressIndicator())
                : _turnos.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        itemCount: _turnos.length + 1,
                        itemBuilder: (context, i) {
                          if (i == _turnos.length) {
                            return _footer();
                          }
                          final t = _turnos[i];
                          return _TurnoCard(
                            turno: t,
                            onTap: () => _verTurno(t),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            _turnos.isEmpty
                ? ''
                : 'Mostrando los ${_turnos.length} turnos más recientes',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (_tieneMas && !_cargando)
            OutlinedButton.icon(
              onPressed: () => _cargarPagina(reset: false),
              icon: const Icon(Icons.expand_more),
              label: const Text('Cargar más turnos'),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.work_history_outlined, size: 80, color: scheme.outline),
          const SizedBox(height: 16),
          Text('No hay turnos registrados',
              style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Cierre sesión para generar el primer turno y su cierre de caja',
              style: TextStyle(fontSize: 13, color: scheme.outline)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tarjeta de turno
// ===========================================================================

class _TurnoCard extends StatelessWidget {
  const _TurnoCard({required this.turno, required this.onTap});

  final ({PosSesion sesion, String? usuarioNombre, int ventas, double totalVentas}) turno;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = turno.sesion;
    final abierto = s.cerradaEn == null;
    final fechaA = (s.abiertaEn ?? '').substring(0, (s.abiertaEn ?? '').length > 16 ? 16 : (s.abiertaEn ?? '').length).replaceFirst('T', ' ');
    final fechaC = s.cerradaEn == null
        ? '\u2014'
        : (s.cerradaEn ?? '').substring(0, (s.cerradaEn ?? '').length > 16 ? 16 : (s.cerradaEn ?? '').length).replaceFirst('T', ' ');
    final cajaFinal = abierto ? null : s.cajaFinal;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: abierto ? const Color(0xFF4CAF50).withValues(alpha: 0.5) : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: abierto ? const Color(0xFF2E7D32) : const Color(0xFF546E7A),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${turno.ventas}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            turno.usuarioNombre ?? 'Cajero #${s.usuarioId}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          texto: abierto ? 'ABIERTO' : 'CERRADO',
                          colorFondo:
                              abierto ? const Color(0xFF1B5E20) : const Color(0xFF37474F),
                          colorTexto:
                              abierto ? const Color(0xFF4CAF50) : const Color(0xFF90A4AE),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Apertura $fechaA · Cierre $fechaC',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${turno.ventas} ventas · \$${turno.totalVentas.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('CAJA FINAL',
                      style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.bold, color: scheme.outline)),
                  const SizedBox(height: 2),
                  Text(
                    cajaFinal == null
                        ? '\$${turno.totalVentas.toStringAsFixed(2)}*'
                        : '\$${cajaFinal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: abierto ? const Color(0xFF4CAF50) : const Color(0xFF26A69A),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Diálogo: detalle del turno (cierre + ventas)
// ===========================================================================

class _DetalleTurnoDialog extends StatelessWidget {
  const _DetalleTurnoDialog({
    required this.turno,
    required this.ventas,
    required this.lugar,
    required this.onAnular,
    required this.onVerDetalle,
  });

  final ({PosSesion sesion, String? usuarioNombre, int ventas, double totalVentas}) turno;
  final List<PosVenta> ventas;
  final String Function(PosVenta) lugar;
  final void Function(PosVenta) onAnular;
  final void Function(PosVenta) onVerDetalle;

  String _fecha(String? d) =>
      d == null ? '\u2014' : d.replaceFirst('T', ' ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = turno.sesion;
    final abierto = s.cerradaEn == null;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: modalContentWidth(context), maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Turno #${s.id}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  _Badge(
                    texto: abierto ? 'ABIERTO' : 'CERRADO',
                    colorFondo:
                        abierto ? const Color(0xFF1B5E20) : const Color(0xFF37474F),
                    colorTexto:
                        abierto ? const Color(0xFF4CAF50) : const Color(0xFF90A4AE),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fila(context, 'Cajero', turno.usuarioNombre ?? '-'),
                  _fila(context, 'Apertura', _fecha(s.abiertaEn)),
                  _fila(context, 'Cierre', _fecha(s.cerradaEn)),
                  _fila(context, 'Ventas del turno', '${turno.ventas}'),
                  _fila(context, 'Total vendido',
                      '\$${turno.totalVentas.toStringAsFixed(2)}'),
                  _fila(context, 'Caja inicial',
                      '\$${s.cajaInicial.toStringAsFixed(2)}'),
                  _fila(
                    context,
                    'Caja final',
                    abierto
                        ? '\$${turno.totalVentas.toStringAsFixed(2)}*'
                        : '\$${(s.cajaFinal ?? 0).toStringAsFixed(2)}',
                    destacado: true,
                  ),
                  const Divider(height: 20),
                  Text('VENTAS DEL TURNO',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Flexible(
              child: ventas.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Sin ventas en este turno',
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: scheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: ventas.length,
                      itemBuilder: (context, i) {
                        final v = ventas[i];
                        return _VentaCard(
                          venta: v,
                          lugar: lugar(v),
                          onTap: () => onVerDetalle(v),
                          onAnular: v.estado == 'vigente'
                              ? () => onAnular(v)
                              : null,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('* Caja abierta: el monto mostrado es el total vendido',
                  style: TextStyle(fontSize: 10, color: scheme.outline)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, String label, String value,
      {bool destacado = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: destacado ? 15 : 12,
                color: destacado ? const Color(0xFF26A69A) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tarjeta de venta
// ===========================================================================

class _VentaCard extends StatelessWidget {
  const _VentaCard({
    required this.venta,
    required this.lugar,
    required this.onTap,
    this.onAnular,
  });

  final PosVenta venta;
  final String lugar;
  final VoidCallback onTap;
  final VoidCallback? onAnular;

  String get _numero {
    final c = venta.correlativo;
    if (c != null) return c.toString().padLeft(5, '0');
    return '#${venta.comandaId ?? venta.id}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vigente = venta.estado == 'vigente';
    final fecha = (venta.createdAt ?? '')
        .substring(0, (venta.createdAt ?? '').length > 16 ? 16 : (venta.createdAt ?? '').length)
        .replaceFirst('T', ' ');

    final esCorreccion = venta.ventaAnulaId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF1E88E5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _numero,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(_numero,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          texto: vigente ? 'VIGENTE' : 'ANULADA',
                          colorFondo: vigente
                              ? const Color(0xFF1B5E20)
                              : const Color(0xFFB71C1C),
                          colorTexto: vigente
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFEF5350),
                        ),
                        if (esCorreccion) ...[
                          const SizedBox(width: 8),
                          Text('CORRECCIÓN',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.tertiary)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(fecha,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                        Text(' · ',
                            style: TextStyle(
                                fontSize: 11, color: scheme.outline)),
                        Text(lugar,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${venta.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: vigente ? const Color(0xFF4CAF50) : scheme.outline,
                    ),
                  ),
                  if (venta.tasaBs != null && venta.tasaBs! > 0)
                    Text(
                      'Bs ${formatearBs(venta.total * venta.tasaBs!)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color:
                            vigente ? const Color(0xFF26A69A) : scheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              if (onAnular != null)
                IconButton(
                  tooltip: 'Anular venta',
                  onPressed: onAnular,
                  icon: const Icon(Icons.undo, color: Color(0xFFEF5350)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.texto,
    required this.colorFondo,
    required this.colorTexto,
  });

  final String texto;
  final Color colorFondo;
  final Color colorTexto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.bold, color: colorTexto),
      ),
    );
  }
}

// ===========================================================================
// Diálogo de detalle
// ===========================================================================

class _DetalleVentaDialog extends StatelessWidget {
  const _DetalleVentaDialog({
    required this.venta,
    required this.vendedor,
    required this.correlativoAnulada,
    required this.descargos,
    required this.lugar,
  });

  final PosVenta venta;
  final String? vendedor;
  final int? correlativoAnulada;
  final List<Map<String, dynamic>> descargos;
  final String lugar;

  String get _numero {
    final c = venta.correlativo;
    if (c != null) return c.toString().padLeft(5, '0');
    return '#${venta.comandaId ?? venta.id}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vigente = venta.estado == 'vigente';
    final items = ComandaItem.listFromJson(venta.itemsJson);

    return AlertDialog(
      title: Row(
        children: [
          Text(_numero,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          _Badge(
            texto: vigente ? 'VIGENTE' : 'ANULADA',
            colorFondo:
                vigente ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
            colorTexto:
                vigente ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: modalContentWidth(context)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _fila(context, 'Fecha',
                  (venta.createdAt ?? '').replaceFirst('T', ' ')),
              _fila(context, 'Vendedor', vendedor ?? '-'),
              _fila(context, 'Mesa / Hab.', lugar),
              if (correlativoAnulada != null)
                _fila(context, 'Corrige a', '#${correlativoAnulada.toString().padLeft(5, '0')}'),
              const Divider(height: 20),
              Text('ITEMS VENDIDOS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(it.nombre,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                      Text('x${it.cantidad}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      Text('\$${(it.subtotal).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4CAF50))),
                    ],
                  ),
                ),
              if (descargos.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('DESCARGOS DE INVENTARIO',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                for (final m in descargos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${m['producto_nombre'] ?? '?'}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        Text('${-double.parse('${m['cantidad'] ?? 0}')}',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFEF5350))),
                        const SizedBox(width: 6),
                        Text('${m['almacen'] ?? '?'}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: scheme.tertiary)),
                      ],
                    ),
                  ),
              ],
              const Divider(height: 20),
              Row(
                children: [
                  const Text('TOTAL',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(
                    '\$${venta.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: vigente ? const Color(0xFF4CAF50) : scheme.outline,
                    ),
                  ),
                ],
              ),
              if (venta.tasaBs != null && venta.tasaBs! > 0)
                Text(
                  'Bs ${formatearBs(venta.total * venta.tasaBs!)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF26A69A)),
                ),
              if (!vigente) ...[
                const Divider(height: 20),
                Text('ANULACIÓN',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.error)),
                _fila(context, 'Motivo', venta.motivoAnulacion ?? '-'),
                _fila(context, 'Anulada por', venta.anuladaPor ?? '-'),
                if (venta.anuladaEn != null)
                  _fila(context, 'Cuando',
                      (venta.anuladaEn ?? '').replaceFirst('T', ' ')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _fila(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Diálogo de anulación
// ===========================================================================

class _AnularVentaDialog extends StatefulWidget {
  const _AnularVentaDialog({required this.venta});

  final PosVenta venta;

  @override
  State<_AnularVentaDialog> createState() => _AnularVentaDialogState();
}

class _AnularVentaDialogState extends State<_AnularVentaDialog> {
  late final TextEditingController _motivo;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _motivo = TextEditingController(text: 'Corrección de la venta');
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    setState(() => _guardando = true);
    Navigator.of(context).pop(_motivo.text.trim().isEmpty
        ? 'Corrección de la venta'
        : _motivo.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    final numero = v.correlativo != null
        ? v.correlativo.toString().padLeft(5, '0')
        : '${v.id}';
    return AlertDialog(
      title: const Text('Anular venta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Se devolverá la venta #$numero (\$${v.total.toStringAsFixed(2)})',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Se restaura el stock, la comanda vuelve a la mesa y podrá corregir y volver a cobrar.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivo,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Motivo de la anulación',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
          onPressed: _guardando ? null : _confirmar,
          child: Text(_guardando ? 'Anulando…' : 'Anular venta'),
        ),
      ],
    );
  }
}