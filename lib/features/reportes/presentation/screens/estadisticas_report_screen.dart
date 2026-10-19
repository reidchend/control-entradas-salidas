import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/postgres_providers.dart';
import '../../../../core/network/postgres_client.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../data/reportes_repository.dart';
import '../widgets/aviso_error_banner.dart';
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

  /// Secciones que fallaron en la última carga; el banner persiste hasta que
  /// el usuario reintente (en vez de un snackbar que desaparece y deja la
  /// vista vacía sin explicación).
  String? _error;

  /// Detalle técnico del fallo, para poder copiarlo y reportarlo.
  String _detalleError = '';

  @override
  void initState() {
    super.initState();
    _actualizar();
  }

  @override
  Widget build(BuildContext context) {
    // Si la sesión con la base recién queda lista (arranque en frío) y la
    // carga inicial falló por eso, se reintenta sola en vez de dejar la
    // pantalla vacía esperando que el usuario apriete "Actualizar KPIs".
    ref.listen(postgresServiceProvider, (prev, next) {
      if (next != null && _error != null) _actualizar();
    });
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          AvisoErrorBanner(
            mensaje: _error!,
            detalle: _detalleError,
            onReintentar: _actualizar,
          ),
          const SizedBox(height: 16),
        ],
        EstadisticasCuerpo(
          kpis: _kpis,
          topFacturacion: _topFacturacion,
          topCantidad: _topCantidad,
          tendencia: _tendencia,
          porHora: _porHora,
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Datos
  // -------------------------------------------------------------------------

  Future<void> _actualizar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _detalleError = '';
    });

    // La sesión con la base puede no estar lista todavía (arranque en frío:
    // el pool consulta el túnel antes de abrir). Antes eso lanzaba
    // 'PostgreSQL no configurado' y dejaba la vista entera vacía; ahora se
    // espera al pool y, si falla, queda el banner con el detalle.
    var candidato = _repo();
    if (candidato == null) {
      try {
        await ref.read(postgresPoolProvider.future);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _cargando = false;
          _error = 'la conexión con la base de datos';
          _detalleError = 'No se pudo abrir la base de datos: $e';
        });
        return;
      }
      candidato = _repo();
    }
    final repo = candidato;
    if (repo == null) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'la conexión con la base de datos';
        _detalleError = _detalleConexion();
      });
      return;
    }

    final fallos = <String>[];
    final detalles = <String>[];

    // Las cuatro consultas siguen corriendo en paralelo, pero cada una se
    // protege por separado: si una falla, las demás se renderizan igual y el
    // fallo queda en un banner persistente con "Reintentar". Antes un solo
    // try/catch vaciaba toda la vista y solo dejaba un snackbar efímero.
    await Future.wait([
      _cargar(
        'KPIs',
        () => repo.getKPIs(desde: _desde, hasta: _hasta),
        (v) => _kpis = v,
        fallos,
        detalles,
      ),
      _cargar(
        'top de productos',
        () => repo.getTopProductosRankings(
            desde: _desde, hasta: _hasta, limit: 10),
        (v) {
          _topFacturacion = v.porFacturacion;
          _topCantidad = v.porCantidad;
        },
        fallos,
        detalles,
      ),
      _cargar(
        'ventas por día',
        () => repo.getTendenciaVentas(desde: _desde, hasta: _hasta),
        (v) => _tendencia = v,
        fallos,
        detalles,
      ),
      _cargar(
        'ventas por hora',
        () => repo.getVentasPorHora(desde: _desde, hasta: _hasta),
        (v) => _porHora = v,
        fallos,
        detalles,
      ),
    ]);

    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (fallos.isNotEmpty) {
        _error = fallos.join(', ');
        _detalleError = detalles.join('\n');
      }
    });
  }

  /// Repositorio de reportes, o `null` si la sesión todavía no está lista.
  ReportesRepository? _repo() {
    try {
      return ref.read(reportesRepoProvider);
    } catch (_) {
      return null;
    }
  }

  /// Detalle del estado de la sesión, para el botón «Copiar detalle».
  String _detalleConexion() {
    final ev = ref.read(postgresPoolProvider);
    return ev.hasError
        ? 'Pool de base de datos con error: ${ev.error}'
        : 'La sesión con la base de datos todavía no estaba lista';
  }

  /// Ejecuta [consulta] y aplica el resultado con [aplicar]; si falla, anota
  /// [etiqueta] en [fallos] (y el error en [detalles]) sin abortar el resto.
  Future<void> _cargar<T>(
    String etiqueta,
    Future<T> Function() consulta,
    void Function(T) aplicar,
    List<String> fallos,
    List<String> detalles,
  ) async {
    try {
      aplicar(await consulta());
    } catch (e) {
      fallos.add(etiqueta);
      detalles.add('[$etiqueta] $e');
    }
  }

  void _exportar() {
    _snack('Exportar reporte estadístico - pendiente');
  }

  void _snack(String msg) {
    showErrorSnackBar(context, msg);
  }
}
