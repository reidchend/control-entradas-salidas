# 📦 Control de Entradas y Salidas - Guía Técnica

Sistema de gestión de inventario **Offline-First** desarrollado con Flet y SQLAlchemy, diseñado para operar en entornos con conexión intermitente y actualizarse dinámicamente sin recompilar el ejecutable.

---

## 🚀 Arquitectura del Sistema

### 1. Smart Launcher & Dynamic Updates
El sistema no carga el código directamente desde el ejecutable, sino que utiliza un mecanismo de **Inyección de Rutas**:
- **Lanzador**: El `.exe` actúa como un contenedor de entorno (Python + Librerías).
- **Carga Dinámica**: Al iniciar, `main.py` verifica la versión en un `version.json` remoto.
- **app_updates/**: Si hay una actualización, descarga un `update.zip`, lo extrae en `app_updates/` e inserta esta carpeta al inicio de `sys.path`.
- **Prioridad**: El código en `app_updates/usr/` tiene prioridad sobre el código empaquetado en el `.exe`.

### 2. Motor de Sincronización (Offline-First)
El sistema utiliza una arquitectura de **Réplica Local**:
- **LocalReplica**: Una base de datos SQLite local que imita el esquema de Supabase.
- **SyncQueue**: Cuando el usuario realiza un cambio offline, la operación se guarda en `pending_operations`.
- **Bidireccionalidad**: 
  - **Subida**: Procesa la cola de pendientes → Supabase.
  - **Descarga**: Descarga cambios remotos → SQLite → Poda de registros huérfanos.

### 3. Flujo de Requisiciones (Audit Workflow)
El módulo de requisiciones implementa un proceso de control de calidad:
- **Pendiente**: Registro inicial de solicitud.
- **Auditoría**: Vista de verificación donde se compara el stock físico vs sistema. Permite realizar **Ajustes de Stock** inmediatos.
- **Totalización**: Traslada físicamente el stock (Origen → Destino) y marca la requisición como `completada`, registrando la validación en el `kardex_validaciones`.

---

## 📂 Mapa del Proyecto

```text
control-entradas-salidas/
├── main.py                              # Entry point: Maneja la redirección a app_updates/
├── usr/
│   ├── database/
│   │   ├── conn.py                      # Conexiones SQLite/Supabase + gestión de ruta BD
│   │   ├── local_replica.py             # Definición de tablas SQLite y migraciones locales
│   │   ├── sync.py                      # Lógica core de sincronización, poda de huérfanos, timeout 15s
│   │   └── sync_queue.py                # Gestión de operaciones pendientes
│   ├── models/                          # Definiciones de SQLAlchemy (Esquema de datos)
│   │   ├── producto.py                  # Atributos: es_pesable, tipo, etc.
│   │   └── requisicion.py               # Modelos de Requisición y Detalle (incluye verificado)
│   ├── views/                           # UI desarrollada con Flet
│   │   ├── requisiciones/
│   │   │   ├── data.py                  # Lógica de negocio de requisiciones (CRUD + Audit)
│   │   │   ├── audit_view.py            # Vista de verificación y totalización
│   │   │   ├── visualize_view.py        # Vista de solo lectura + compartir (copiar/guardar .txt)
│   │   │   ├── components.py            # Tarjetas de requisición (iconos compactos)
│   │   │   ├── dialogs.py               # Diálogos de creación/edición
│   │   │   └── helpers.py               # Utilidades de color/tema
│   │   ├── stock/
│   │   │   ├── data.py                  # Operaciones de stock/movimientos
│   │   │   ├── helpers.py               # Utilidades de stock
│   │   │   ├── components.py            # Componentes reutilizables de stock
│   │   │   └── dialogs.py               # Diálogos de ajuste/entrada/salida
│   │   ├── validacion/
│   │   │   ├── service.py               # Servicio de validación/kardex
│   │   │   ├── payments.py              # Gestión de pagos
│   │   │   ├── fields.py                # Campos personalizados
│   │   │   ├── dialog.py                # Diálogos de validación
│   │   │   ├── ocr_handler.py           # Procesamiento OCR
│   │   │   └── __init__.py
│   │   ├── inventario/
│   │   │   ├── data.py                  # Operaciones de inventario
│   │   │   ├── helpers.py               # Utilidades de inventario
│   │   │   ├── components.py            # Componentes reutilizables
│   │   │   ├── dialogs.py               # Diálogos de inventario
│   │   │   ├── shopping_list.py         # Lista de compras
│   │   │   └── movements.py             # Movimientos de stock
│   │   ├── login_view.py                # Login / Registro / PIN
│   │   ├── configuracion_view.py        # Configuración + test conexión + sync manual
│   │   ├── historial_facturas_view.py   # Historial de facturas
│   │   ├── producciones_view.py         # Módulo de producciones
│   │   ├── requisiciones_view.py        # Vista principal (lista + navegación)
│   │   ├── stock_view.py                # Vista de stock/almacenes
│   │   ├── validacion_view.py           # Vista de validaciones/kardex
│   │   └── whatsapp_bandeja_view.py     # Bandeja WhatsApp
│   └── widgets/
│       └── sync_status_bar.py           # Barra visual de progreso del sync
└── config/
    └── config.py                        # Configuración centralizada con Pydantic
```

---

## 🛠️ Guía de Depuración y Mantenimiento

### Problemas Comunes y Soluciones

#### 1. El código actualizado no se refleja en el App
- **Causa**: Windows mantiene caché de bytecode (`.pyc`) en carpetas `__pycache__` que puede tener prioridad sobre los archivos `.py` actualizados.
- **Solución**: Borrar manualmente todas las carpetas `__pycache__` en el directorio de instalación.

#### 2. Fallo en Notificaciones tras Actualización
- **Causa**: Al limpiar `sys.modules` para cargar la nueva versión, se pierde la referencia a la página de Flet (`_page`) en el módulo de notificaciones.
- **Solución**: Se implementó un **Stack Walker** en `usr/notifications.py` que busca la instancia de `ft.Page` recorriendo la pila de llamadas si la referencia directa es `None`.

#### 3. Bases de Datos Duplicadas
- **Causa**: Uso de rutas relativas que crean una DB en la raíz y otra en `app_updates/`.
- **Solución**: Siempre utilizar rutas absolutas obtenidas mediante `os.path.abspath` en `usr/database/conn.py`.

#### 4. Stock con decimales infinitos (ej. -4.4399999999999995)
- **Causa**: Error de precisión de punto flotante IEEE 754 al sumar/restar movimientos sucesivamente.
- **Solución**: `recalculate_existencias()` en `local_replica.py` redondea el resultado final a 4 decimales antes de guardar.

---

## 📈 Flujo de Trabajo para Desarrolladores

### Para agregar una nueva funcionalidad:
1. **Modelo**: Definir la tabla en `usr/models/` y agregar el `CREATE TABLE` en `usr/database/local_replica.py`.
2. **Data Layer**: Crear funciones de acceso a datos en `usr/views/[modulo]/data.py`.
3. **UI**: Implementar la vista en `usr/views/` usando componentes reutilizables.
4. **Sync**: Si la tabla debe sincronizarse, agregarla a `tables_to_sync` en `usr/database/sync.py`.

### Para publicar un parche (Hotfix):
1. Subir los cambios a la rama `main` de GitHub.
2. El GitHub Action (configurar en `.github/workflows/`) generará el `update.zip` automáticamente.
3. Actualizar el número de versión en `version.json`.
4. El cliente descargará el parche al reiniciar.

---

## 📦 Compilación del Ejecutable

Si se agregan nuevas dependencias en `requirements.txt`, se debe recompilar:

---

## Guía de Buenas Prácticas y Errores a Evitar

### ❌ Errores Comunes (Ya Corregidos)

#### 1. Variables `snack` sin definir
**Síntoma**: `NameError: name 'snack' is not defined` al mostrar advertencias en requisiciones.
**Causa**: Llamar a `self.page.overlay.append(snack)` y `snack.open = True` después de `show_warning()`/`show_success()`, sin haber creado la variable `snack`.
**Regla**: Las funciones `show_warning()`, `show_success()` y `show_error()` de `usr.notifications` ya muestran su propio `SnackBar`. **No agregues líneas adicionales** de overlay después de llamarlas.

#### 2. Código de depuración en producción
**Síntoma**: Textos como `"PRUEBA DE LISTA"` o `"PRUEBA DE DATOS"` visibles en la UI.
**Regla**: Nunca dejes textos de debug, variables de prueba o asserts en el código de producción. Usa `logger.debug()` para trazas temporales.

#### 3. Métodos duplicados en una misma clase
**Síntoma**: El segundo `_on_file_save` sobrescribe al primero, causando comportamiento inesperado.
**Regla**: En Python, el último método definido con el mismo nombre es el que prevalece. Usa `grep` o `rg` para verificar que no haya duplicados al refactorizar.

#### 4. Bloques de código duplicados
**Síntoma**: El método `_buscar_productos_buscador()` ejecutaba la misma query y renderizado **dos veces**, sobrescribiendo los resultados.
**Regla**: Aplica el principio DRY (Don't Repeat Yourself). Si ves más de ~10 líneas repetidas, extráelas a un método auxiliar o elimina el duplicado.

#### 5. Archivos muertos que importan símbolos inexistentes
**Síntoma**: `usr/database/session.py` importaba `engine` de `base.py`, pero `engine` no existe como variable global en ese módulo.
**Regla**: Antes de eliminar o renombrar un símbolo exportado, verifica con `grep -r "from .*import.*engine"` que ningún otro archivo lo importe. Los archivos que no se importan desde ningún lado deben eliminarse.

#### 6. Hilos modificando la UI de Flet
**Síntoma**: Llamar a `self.page.update()` desde hilos secundarios (`threading.Thread`).
**Regla**: Flet **no es thread-safe**. Para actualizar la UI desde un hilo, usa `self.page.run_task()` con una corutina async o `self.page.add()` desde el hilo principal únicamente.

---

### ✅ Buenas Prácticas Recomendadas

#### Base de Datos
- **No mezcles** `sqlite3` directo con SQLAlchemy ORM. Usa **uno solo** para evitar inconsistencias de datos.
- Cada escritura de movimiento debe actualizar el stock (ej: `recalculate_existencias()`).
- Limpia `page.overlay` selectivamente, no con `.clear()` que borra overlays de otras vistas.

#### Manejo de Errores
- Usa siempre `show_error()`/`show_warning()`/`show_success()` del sistema centralizado (`usr.notifications`).
- No dupliques la lógica de inicio de sesión (`LoginView._go_to_main` es casi igual a `main.py`).
- Captura excepciones específicas, no `Exception` genérica.

#### Sincronización
- **Solo existe una cola activa**: `sync_queue`. La tabla `pending_operations` fue eliminada porque nunca se procesaba.
- Al eliminar un movimiento via SQLAlchemy, también elimínalo del SQLite local raw si usas ambos sistemas.
- `LocalReplica.save_movimiento()` ya no tiene lógica de sync propia. Delega al llamante (`registrar_movimiento` o `save_movimiento_with_sync`).

#### Estructura
- Evita alias redundantes (ej: 4 alias para `get_session()`).
- Unifica los sistemas de notificaciones a un solo módulo.
- Documenta en el `__init__.py` del package qué se exporta realmente.
- No dupliques la lógica de sync en múltiples capas (causa inconsistencias).

---

## Historial de Cambios

### Version 2.1.1 (Mayo 2026)
- 🐛 **Corregido**: `NameError: snack is not defined` en 6 ubicaciones de `requisiciones_view.py`
- 🗑️ **Eliminado**: `usr/database/session.py` (archivo muerto que causaba `ImportError`)
- 🧹 **Eliminado**: Código debug "PRUEBA DE LISTA" y "PRUEBA DE DATOS" en requisiciones
- 🔁 **Eliminado**: Bloque duplicado (~50 líneas) en `_buscar_productos_buscador()`
- 🔁 **Eliminado**: Método duplicado `_on_file_save` en `historial_facturas_view.py`
- 🔄 **Corregido**: `registrar_movimiento()` ahora llama a `recalculate_existencias()` después de cada escritura
- 🔄 **Corregido**: Sync Manager reutilizado en `registrar_movimiento()` (ya no crea engine PostgreSQL en cada movimiento)
- 🔄 **Eliminado**: Sync duplicado en `LocalReplica.save_movimiento()` (delegado al llamante)
- 🗑️ **Eliminada**: Tabla `pending_operations` + sus 4 métodos (código muerto - nunca se procesaba)
- 📝 **Añadido**: Guía de buenas prácticas y errores a evitar

### Version 2.1.0 (Mayo 2026)
- ✨ **OCR con Gemini API**: Extraccion automatica de datos de facturas desde imagenes del portapapeles
- ✨ **Lista de Compras**: Gestion de productos pendientes por ingresar
- 🔧 Correcciones de UI en lista de compras (empty state, actualizacion de stock)
- 🔧 Silenciado de mensajes de debug de asyncio en consola
- 🔧 Modularizacion de inventario_view.py (separacion en helpers, categories, products, dialogs, movements, shopping_list)
