import 'package:flutter/material.dart';

import '../data/activo.dart';
import '../data/activos_repository.dart';
import '../data/grupo_activos.dart';
import 'dialogs/cantidad_unidades_dialog.dart';
import 'dialogs/confirmar_dialog.dart';
import 'dialogs/mover_unidades_dialog.dart';
import 'dialogs/unidades_grupo_sheet.dart';

/// Acciones compartidas sobre un grupo de unidades.
///
/// Los paneles (detalle de un tipo y vista filtrada) muestran la misma tarjeta
/// agrupada; concentrar acá los diálogos y las escrituras evita que uno de los
/// dos quede con una versión vieja del flujo.
class GrupoAcciones {
  GrupoAcciones({
    required this.context,
    required this.repo,
    required this.onRecargar,
    required this.onEditarUnidad,
  });

  final BuildContext context;
  final ActivosRepository repo;
  final Future<void> Function() onRecargar;
  final Future<void> Function(Activo unidad) onEditarUnidad;

  Future<void> agregar(GrupoActivos grupo) async {
    try {
      final creada = await repo.createActivo(_clon(grupo.plantilla));
      if (!context.mounted) return;
      await onRecargar();
      _snack(creada.codigo == null
          ? 'Unidad agregada'
          : 'Unidad agregada: ${creada.codigo}');
    } catch (e) {
      _snack('No se pudo agregar: $e', error: true);
    }
  }

