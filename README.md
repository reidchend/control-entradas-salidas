# Control de Entradas y Salidas

Aplicacion de escritorio/web para gestion de inventario desarrollada con Flet y SQLAlchemy.

## Version Actual - Sistema Offline-First

### Caracteristicas Principales

- **Modo Offline**: Trabaja sin conexion - los datos se guardan localmente
- **Sincronizacion Automatica**: Se sincroniza con Supabase cuando hay conexion
- **Productos Pesables**: Registro de productos por peso (kg) con calculo automatico
- **Cola de Operaciones**: Las operaciones offline se procesan cuando hay conexion
- **OCR de Facturas**: Extraccion automatica de datos de facturas desde imagenes del portapapeles usando Gemini API
- **Lista de Compras**: Gestion de productos pendientes por ingresar al inventario

---

## Requisitos

- Python 3.11 o superior
- pip (gestor de paquetes de Python)
- Navegador web moderno (Chrome, Firefox, Edge)

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

Crea un archivo `.env` con las credenciales de Supabase:
```env
DB_TYPE=postgresql
DB_HOST=your-supabase-host.supabase.co
DB_PORT=5432
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=your-supabase-password
```

5. **Ejecutar la aplicacion**
```bash
python main.py
```

La aplicacion sincronizara automaticamente los datos desde Supabase al iniciar.

---

## OCR de Facturas

La aplicacion extrae automaticamente datos de facturas desde imagenes del portapapeles usando **Gemini API**.

### Como usar

1. En cualquier aplicacion (WhatsApp, correo, etc.), copia la imagen de la factura
2. En la app, ve a **Validacion** y presiona `Ctrl+V` o haz clic en el area de pegado
3. La imagen se procesa automaticamente y se extraen los datos:
   - Proveedor
   - RIF / C.I.
   - Numero de factura
   - Fecha

### Configuracion de OCR

La API key de Gemini viene precargada en el codigo. Si necesitas cambiarla, edita `GEMINI_API_KEY` en `usr/ocr_extractor.py`.

### Metodo de extraccion

1. **Gemini API** (metodo principal) - requiere `google-genai>=2.0.0`
2. **Fallbacks**: Tesseract OCR, EasyOCR (instalados automaticamente si estan disponibles)

---

## Lista de Compras

Permite gestionar productos pendientes por ingresar al inventario.

- Agregar productos con busqueda filtrada
- Ver stock actual en almacen principal y restaurante
- Registrar entradas desde la lista (elimina el item al completar)
- Corregir stock (entrada/salida segun cantidad fisica real)
- Eliminar productos de la lista

---

## Ejecucion

```bash
python main.py
```

La aplicacion se abrira automaticamente en tu navegador web en:
- `http://localhost:8502`

---

## Configuracion

Edita el archivo `.env` para personalizar:

```env
# Tipo de base de datos: sqlite o postgresql
DB_TYPE=postgresql

# Supabase (produccion)
DB_HOST=your-project.supabase.co
DB_PORT=5432
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=tu_contrasena

# Configuracion de Flet
FLET_WEB_PORT=8502
FLET_WEB_HOST=0.0.0.0
```

---

## Productos Pesables

### Registro de Productos por Peso

Para productos que se venden por peso (jamon, queso, carnes):

1. El producto debe tener `es_pesable = true` en la base de datos
2. Al registrar una entrada, apareceran 3 campos:
   - **Cantidad (unidades)**: Numero de piezas (ej: 3 jamones)
   - **Peso por unidad (kg)**: Peso de cada pieza (ej: 0.100 kg)
   - **Peso total**: Calculo automatico (ej: 0.300 kg)

### Categoria de Unidades

| Tipo | Campo usado | Ejemplo |
|------|------------|---------|
| Normal | cantidad | 10 unidades |
| Pesable | peso_total | 0.300 kg |

---

## Sincronizacion

### Funcionamiento

1. **Modo Offline**: Los datos se guardan en SQLite local
2. **Sync Automatico**: Al iniciar la app, se sincroniza con Supabase
3. **Cola de Operaciones**: Si hay conexion, las operaciones se sincronizan inmediatamente
4. **Background Sync**: Cada 20 segundos se procesa la cola de sync

### Flujo de Datos

```
Local (SQLite) <---> Sync Manager <---> Supabase
                      |
                 Cola de operaciones
                 (offline mode)
```

---

## Estructura del Proyecto

