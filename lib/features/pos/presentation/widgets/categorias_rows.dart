import 'package:flutter/material.dart';

/// Etiqueta de sección para las listas de configuración del POS.
class CatSectionLabel extends StatelessWidget {
  const CatSectionLabel(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFFBB86FC),
        ),
      ),
    );
  }
}

/// Fila de una categoría POS: color, nombre, editar y eliminar.
class PosCatRow extends StatelessWidget {
  const PosCatRow({
    super.key,
    required this.color,
    required this.nombre,
    required this.onEdit,
    required this.onDelete,
  });

  final Color color;
  final String nombre;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(nombre)),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 18, color: Color(0xFFBB86FC)),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF5350)),
          ),
        ],
      ),
    );
  }
}

/// Fila de una categoría de platos / sub-categoría: color, etiqueta, switch
/// de activo, editar y eliminar.
class SubcatRow extends StatelessWidget {
  const SubcatRow({
    super.key,
    required this.color,
    required this.label,
    required this.activo,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Color color;
  final String label;
  final bool activo;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
          ),
          Switch(
            value: activo,
            onChanged: onToggle,
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 18, color: Color(0xFFBB86FC)),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF5350)),
          ),
        ],
      ),
    );
  }
}

/// Convierte un color hex a [Color].
Color hexColor(String value) {
  final v = value.replaceFirst('#', '');
  return Color(int.parse('FF$v', radix: 16));
}