  Future<void> quitarUna(GrupoActivos grupo) async {
    final unidad = grupo.unidades.reduce(
      (a, b) => a.id > b.id ? a : b,
    );
    final quedan = grupo.cantidad - 1;
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Quitar una unidad',
      mensaje: 'Se eliminará ${_codigo(unidad)} de '
          '«${grupo.plantilla.nombre}» en ${_ubicacion(grupo)}.\n\n'
          '${quedan == 0 ? 'No quedará ninguna unidad en este grupo.' : 'Quedarán $quedan unidades.'}',
      accion: 'Quitar',
    );
    if (!ok || !context.mounted) return;
    await _borrar([unidad.id]);
  }

  Future<void> cambiarCantidad(GrupoActivos grupo) async {
    final nueva = await showCantidadUnidadesDialog(
      context,
      cantidadActual: grupo.cantidad,
      max: grupo.cantidad + 500,
    );
    if (nueva == null || nueva == grupo.cantidad || !context.mounted) return;

    if (nueva > grupo.cantidad) {
      final faltan = nueva - grupo.cantidad;
      try {
        await repo.createActivos(
          List<Activo>.generate(faltan, (_) => _clon(grupo.plantilla)),
        );
        if (!context.mounted) return;
        await onRecargar();
        _snack(faltan == 1
            ? 'Se agregó 1 unidad'
            : 'Se agregaron $faltan unidades');
      } catch (e) {
        _snack('No se pudo cambiar la cantidad: $e', error: true);
      }
      return;
    }

    final quitar = grupo.cantidad - nueva;
    final ids = grupo.idsUltimas(quitar);
    final codigos = grupo.codigosUltimas(quitar);
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Quitar $quitar ${quitar == 1 ? 'unidad' : 'unidades'}',
      mensaje: 'Se eliminarán las unidades más nuevas de '
          '«${grupo.plantilla.nombre}» en ${_ubicacion(grupo)}:\n\n'
          '${_resumenCodigos(codigos)}\n\n'
          'Quedarán ${grupo.cantidad - quitar}.',
      accion: 'Quitar',
    );
    if (!ok || !context.mounted) return;
    await _borrar(ids);
  }

  Future<void> mover(GrupoActivos grupo) async {
    List<String> ubicaciones = const [];
    try {
      ubicaciones = await repo.getUbicaciones();
    } catch (_) {
      ubicaciones = const [];
    }
    if (!context.mounted) return;

    final mov = await showMoverUnidadesDialog(
      context,
      cantidad: grupo.cantidad,
      ubicacionActual: grupo.plantilla.ubicacion,
      ubicaciones: ubicaciones,
      codigos: grupo.codigosUltimas(grupo.cantidad),
    );
    if (mov == null || !context.mounted) return;

    final ids = mov.cantidad >= grupo.cantidad
        ? grupo.ids
        : grupo.idsUltimas(mov.cantidad);
    try {
      await repo.moverActivos(ids, mov.ubicacion);
      if (!context.mounted) return;
      await onRecargar();
      final destino = (mov.ubicacion ?? '').trim();
      _snack(ids.length == 1
          ? 'Unidad movida a ${destino.isEmpty ? 'sin ubicación' : '«$destino»'}'
          : '${ids.length} unidades movidas a '
              '${destino.isEmpty ? 'sin ubicación' : '«$destino»'}');
    } catch (e) {
      _snack('No se pudieron mover: $e', error: true);
    }
  }

  Future<void> verUnidades(GrupoActivos grupo) {
    return showUnidadesGrupoSheet(
      context,
      grupo: grupo,
      onEditar: (u) => onEditarUnidad(u),
      onDesactivar: _desactivarUnidad,
      onEliminar: _eliminarUnidad,
    );
  }

  Future<void> eliminarTodas(GrupoActivos grupo) async {
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Eliminar todas',
      mensaje: '¿Eliminar definitivamente las ${grupo.cantidad} unidades de '
          '«${grupo.plantilla.nombre}» en ${_ubicacion(grupo)}?\n\n'
          '${_resumenCodigos(grupo.codigos)}',
      accion: 'Eliminar',
    );
    if (!ok || !context.mounted) return;
    await _borrar(grupo.ids);
  }

  Future<void> reactivar(GrupoActivos grupo) async {
    try {
      await repo.setActivosActivo(grupo.ids, true);
      if (!context.mounted) return;
      await onRecargar();
      _snack(grupo.cantidad == 1
          ? 'Unidad reactivada'
          : '${grupo.cantidad} unidades reactivadas');
    } catch (e) {
      _snack('No se pudieron reactivar: $e', error: true);
    }
  }

  Future<void> _desactivarUnidad(Activo unidad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar unidad'),
        content: Text('¿Desactivar ${_codigo(unidad)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await repo.deactivateActivo(unidad.id);
      if (!context.mounted) return;
      await onRecargar();
      _snack('${_codigo(unidad)} desactivada');
    } catch (e) {
      _snack('No se pudo desactivar: $e', error: true);
    }
  }

  Future<void> _eliminarUnidad(Activo unidad) async {
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Eliminar unidad',
      mensaje: '¿Eliminar definitivamente ${_codigo(unidad)}?',
      accion: 'Eliminar',
    );
    if (!ok || !context.mounted) return;
    await _borrar([unidad.id]);
  }

  Future<void> _borrar(List<int> ids) async {
    try {
      await repo.deleteActivos(ids);
      if (!context.mounted) return;
      await onRecargar();
      _snack(ids.length == 1 ? 'Unidad eliminada' : '${ids.length} unidades eliminadas');
    } catch (e) {
      _snack('No se pudo eliminar: $e', error: true);
    }
  }

  Activo _clon(Activo a) => Activo(
        id: 0,
        tipoId: a.tipoId,
        ubicacion: a.ubicacion,
        estado: a.estado,
        valor: a.valor,
        fecha: a.fecha,
        observaciones: a.observaciones,
        activo: true,
      );

  String _codigo(Activo a) {
    final c = (a.codigo ?? '').trim();
    return c.isEmpty ? 'la unidad' : c;
  }

  String _ubicacion(GrupoActivos g) {
    final u = (g.plantilla.ubicacion ?? '').trim();
    return u.isEmpty ? 'sin ubicación' : '«$u»';
  }

  String _resumenCodigos(List<String> codigos) {
    if (codigos.isEmpty) return '';
    if (codigos.length <= 3) return codigos.join(', ');
    return '${codigos.first} … ${codigos.last}';
  }

  void _snack(String msg, {bool error = false}) {
    if (!context.mounted) return;
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? colors.error : null,
      ),
    );
  }
}
