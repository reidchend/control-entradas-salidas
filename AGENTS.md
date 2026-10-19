## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Pendientes de producción

**Regla obligatoria:** cada vez que se actualice el repositorio local (`git pull`/`git fetch`/cambio de rama), verificar si existe `PENDIENTES_PRODUCCION.md` en la raíz del proyecto.

- Si existe y tiene casillas `- [ ]` sin completar, **avisar al usuario** qué pendientes quedan y recordar que requieren permisos de propietario (`postgres`, no `control_app`) para ejecutarse en la base master.
- No ejecutar los DDL por cuenta propia a menos que el usuario lo pida explícitamente.
- Al confirmar que un pendiente se ejecutó, borrar su casilla del archivo; si el archivo queda sin pendientes, borrar el archivo.

## Estilo de codificación modular (separación de responsabilidades)

**Regla obligatoria:** Dividir el código por responsabilidad en archivos separados. No crear archivos "todo en uno" de cientos de líneas.

Estructura por feature (`lib/features/<feature>/`):
```
presentation/
├── <feature>_screen.dart         # Pantalla principal (solo orquestación)
├── widgets/                      # Widgets reutilizables de UI
│   ├── <widget>_card.dart        # Cards individuales
│   ├── <widget>_grid.dart        # GridViews/ListViews
│   └── <widget>_panel.dart       # Paneles compuestos
├── dialogs/                      # Diálogos modales
│   ├── <accion>_dialog.dart      # Un diálogo por archivo
│   └── <otro>_dialog.dart
��── <feature>_screen.dart         # Importa y compone widgets/dialogs
data/
├── <feature>_repository.dart     # Lógica de datos (CRUD, queries)
├── <feature>_providers.dart      # Providers Riverpod compartidos
��── <feature>_models.dart         # Data classes auxiliares (si aplica)
```

**Principios:**
1. **Un archivo = una responsabilidad** (screen orquesta, widget pinta, repo datos, dialog interacción).
2. **Máx ~200 líneas por archivo**; si crece, dividir.
3. **Imports relativos correctos**: desde `widgets/` y `dialogs/` usar `../../data/...`, desde `screen` usar `data/...` y `widgets/...`.
4. **Providers compartidos** en `data/<feature>_providers.dart` para acceso cross-widget.
5. **Nombres descriptivos**: `_widget.dart`, `_dialog.dart`, `_panel.dart`, `_card.dart`.
6. **Evitar lógica de negocio en widgets** → delegar al repository.
7. **Tests**: un test por archivo de lógica (repository), test de widget para UI crítica.

**Ejemplo aplicado en `inventario`:**
- `presentation/inventario_screen.dart` (130 líneas) → orquesta header + modo toggle + compone widgets
- `presentation/widgets/categorias_grid.dart` → GridView categorías
- `presentation/widgets/productos_panel.dart` → Panel productos + búsqueda
- `presentation/widgets/producto_card.dart` → Card individual con stock/acciones
- `presentation/widgets/lista_compra_panel.dart` → Panel lista compra agrupado
- `presentation/widgets/lista_compra_item.dart` → Item individual con acciones
- `presentation/dialogs/agregar_producto_dialog.dart` → Diálogo crear producto
- `presentation/dialogs/movimiento_dialog.dart` → Diálogo registrar movimiento
- `data/inventario_repository.dart` → Queries CRUD + movimientos + lista compra
- `data/inventario_providers.dart` → Provider `inventarioRepoProvider` compartido

## Estilo visual (UI)

**Regla obligatoria:** toda UI nueva o modificada debe verse bien en el tema de la app. Antes de dar por terminado un cambio visual, revisar que **todos** los textos e iconos se lean tanto en tema **claro** como **oscuro** (la app trae los dos: `lib/core/theme/app_colors.dart`).

**De dónde salen los colores**

- Siempre del tema: `Theme.of(context).colorScheme` (`scheme`). Para `success` / `warning` / `info` usar `appColor(context, 'success' | 'warning' | 'info')` (`lib/core/theme/app_theme.dart`).
- No inventar colores nuevos ni hex sueltos; reutilizar `AppColors` / el `ColorScheme`.
- La paleta del tema (para juzgar contraste): claro → card `#FFFFFF`, borde `#D8CDEC`, acento `#7C4DFF`; oscuro → card `#1A1530`, borde `#2F2748`, acento `#BB86FC`.

**Uso semántico (respetarlo)**

| Rol del `ColorScheme` | Para qué | **No usar para** |
| --- | --- | --- |
| `primary` (acento) | acciones: iconos de acción en cards (editar/ver/agregar), `FilledButton`, `TextButton`, enlaces, foco | texto destructivo |
| `error` | destructivo (eliminar/anular) y mensajes de error | acciones normales |
| `tertiary` (fucsia) | estados y etiquetas destacadas (nota guardada, "Reservada", "PESABLE") | fondos de pantalla completa |
| `onSurface` | texto principal | — |
| `onSurfaceVariant` | texto secundario e **iconos neutros** | — |
| `outline` (color de borde) | **solo** bordes/divisores y placeholders decorativos de empty states | **nunca** texto ni iconos accionables: es del color del borde y sobre la card queda casi invisible |
| `outlineVariant` | bordes de inputs y tarjetas | texto |

**Patrones de widgets**

- Iconos de acción: `IconButton(icon: Icon(..., color: scheme.primary), tooltip: '...')`, con el **tamaño por defecto (24)**; no achicarlos. Botón destructivo: `scheme.error`.
- Si un estado pinta distinto (con/sin nota, activo/inactivo), mantener **una sola paleta consistente** y comunicar el estado con color + ícono + texto, no solo con color.
- Formas del tema (`app_theme.dart`): cards radio **16** (`Card` del tema), inputs **12**, chips **10**, botones **12**. Preferir `Card` / chips / `FilledButton` del tema antes que `Container` con bordes propios.
- Textos secundarios: 11–13 px y `scheme.onSurfaceVariant`; títulos en negrita (`FontWeight.w600`/`w700`), como el resto de las cards.
- `Colors.*` crudos solo si el archivo vecino ya lo hace por un estado puntual (ej. `Colors.green` para "Activo"); si existe `appColor(...)`, usarlo.
