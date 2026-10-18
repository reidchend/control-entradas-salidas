import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/usuarios_providers.dart';
import '../../../../core/auth/usuarios_repository.dart';
import '../../../../core/models/pos_cierre_models.dart';
import '../../../../core/models/usuario.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../data/cierres_repository.dart';
import '../dialogs/reenviar_cierre_dialog.dart';
import '../widgets/cierre_card.dart';
import '../widgets/cierre_detalle_dialog.dart';
import '../widgets/cierre_resumen.dart';

/// Pantalla de historial de cierres de caja (módulo inventario).
///
/// Muestra el cajero de cada cierre, permite filtrar por cajero y
/// reenviar los reportes (simple/detallado) por WhatsApp.
class CierresHistorialScreen extends ConsumerStatefulWidget {
  const CierresHistorialScreen({super.key});

  @override
  ConsumerState<CierresHistorialScreen> createState() =>
      _CierresHistorialScreenState();
}

class _CierresHistorialScreenState extends ConsumerState<CierresHistorialScreen> {
  DateTime? _desde;
  DateTime? _hasta;
  int? _usuarioId;
  List<CierreCaja> _cierres = [];
  List<Usuario> _cajeros = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _desde = DateTime.now().subtract(const Duration(days: 30));
    _hasta = DateTime.now();
    _cargar();
    _cargarCajeros();
  }

  Future<void> _cargarCajeros() async {
    final repo = ref.read(usuariosRepoProvider);
    if (repo == null) return;
    try {
      final lista = await repo.listarPorModulo(UsuariosRepository.moduloPos);
      if (mounted) setState(() => _cajeros = lista);
    } catch (_) {
      // Sin cajeros el filtro queda como "Todos"; no bloquea la pantalla.
    }
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(cierresRepoProvider);
      _cierres = await repo.getCierres(
        desde: _desde,
        hasta: _hasta,
        usuarioId: _usuarioId,
        limit: 100,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Cierres'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Exportar',
            onPressed: _exportar,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 600;
          if (!esMovil) {
            return Column(
              children: [
                _buildFiltros(esMovil: false),
                const Divider(height: 1),
                Expanded(child: _contenido(scheme, esMovil: false)),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildFiltros(esMovil: true)),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              ..._contenidoSlivers(scheme),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Filtros (fechas + cajero + actualizar)
  // -------------------------------------------------------------------------

  Widget _buildFiltros({required bool esMovil}) {
    final scheme = Theme.of(context).colorScheme;
    final actualizar = FilledButton.icon(
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Actualizar'),
      onPressed: _cargando ? null : _cargar,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: esMovil
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker(
                          'Desde', _desde, (d) => setState(() => _desde = d),
                          width: double.infinity),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDatePicker(
                          'Hasta', _hasta, (d) => setState(() => _hasta = d),
                          width: double.infinity),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDropdownCajero(width: double.infinity),
                const SizedBox(height: 8),
                actualizar,
              ],
            )
          : Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildDatePicker(
                    'Desde', _desde, (d) => setState(() => _desde = d)),
                _buildDatePicker(
                    'Hasta', _hasta, (d) => setState(() => _hasta = d)),
                _buildDropdownCajero(width: 200),
                actualizar,
              ],
            ),
    );
  }

  Widget _buildDropdownCajero({required double width}) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<int?>(
        initialValue: _usuarioId,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Cajero',
          isDense: true,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outline, size: 18),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
          for (final u in _cajeros)
            DropdownMenuItem<int?>(
              value: u.id,
              child: Text(u.nombre,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
            ),
        ],
        onChanged: _cargando
            ? null
            : (v) {
                setState(() => _usuarioId = v);
                _cargar();
              },
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? value,
      ValueChanged<DateTime> onChanged,
      {double? width}) {
    return SizedBox(
      width: width ?? 160,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(value != null
              ? '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'
              : 'Seleccionar'),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Contenido (resumen + lista de cierres)
  // -------------------------------------------------------------------------

  Widget _contenido(ColorScheme scheme, {required bool esMovil}) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cierres.isEmpty) return _vacio(scheme);

    final lista = _buildLista(scheme, padding: 16);
    if (esMovil) return lista;
    return Column(
      children: [
        _buildResumen(scheme),
        Expanded(child: lista),
      ],
    );
  }

  List<Widget> _contenidoSlivers(ColorScheme scheme) {
    if (_cargando) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_cierres.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _vacio(scheme)),
      ];
    }
    return [
      SliverToBoxAdapter(child: _buildResumen(scheme)),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList.separated(
          itemCount: _cierres.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _buildItem(index),
        ),
      ),
    ];
  }

  Widget _vacio(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history,
              size: 64, color: scheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Sin cierres en el período',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('Ajusta los filtros e intenta de nuevo',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildResumen(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerHighest,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 24,
        runSpacing: 12,
        children: [
          CierreResumenCard(
              label: 'Total Cierres',
              valor: _cierres.length.toString(),
              icon: Icons.history,
              color: Colors.blue),
          CierreResumenCard(
              label: 'Caja Inicial Total',
              valor: '\$${_totalInicial.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              color: Colors.green),
          CierreResumenCard(
              label: 'Ventas Totales',
              valor: '\$${_totalVentas.toStringAsFixed(2)}',
              icon: Icons.point_of_sale,
              color: Colors.orange),
          CierreResumenCard(
              label: 'Caja Final Total',
              valor: '\$${_totalFinal.toStringAsFixed(2)}',
              icon: Icons.savings,
              color: Colors.purple),
        ],
      ),
    );
  }

  Widget _buildLista(ColorScheme scheme, {required double padding}) {
    return ListView.separated(
      padding: EdgeInsets.all(padding),
      itemCount: _cierres.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildItem(index),
    );
  }

  Widget _buildItem(int index) {
    final c = _cierres[index];
    return CierreCard(
      cierre: c,
      onTap: () => _verDetalle(c),
      onReenviar: () => _reenviar(c),
    );
  }

  double get _totalInicial => _cierres.fold(0.0, (s, c) => s + c.cajaInicial);
  double get _totalVentas => _cierres.fold(0.0, (s, c) => s + c.totalVentas);
  double get _totalFinal => _cierres.fold(0.0, (s, c) => s + c.cajaFinal);

  void _verDetalle(CierreCaja cierre) {
    showDialog(
      context: context,
      builder: (_) => CierreDetalleDialog(
        cierre: cierre,
        onReenviar: () => _reenviar(cierre),
      ),
    );
  }

  void _reenviar(CierreCaja cierre) {
    showDialog(
      context: context,
      builder: (_) => ReenviarCierreDialog(cierre: cierre),
    );
  }

  void _exportar() {
    _snack('Exportar a Excel/PDF - pendiente');
  }

  void _snack(String msg) {
    showErrorSnackBar(context, msg);
  }
}
