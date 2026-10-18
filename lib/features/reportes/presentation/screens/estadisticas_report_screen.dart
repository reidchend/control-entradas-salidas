import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/snackbar_utils.dart';
import '../../data/reportes_repository.dart';
import '../widgets/estadisticas_cuerpo.dart';
import '../widgets/filtro_rango_fechas.dart';

/// Pantalla de estadísticas y KPIs: tarjetas de KPI del período, rankings de
/// productos por facturación Y por cantidad, ventas por día y por hora.
///
/// Las ventas anuladas quedan excluidas de todos los agregados (el KPI
/// "Ventas Anuladas" muestra cuántas se descartaron).
class EstadisticasReportScreen extends ConsumerStatefulWidget {
  const EstadisticasReportScreen({super.key});

  @override
  ConsumerState<EstadisticasReportScreen> createState() =>
      _EstadisticasReportScreenState();
}

class _EstadisticasReportScreenState
    extends ConsumerState<EstadisticasReportScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();
  Map<String, dynamic> _kpis = {};
  List<Map<String, dynamic>> _topFacturacion = [];
  List<Map<String, dynamic>> _topCantidad = [];
  List<Map<String, dynamic>> _tendencia = [];
  List<Map<String, dynamic>> _porHora = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _actualizar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas y KPIs'),
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
                _filtros(esMovil: false),
                const Divider(height: 1),
                Expanded(child: _contenido()),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _filtros(esMovil: true)),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              ..._contenidoSlivers(),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Filtros (fechas + actualizar)
  // -------------------------------------------------------------------------

  Widget _filtros({required bool esMovil}) {
    return FiltroRangoFechas(
      desde: _desde,
      hasta: _hasta,
      esMovil: esMovil,
      actualizando: _cargando,
      etiquetaAccion: 'Actualizar KPIs',
      onDesdeChanged: (d) => setState(() => _desde = d),
      onHastaChanged: (d) => setState(() => _hasta = d),
      onActualizar: _actualizar,
    );
  }

  // -------------------------------------------------------------------------
  // Contenido
  // -------------------------------------------------------------------------

  Widget _contenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _cuerpo(),
    );
  }

  List<Widget> _contenidoSlivers() {
    if (_cargando) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.all(24),
        sliver: SliverToBoxAdapter(child: _cuerpo()),
      ),
    ];
  }

  Widget _cuerpo() {
    return EstadisticasCuerpo(
      kpis: _kpis,
      topFacturacion: _topFacturacion,
      topCantidad: _topCantidad,
      tendencia: _tendencia,
      porHora: _porHora,
    );
  }

  // -------------------------------------------------------------------------
  // Datos
  // -------------------------------------------------------------------------

  Future<void> _actualizar() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(reportesRepoProvider);
      // Las cuatro consultas se disparan juntas y se esperan en paralelo.
      final fKpis = repo.getKPIs(desde: _desde, hasta: _hasta);
      final fTops =
          repo.getTopProductosRankings(desde: _desde, hasta: _hasta, limit: 10);
      final fTendencia = repo.getTendenciaVentas(desde: _desde, hasta: _hasta);
      final fPorHora = repo.getVentasPorHora(desde: _desde, hasta: _hasta);

      final kpis = await fKpis;
      final tops = await fTops;
      final tendencia = await fTendencia;
      final porHora = await fPorHora;

      if (mounted) {
        setState(() {
          _kpis = kpis;
          _topFacturacion = tops.porFacturacion;
          _topCantidad = tops.porCantidad;
          _tendencia = tendencia;
          _porHora = porHora;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        _snack('Error: $e');
      }
    }
  }

  void _exportar() {
    _snack('Exportar reporte estadístico - pendiente');
  }

  void _snack(String msg) {
    showErrorSnackBar(context, msg);
  }
}
