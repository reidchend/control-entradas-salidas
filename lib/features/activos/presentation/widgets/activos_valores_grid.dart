import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activos_repository.dart';

/// GridView de valores de una dimensión de activos (ubicación, grupo, modelo,
/// estado...) con su conteo de activos. Estilo igual al grid de categorías.
class ActivosValoresGrid extends ConsumerWidget {
  const ActivosValoresGrid({
    super.key,
    required this.repo,
    required this.columna,
    required this.singular,
    required this.icono,
    required this.color,
    required this.onSelect,
    this.onCrear,
  });

  final ActivosRepository repo;
  final String columna;
  final String singular;
  final IconData icono;
  final Color color;
  final ValueChanged<String> onSelect;
  final VoidCallback? onCrear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.getValoresConConteo(columna),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final items = snap.data ?? const <Map<String, dynamic>>[];

        final crear = onCrear;
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
                label: 'Nueva $singular',
                onCreate: crear,
              );
            }
            final item = items[i - (crear != null ? 1 : 0)];
            final valor = (item['valor'] as String?) ?? '';
            return _ValorCard(
              valor: valor,
              conteo: (item['n'] as num?)?.toInt() ?? 0,
              icono: icono,
              color: color,
              onTap: () => onSelect(valor),
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
  });

  final String valor;
  final int conteo;
  final IconData icono;
  final Color color;
  final VoidCallback onTap;

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
              Text(
                valor,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}