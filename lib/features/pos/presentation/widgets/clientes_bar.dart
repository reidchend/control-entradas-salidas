import 'package:flutter/material.dart';

import '../data/pos_responsive.dart';

/// Barra de sub-cuentas ("clientes") dentro de una comanda.
///
/// Muestra cada cliente con su nombre y subtotal en una fila horizontal
/// (scroll si no caben), manteniendo la altura mínima. Diseñado para
/// tablets pequeñas en horizontal: chips reducidos, encabezado bajo y
/// acciones como íconos compactos.
class ClientesBar extends StatelessWidget {
  const ClientesBar({
    super.key,
    required this.clientes,
    required this.activo,
    required this.filtro,
    required this.subtotales,
    required this.nombres,
    required this.onSelect,
    required this.onVerTodos,
    required this.onNuevo,
    required this.onRenombrar,
    required this.onEliminar,
  });

  final List<int> clientes;
  final int activo;

  /// Cliente cuyos productos se están viendo; `null` = ver todos.
  final int? filtro;
  final Map<int, double> subtotales;
  final Map<int, String> nombres;

  final ValueChanged<int> onSelect;
  final VoidCallback onVerTodos;
  final VoidCallback onNuevo;
  final ValueChanged<int> onRenombrar;
  final ValueChanged<int> onEliminar;

  String etiqueta(int c) => nombres[c] ?? 'Cliente $c';

  bool get _gestionable => filtro != null && filtro != 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esPequena = MediaQuery.sizeOf(context).width <= 720;

    if (clientes.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[
      // Chip "Todos"
      ChoiceChip(
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
        label: const Text('Todos', style: TextStyle(fontSize: 9)),
        selected: filtro == null,
        onSelected: (_) => onVerTodos(),
        labelStyle: TextStyle(
          color: filtro == null ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontSize: 9,
        ),
        side: BorderSide(
          color: filtro == null ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      const SizedBox(width: 4),
      // Chips de clientes
      for (final c in clientes)
        _ChipCliente(
          clave: c,
          etiqueta: etiqueta(c),
          subtotal: subtotales[c] ?? 0,
          seleccionado: c == filtro,
          scheme: scheme,
          esActivo: c == activo,
          onTap: () {
            if (c == filtro) {
              if (c == 1) {
                onVerTodos();
              } else {
                onRenombrar(c);
              }
            } else {
              onSelect(c);
            }
          },
          onLongPress: c != 1 ? () => onRenombrar(c) : null,
        ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        PosResponsive.padding(context),
        0,
        PosResponsive.padding(context),
        6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado + chips en una sola fila horizontal (scroll si es necesario)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Título
                    Text(
                      'Clientes',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Chips en fila horizontal con scroll
                    SizedBox(
                      height: 28,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: chips,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Acciones agrupadas a la derecha (solo íconos)
              if (_gestionable) ...[
                _BotonAccion(
                  tooltip: 'Renombrar ${etiqueta(filtro!)}',
                  icon: Icons.edit_outlined,
                  onPressed: () => onRenombrar(filtro!),
                  esPequena: esPequena,
                ),
                const SizedBox(width: 4),
                _BotonAccion(
                  tooltip: 'Eliminar ${etiqueta(filtro!)}',
                  icon: Icons.delete_outline,
                  color: scheme.error,
                  onPressed: () => onEliminar(filtro!),
                  esPequena: esPequena,
                ),
                const SizedBox(width: 4),
              ],
              _BotonAccion(
                tooltip: clientes.length == 1
                    ? 'Nueva cuenta separada'
                    : 'Añadir otra cuenta',
                icon: Icons.person_add_alt,
                onPressed: onNuevo,
                esPequena: esPequena,
              ),
            ],
          ),
          // Mensaje de destino (una línea mínima, solo cuando hay varios clientes y filtro null)
          if (filtro == null && clientes.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 21),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_right_alt, size: 12, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Nuevo → ${etiqueta(activo)}',
                    style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip individual de cliente con subtotal.
class _ChipCliente extends StatelessWidget {
  const _ChipCliente({
    required this.clave,
    required this.etiqueta,
    required this.subtotal,
    required this.seleccionado,
    required this.esActivo,
    required this.scheme,
    required this.onTap,
    this.onLongPress,
  });

  final int clave;
  final String etiqueta;
  final double subtotal;
  final bool seleccionado;
  final bool esActivo;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tieneSaldo = subtotal > 0;
    return GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etiqueta,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (tieneSaldo) ...[
              const SizedBox(width: 3),
              Text(
                '\$${subtotal.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ],
            if (esActivo && seleccionado)
              const Icon(Icons.check_circle, size: 10, color: Colors.white),
          ],
        ),
        selected: seleccionado,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          color: seleccionado ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontSize: 9,
        ),
        side: BorderSide(
          color: seleccionado ? scheme.primary : scheme.outlineVariant,
        ),
      ),
    );
  }
}

/// Botón de acción compacto (solo ícono, sin texto visible).
class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
    this.esPequena = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final bool esPequena;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: esPequena ? 14 : 16, color: color),
        padding: EdgeInsets.all(esPequena ? 4 : 6),
        constraints: BoxConstraints(
          minWidth: esPequena ? 28 : 32,
          minHeight: esPequena ? 28 : 32,
        ),
      ),
    );
  }
}
