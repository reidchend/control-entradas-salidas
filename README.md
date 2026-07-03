# Control de Entradas y Salidas

Aplicacion de escritorio para gestion de inventario desarrollada con Flet y SQLAlchemy.

## Version Actual - Sistema Offline-First con Auto-Updates

### Caracteristicas Principales

- **Modo Offline**: Trabaja sin conexion - los datos se guardan localmente en SQLite
- **Sincronizacion Automatica**: Se sincroniza con Supabase (PostgreSQL) cuando hay conexion
- **Auto-Update**: El cargador inteligente descarga actualizaciones de `usr/` y `config/` desde GitHub sin necesidad de recompilar el `.exe`
- **WhatsApp Bot**: Envio de notificaciones via WhatsApp usando Baileys
- **Productos Pesables**: Registro de productos por peso (kg) con calculo automatico
- **Cola de Operaciones**: Las operaciones offline se procesan cuando hay conexion
- **OCR de Facturas**: Extraccion automatica de datos de facturas desde imagenes del portapapeles usando Gemini API
- **Lista de Compras**: Gestion de productos pendientes por ingresar al inventario
- **Requisiciones**: Solicitudes internas de productos
- **Gestion de Proveedores**: Administracion del catalogo de proveedores

---

## Requisitos

- Python 3.11 o superior
- pip (gestor de paquetes de Python)

---

## Instalacion

1. **Clonar o descargar el proyecto**

2. **Crear entorno virtual (recomendado)**
```bash
python -m venv .venv
source .venv/bin/activate  # En Linux/Mac
.venv\Scripts\activate     # En Windows
```

3. **Instalar dependencias**
```bash
pip install -r requirements.txt
```

4. **Configurar variables de entorno**

Crea un archivo `.env` en la raiz del proyecto:
```env
DB_TYPE=postgresql
DB_HOST=your-supabase-host.pooler.supabase.com
DB_PORT=6543
DB_NAME=postgres
DB_USER=postgres.your_project
DB_PASSWORD=your-supabase-password

FLET_APP_NAME=Lycoris_Control
FLET_APP_VERSION=1.0.0

UPDATE_URL=https://raw.githubusercontent.com/tu_usuario/tu_repo/main/version.json
```

5. **Ejecutar la aplicacion**
```bash
python main.py
```

---

## Auto-Update (Actualizaciones Automaticas)

El sistema cuenta con un cargador inteligente que permite actualizar la logica de la app sin recompilar el `.exe`.

### Como funciona
1. El ejecutable actua como **Launcher**: contiene Python, Flet y las librerias.
2. Al iniciar, consulta un `version.json` remoto (ej: en GitHub).
3. Si la version remota es diferente a la local, descarga `update.zip`.
4. Extrae las carpetas `usr/` y `config/` en `app_updates/`.
5. Inyecta `app_updates/` en `sys.path` y carga el codigo nuevo.

### Para publicar una actualizacion
1. Modifica el codigo en `usr/` o `config/`.
2. Sube los cambios a GitHub (rama `main`).
3. El **GitHub Action** genera automaticamente el `update.zip`.
4. Edita `version.json` en GitHub con el nuevo numero de version.
5. Los usuarios recibiran la actualizacion al reiniciar la app.

**Nota**: Solo es necesario recompilar el `.exe` si se agregan nuevas librerias externas.

---

## OCR de Facturas

La aplicacion extrae automaticamente datos de facturas desde imagenes del portapapeles usando **Gemini API**.

### Como usar
1. En cualquier aplicacion (WhatsApp, correo, etc.), copia la imagen de la factura
2. En la app, ve a **Validacion** y presiona `Ctrl+V`
3. La imagen se procesa automaticamente y se extraen los datos

---

## Navegacion

### Desktop
```
📦 INVENTARIO      → Registro de entradas + Lista de Compras
✓  VALIDACION      → Validar facturas (con OCR automatico)
📊 STOCK           → Consultar inventario
📋 REQUISICIONES   → Solicitudes internas de productos
🕒 HISTORIAL       → Ver facturas historicas
⚙️ CONFIGURACION   → Gestion de catalogo y sistema
✉️ BANDEJA        → Notificaciones WhatsApp
```

