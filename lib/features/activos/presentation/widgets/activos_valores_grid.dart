import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activos_repository.dart';
import '../dialogs/confirmar_dialog.dart';
import '../dialogs/renombrar_valor_dialog.dart';

/// GridView de valores de una dimensión de activos (ubicación, grupo, modelo,
/// estado...) con su conteo de activos. Estilo igual al grid de categorías.
class ActivosValoresGrid extends ConsumerStatefulWidget {
  const ActivosValoresGrid({
    super.key,
    required this.repo,
    required this.columna,
    required this.singular,
    required this.icono,
    required this.color,
    required this.onSelect,
    this.onCrear,
    this.onRenombrar,
    this.onQuitar,
  });

  final ActivosRepository repo;
  final String columna;
  final String singular;
  final IconData icono;
  final Color color;
  final ValueChanged<String> onSelect;
  final VoidCallback? onCrear;

  /// Se avisa a la pantalla qué valor cambió para que no quede seleccionado un
  /// nombre que ya no existe.
  final void Function(String antes, String despues)? onRenombrar;
  final ValueChanged<String>? onQuitar;

  @override
  ConsumerState<ActivosValoresGrid> createState() => _ActivosValoresGridState();
}

class _ActivosValoresGridState extends ConsumerState<ActivosValoresGrid> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    // Query única por instancia: evita refetch por cada tecla del buscador.
    _future = widget.repo.getValoresConConteo(widget.columna);
  }

  /// Vuelve a consultar la lista, para que un renombrado o un valor quitado se
  /// vean sin volver a entrar a la pantalla.
  void _recargar() {
    setState(() {
      _future = widget.repo.getValoresConConteo(widget.columna);
    });
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _renombrar(
    List<Map<String, dynamic>> items,
    String valor,
    int conteo,
  ) async {
    final nuevo = await showRenombrarValorDialog(
      context,
      singular: widget.singular,
      valor: valor,
      afectados: conteo,
      existentes: [for (final it in items) it['valor'] as String? ?? ''],
    );
    if (nuevo == null || !mounted) return;
    setState(() => _trabajando = true);
    try {
      await widget.repo.renombrarValor(widget.columna, valor, nuevo);
      widget.onRenombrar?.call(valor, nuevo);
      if (mounted) _recargar();
    } catch (e) {
      _error('Error al renombrar: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _quitar(String valor, int conteo) async {
    // `conteo` viene de `getValoresConConteo`, que cuenta las unidades activas
    // que usan el valor (también para grupo/modelo, donde el valor vive en el
    // tipo). Por eso el texto habla siempre de unidades.
    final unidades = conteo == 1 ? '1 unidad' : '$conteo unidades';
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Quitar ${widget.singular}',
      mensaje: '¿Quitar "$valor"?\n'
          'Las $unidades que lo tienen no se borran, solo quedan sin '
          '${widget.singular}.',
      accion: 'Quitar',
    );
    if (!ok || !mounted) return;
    setState(() => _trabajando = true);
    try {
      await widget.repo.quitarValor(widget.columna, valor);
      widget.onQuitar?.call(valor);
      if (mounted) _recargar();
    } catch (e) {
      _error('Error al quitar valor: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final items = snap.data ?? const <Map<String, dynamic>>[];

        final crear = _trabajando ? null : widget.onCrear;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisExtent: 120,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: items.length + (crear != null ? 1 : 0),
          itemBuilder: (context, i) {
            if (crear != null && i == 0) {
              return _NuevoValorCard(
                label: 'Nueva ${widget.singular}',
                onCreate: crear,
              );
            }
            final item = items[i - (crear != null ? 1 : 0)];
            final valor = (item['valor'] as String?) ?? '';
            final conteo = (item['n'] as num?)?.toInt() ?? 0;
            // La pantalla pasa `onCrear` solo en las dimensiones editables
            // (ubicación, grupo, modelo). Estados no la pasa, y sin este filtro
            // su menú dejaría al usuario renombrando algo que el repositorio
            // rechaza con `ArgumentError`.
            final puedeEditar = crear != null && !_trabajando;
            return _ValorCard(
              valor: valor,
              conteo: conteo,
              icono: widget.icono,
              color: widget.color,
              onTap: () => widget.onSelect(valor),
              onRenombrar:
                  puedeEditar ? () => _renombrar(items, valor, conteo) : null,
              onQuitar: puedeEditar ? () => _quitar(valor, conteo) : null,
            );
          },
        );
      },
    );
  }
}

class _NuevoValorCard extends StatelessWidget {
  const _NuevoValorCard({required this.label, required this.onCreate});
  final String label;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onCreate,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 32, color: colors.primary),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValorCard extends StatelessWidget {
  const _ValorCard({
    required this.valor,
    required this.conteo,
    required this.icono,
    required this.color,
    required this.onTap,
    this.onRenombrar,
    this.onQuitar,
  });

  final String valor;
  final int conteo;
  final IconData icono;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onRenombrar;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withValues(alpha: .75)],
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icono, color: Colors.white, size: 22),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$conteo',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      valor,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (onRenombrar != null || onQuitar != null)
                    _MenuValor(
                      onRenombrar: onRenombrar,
                      onQuitar: onQuitar,
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

/// Menú de mantenimiento de un valor de dimensión.
///
/// Va en las cards igual que en `TipoCard`: renombrar corrige un valor guardado
/// mal y quitar lo saca del catálogo sin borrar las unidades que lo tenían.
class _MenuValor extends StatelessWidget {
  const _MenuValor({this.onRenombrar, this.onQuitar});

  final VoidCallback? onRenombrar;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 20,
      color: Colors.white,
      // La card es un gradiente saturado: el icono necesita su propio fondo para
      // que se vea el menú al abrirlo.
      icon: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.more_vert, color: Colors.white),
      ),
      onSelected: (v) {
        if (v == 'renombrar') onRenombrar?.call();
        if (v == 'quitar') onQuitar?.call();
      },
      itemBuilder: (_) => [
        if (onRenombrar != null)
          const PopupMenuItem(value: 'renombrar', child: Text('Renombrar')),
        if (onQuitar != null)
          const PopupMenuItem(value: 'quitar', child: Text('Quitar valor')),
      ],
    );
  }
}
