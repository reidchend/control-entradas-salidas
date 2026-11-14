import 'package:flutter/material.dart';

import '../data/pos_responsive.dart';

/// Barra de sub-cuentas ("clientes") dentro de una comanda.
///
/// Muestra cada cliente con su nombre y subtotal. Toque un chip para
/// **filtrar** la lista y ver solo esos productos; el chip "Todos" muestra
/// la comanda completa.
///
/// Optimizado para tablets pequeñas en horizontal: los chips se acomodan
/// en filas (Wrap) en lugar de una sola línea con scroll, y los botones de
/// acción se agrupan en un menú compacto para ahorrar ancho.
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
  bool get _esPequeno => clientes.isNotEmpty && clientes.length > 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esPequena = MediaQuery.sizeOf(context).width <= 720;

    if (clientes.isEmpty) return const SizedBox.shrink();

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
          // Encabezado compacto: título + chips + acciones agrupadas.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Título + chips en una línea
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Clientes',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Chip "Todos"
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                          label: const Text(
                            'Todos',
                            style: TextStyle(fontSize: 11),
                          ),
                          selected: filtro == null,
                          onSelected: (_) => onVerTodos(),
                          labelStyle: TextStyle(
                            color: filtro == null
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          side: BorderSide(
                            color: filtro == null
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Chips de clientes: se envuelven en filas si no caben
                        Expanded(
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: [
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
                                  onLongPress: c != 1
                                      ? () => onRenombrar(c)
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Línea de destino y acciones compactas
                    if (filtro == null && clientes.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_right_alt,
                                size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              'Nuevo → ${etiqueta(activo)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            if (_gestionable) ...[
                              _BotonAccion(
                                tooltip: 'Renombrar ${etiqueta(filtro!)}',
                                icon: Icons.edit_outlined,
                                onPressed: () => onRenombrar(filtro!),
                                esPequena: esPequena,
                              ),
                              _BotonAccion(
                                tooltip: 'Eliminar ${etiqueta(filtro!)}',
                                icon: Icons.delete_outline,
                                color: scheme.error,
                                onPressed: () => onEliminar(filtro!),
                                esPequena: esPequena,
                              ),
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
                      ),
                  ],
                ),
              ),
            ],
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
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (tieneSaldo) ...[
              const SizedBox(width: 3),
              Text(
                '\$${subtotal.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 9,
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
          color: seleccionado
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
          fontSize: 10,
        ),
        side: BorderSide(
          color: seleccionado
              ? scheme.primary
              : scheme.outlineVariant,
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
