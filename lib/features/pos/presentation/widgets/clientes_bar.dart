import 'package:flutter/material.dart';

import '../../data/pos_responsive.dart';

/// Barra de sub-cuentas ("clientes") dentro de una comanda.
///
/// Fila horizontal con scroll: chip "Todos" + un chip por cliente con su
/// menú de opciones (⋮). Sin subtotales en los chips para que se lean bien en
/// tablets; el total se muestra en el panel de la comanda.
class ClientesBar extends StatelessWidget {
  const ClientesBar({
    super.key,
    required this.clientes,
    required this.activo,
    required this.filtro,
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
  final Map<int, String> nombres;

  final ValueChanged<int> onSelect;
  final VoidCallback onVerTodos;
  final VoidCallback onNuevo;
  final ValueChanged<int> onRenombrar;
  final ValueChanged<int> onEliminar;

  String etiqueta(int c) => nombres[c] ?? 'Cliente $c';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (clientes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        PosResponsive.padding(context),
        0,
        PosResponsive.padding(context),
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Clientes',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: clientes.length == 1
                    ? 'Nueva cuenta separada'
                    : 'Añadir otra cuenta',
                onPressed: onNuevo,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.person_add_alt, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _ChipTodos(
                  seleccionado: filtro == null,
                  scheme: scheme,
                  onTap: onVerTodos,
                ),
                const SizedBox(width: 8),
                for (final c in clientes) ...[
                  _ChipCliente(
                    etiqueta: etiqueta(c),
                    seleccionado: c == filtro,
                    esActivo: c == activo,
                    scheme: scheme,
                    // El cliente 1 es la cuenta base de la comanda: no se
                    // renombra ni se elimina.
                    puedeGestionar: c != 1,
                    onTap: () {
                      if (c == filtro) {
                        if (c == 1) onVerTodos();
                      } else {
                        onSelect(c);
                      }
                    },
                    onRenombrar: () => onRenombrar(c),
                    onEliminar: () => onEliminar(c),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          // Destino de los próximos productos (solo con varios clientes).
          if (filtro == null && clientes.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_right_alt,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Nuevo → ${etiqueta(activo)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip "Todos": muestra la comanda completa sin filtrar por cliente.
class _ChipTodos extends StatelessWidget {
  const _ChipTodos({
    required this.seleccionado,
    required this.scheme,
    required this.onTap,
  });

  final bool seleccionado;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final frente =
        seleccionado ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return _ChipBase(
      seleccionado: seleccionado,
      scheme: scheme,
      onTap: onTap,
      child: Text(
        'Todos',
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: frente,
        ),
      ),
    );
  }
}

/// Chip individual de cliente con menú de opciones (⋮).
class _ChipCliente extends StatelessWidget {
  const _ChipCliente({
    required this.etiqueta,
    required this.seleccionado,
    required this.esActivo,
    required this.scheme,
    required this.puedeGestionar,
    required this.onTap,
    required this.onRenombrar,
    required this.onEliminar,
  });

  final String etiqueta;
  final bool seleccionado;
  final bool esActivo;
  final ColorScheme scheme;
  final bool puedeGestionar;
  final VoidCallback onTap;
  final VoidCallback onRenombrar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final frente =
        seleccionado ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return _ChipBase(
      seleccionado: seleccionado,
      scheme: scheme,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (esActivo && seleccionado) ...[
            Icon(Icons.check_circle, size: 14, color: frente),
            const SizedBox(width: 5),
          ],
          Text(
            etiqueta,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: frente,
            ),
          ),
          if (puedeGestionar)
            PopupMenuButton<String>(
              tooltip: 'Opciones de $etiqueta',
              // `child` en vez de `icon`: así el botón mide lo que el ícono
              // (18 dp) y no los 48 dp por defecto de IconButton, que hacían
              // el chip más alto que el del cliente 1.
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.more_vert, size: 18, color: frente),
              ),
              onSelected: (v) {
                if (v == 'renombrar') onRenombrar();
                if (v == 'eliminar') onEliminar();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'renombrar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Renombrar'),
                  ),
                ),
                PopupMenuItem(
                  value: 'eliminar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Eliminar',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// Contenedor tipo chip con color, borde y área táctil del tema.
class _ChipBase extends StatelessWidget {
  const _ChipBase({
    required this.seleccionado,
    required this.scheme,
    required this.onTap,
    required this.child,
  });

  final bool seleccionado;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      shape: StadiumBorder(
        side: BorderSide(
          color: seleccionado ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: child,
        ),
      ),
    );
  }
}
