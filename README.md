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

```bash
pyinstaller --noconfirm --onefile --windowed --name "Lycoris_Control" \
--icon "assets/icono.ico" \
--add-data "assets;assets" \
--add-data ".env;." \
--collect-all "supabase" \
--collect-all "pydantic_settings" \
--collect-submodules "sqlalchemy" \
--hidden-import "sqlalchemy.dialects.postgresql" \
--hidden-import "pg8000" \
main.py
```

---

## 🔧 Estado Actual / Pendientes

- [x] Sincronización bidireccional con timeout 15s y rollback en ALTER TABLE
- [x] Barra de progreso visual del sync (`SyncStatusBar`)
- [x] Engine SQLite se regenera solo si cambia la ruta de la BD
- [x] Redondeo de stock a 4 decimales (elimina ruido flotante)
- [x] Compartir requisición: copiar al portapapeles + guardar .txt nativo
- [ ] Workflow GitHub Actions para build automático de `update.zip`
- [ ] Tests unitarios para motor de sincronización

---

**Soporte**: Reportar errores en [Issues de GitHub](https://github.com/reidchend/control-entradas-salidas/issues)