### Mobile
El mismo menu aparece en la barra inferior con iconos intuitivos y un boton "Mas" para las opciones adicionales.

---

## Estructura del Proyecto

```
control-entradas-salidas/
├── main.py                    # Punto de entrada (Smart Launcher)
├── requirements.txt           # Dependencias
├── .env                       # Configuracion (no incluir en git)
├── .gitignore                 # Archivos ignorados
├── version.json               # Version actual para auto-update
├── update.zip                 # Paquete de actualizacion (generado por CI)
├── assets/
│   └── icono.ico              # Icono de la aplicacion
├── config/
│   ├── config.py              # Configuracion con Pydantic
│   └── __init__.py
├── migrations/
│   └── 001_add_tipo_to_productos.sql  # Migraciones SQL
├── usr/
│   ├── database/
│   │   ├── conn.py            # Conexion SQLite local
│   │   ├── base.py            # Configuracion SQLAlchemy
│   │   ├── local_replica.py   # Replica local SQLite
│   │   ├── sync.py            # Sincronizacion con Supabase
│   │   ├── sync_queue.py      # Cola de operaciones offline
│   │   ├── sync_callbacks.py  # Callbacks de sincronizacion
│   │   └── cache.py           # Cache de consultas
│   ├── models/
│   │   ├── categoria.py       # Modelo Categoria
│   │   ├── producto.py        # Modelo Producto (es_pesable, tipo)
│   │   ├── factura.py         # Modelo Factura
│   │   ├── factura_pago.py    # Modelo Pagos de Factura
│   │   ├── movimiento.py      # Modelo Movimiento
│   │   ├── existencia.py      # Modelo Existencia
│   │   ├── compra_lista.py    # Modelo Lista de Compras
│   │   ├── proveedor.py       # Modelo Proveedor
│   │   ├── requisicion.py     # Modelo Requisicion
│   │   └── __init__.py
│   ├── views/
│   │   ├── inventario_view.py       # Vista de inventario
│   │   ├── validacion_view.py       # Vista de facturas
│   │   ├── stock_view.py            # Vista de stock
│   │   ├── historial_facturas_view.py
│   │   ├── requisiciones_view.py    # Vista de requisiciones
│   │   ├── configuracion_view.py    # Vista de configuracion
│   │   ├── whatsapp_bandeja_view.py # Bandeja de WhatsApp
│   │   ├── login_view.py            # Login/PIN
│   │   └── __init__.py
│   └── views/inventario/
│       ├── helpers.py
│       ├── categories.py
│       ├── products.py
│       ├── dialogs.py
│       ├── movements.py
│       └── shopping_list.py
├── whatsapp_bot/
│   └── server.js              # Servidor del bot de WhatsApp
├── .github/
│   └── workflows/
│       └── update.yml         # CI para auto-update
└── lycoris_local.db           # Base de datos local SQLite
```

---

## Stack Tecnologico

- **Frontend**: Flet (Python UI Framework)
- **Backend**: SQLAlchemy ORM
- **Base de datos local**: SQLite
- **Base de datos central**: Supabase (PostgreSQL via pg8000)
- **OCR**: Google Gemini API (google-genai)
- **WhatsApp**: Baileys (Node.js)
- **Auto-Update**: GitHub Actions + raw.githubusercontent.com
- **Configuracion**: Pydantic + python-dotenv

### Arquitectura
- Smart Launcher con carga dinamica de modulos
- Sistema offline-first con replica local
- Sync bidireccional con cola de operaciones
- Actualizaciones OTA via GitHub

---

## Produccion

Para compilar el ejecutable para Windows:

```bash
pyinstaller --noconfirm --onefile --windowed --name "Lycoris_Control" --icon "assets/icono.ico" --add-data "assets;assets" --add-data ".env;." --collect-all "supabase" --collect-all "pydantic_settings" --collect-submodules "sqlalchemy" --hidden-import "sqlalchemy.dialects.postgresql" --hidden-import "pg8000" main.py
```

---

## Licencia

Libre uso.

---

**Desarrollado con** ❤️ **usando Flet + SQLAlchemy + Supabase**
