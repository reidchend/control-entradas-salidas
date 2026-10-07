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