```
proyecto_control/
├── main.py                    # Punto de entrada
├── requirements.txt           # Dependencias
├── .env                       # Configuracion (no incluir en git)
├── config/
│   ├── config.py              # Configuracion con Pydantic
│   └── __init__.py
├── usr/
│   ├── database/
│   │   ├── conn.py           # Conexion SQLite local
│   │   ├── base.py           # Configuracion SQLAlchemy
│   │   ├── local_replica.py  # Replica local SQLite
│   │   ├── sync.py           # Sincronizacion con Supabase
│   │   ├── sync_queue.py     # Cola de operaciones offline
│   │   └── __init__.py
│   ├── models/
│   │   ├── categoria.py       # Modelo Categoria
│   │   ├── producto.py       # Modelo Producto (es_pesable)
│   │   ├── factura.py         # Modelo Factura
│   │   ├── movimiento.py      # Modelo Movimiento (peso_total)
│   │   ├── existencia.py     # Modelo Existencia
│   │   ├── compra_lista.py   # Modelo Lista de Compras
│   │   └── __init__.py
│   ├── ocr_extractor.py      # OCR con Gemini API
│   ├── views/
│   │   ├── inventario_view.py        # Vista de inventario
│   │   ├── validacion_view.py        # Vista de facturas
│   │   ├── stock_view.py             # Vista de stock
│   │   ├── historial_facturas_view.py # Vista de historial
│   │   ├── requisiciones_view.py     # Vista de requisiciones
│   │   └── __init__.py
│   └── views/inventario/      # Modulos de inventario
│       ├── helpers.py
│       ├── categories.py
│       ├── products.py
│       ├── dialogs.py
│       ├── movements.py
│       └── shopping_list.py
└── lycoris_local.db          # Base de datos local SQLite
```

---

## Uso

### 1. Inventario

1. Selecciona una categoria
2. Elige un producto
3. **Para productos normales**: Ingresa la cantidad
4. **Para productos pesables**: Ingresa cantidad de unidades y peso por unidad
5. Guarda la entrada

### 2. Validacion de Facturas (OCR)

1. Ve a la seccion **Validacion**
2. Copia una imagen de factura en el portapapeles
3. Presiona `Ctrl+V` o pega la imagen
4. Los datos se extraen automaticamente
5. Valida y confirma la factura

### 3. Lista de Compras

1. Ve a **Inventario** y presiona el icono de carrito
2. Presiona **Agregar** y busca productos
3. Desde cada tarjeta puedes:
   - Registrar **Entrada** (elimina de la lista)
   - **Corregir stock** (ajusta stock sin salir de la lista)
   - **Eliminar** de la lista

### 4. Consulta de Stock

1. Ve a **Stock**
2. Filtra por categoria o busca
3. Revisa niveles y alertas

---

## Navegacion

### Desktop
```
📦 INVENTARIO      → Registro de entradas + Lista de Compras
✓  VALIDACION      → Validar facturas (con OCR automatico)
📊 STOCK           → Consultar inventario
🕒 HISTORIAL       → Ver facturas historicas
⚙️ CONFIGURACION   → Ajustes del sistema
```

### Mobile
El mismo menu aparece en la barra inferior con iconos intuitivos.

---

## Produccion

Para usar PostgreSQL en produccion:

1. Crea una cuenta en Supabase
2. Obtiene las credenciales de conexion
3. Actualiza `.env` con las credenciales
4. Ejecuta `python main.py` - la app creara las tablas automaticamente

---

## Historial de Cambios

### Version 2.1.0 (Mayo 2026)
- ✨ **OCR con Gemini API**: Extraccion automatica de datos de facturas desde imagenes del portapapeles
- ✨ **Lista de Compras**: Gestion de productos pendientes por ingresar
- 🔧 Correcciones de UI en lista de compras (empty state, actualizacion de stock)
- 🔧 Silenciado de mensajes de debug de asyncio en consola
- 🔧 Modularizacion de inventario_view.py (separacion en helpers, categories, products, dialogs, movements, shopping_list)

### Version 2.0.0 (Abril 2026)
- ✨ **Sistema Offline-First**: SQLite como fuente de verdad local
- 🔄 **Sincronizacion Automatica**: Sync bidireccional con Supabase
- ⚖️ **Productos Pesables**: Registro de productos por peso
- 📡 **Cola de Operaciones**: Manejo offline con sync automatico

### Version 1.1.0 (Febrero 2024)
- ✨ **Nueva funcionalidad**: Historial de Facturas
- 🔍 Busqueda avanzada multi-criterio
- 📋 Vista detallada de productos por factura

### Version 1.0.0
- Sistema base de inventario
- Validacion de facturas
- Consulta de stock
- Configuracion

---

## Caracteristicas Tecnicas

### Stack
- **Frontend**: Flet (Python UI Framework)
- **Backend**: SQLAlchemy ORM
- **Base de datos local**: SQLite
- **Base de datos central**: Supabase (PostgreSQL)
- **OCR**: Google Gemini API (google-genai)
- **Configuracion**: Pydantic + python-dotenv

### Arquitectura
- Patron MVC (Model-View-Controller)
- Sistema offline-first
- Replica local con sync bidireccional
- Cola de operaciones para modo offline

---

## Licencia

Libre uso.

---

**Desarrollado con** ❤️ **usando Flet + SQLAlchemy + Supabase**
