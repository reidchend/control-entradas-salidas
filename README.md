# Control de Entradas y Salidas

Aplicacion de escritorio/web para gestion de inventario desarrollada con Flet y SQLAlchemy.

## 🆕 Version Actual - Sistema Offline-First

### Caracteristicas Principales

- **Modo Offline**: Trabaja sin conexion - los datos se guardan localmente
- **Sincronizacion Automatica**: Se sincroniza con Supabase cuando hay conexion
- **Productos Pesables**: Registro de productos por peso (kg) con calculo automatico
- **Cola de Operaciones**: Las operaciones offline se procesan cuando hay conexion

---

## Caracteristicas

- **Registro de Entradas**: Agregar productos al inventario por categoria
- **Validacion de Facturas**: Verificar y aprobar facturas de proveedores
- **Consulta de Stock**: Visualizar niveles de inventario en tiempo real
- **Historial de Facturas**: Consultar y revisar facturas registradas con busqueda avanzada
- **Productos Pesables**: Registro de productos que se venden por peso (jamon, queso, carnes)
- **Configuracion**: Gestionar categorias, productos y base de datos

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
python -m venv venv
source venv/bin/activate  # En Linux/Mac
venv\Scripts\activate     # En Windows
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

5. **Inicializar la base de datos local**
```bash
python main.py
```

La aplicacion sincronizara automaticamente los datos desde Supabase al iniciar.

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
├── init_db.py                 # Script de inicializacion
├── requirements.txt           # Dependencias
├── .env                       # Configuracion (no incluir en git)
├── config/
│   ├── config.py              # Configuracion con Pydantic
│   └── __init__.py
├── usr/
│   ├── database/
│   │   ├── base.py            # Configuracion SQLAlchemy
│   │   ├── local_replica.py   # Replica local SQLite
│   │   ├── sync.py            # Sincronizacion con Supabase
│   │   ├── sync_queue.py      # Cola de operaciones offline
│   │   └── __init__.py
│   ├── models/
│   │   ├── categoria.py       # Modelo Categoria
│   │   ├── producto.py        # Modelo Producto (es_pesable)
│   │   ├── factura.py        # Modelo Factura
│   │   ├── movimiento.py      # Modelo Movimiento (peso_total)
│   │   ├── existencia.py     # Modelo Existencia
│   │   └── __init__.py
│   └── views/
│       ├── inventario_view.py        # Vista de entradas
│       ├── validacion_view.py        # Vista de facturas
│       ├── stock_view.py             # Vista de stock
│       ├── historial_facturas_view.py # Vista de historial
│       ├── configuracion_view.py     # Vista de configuracion
│       └── __init__.py
└── lycoris_local.db          # Base de datos local SQLite
```

---

## Base de Datos

### Modelos

- **Categoria**: Clasificacion de productos (Verduras, Frutas, Granos, etc.)
- **Producto**: Articulos del inventario con stock y umbrales
  - `es_pesable`: Boolean - producto se vende por peso
  - `peso_unitario`: Float - peso de cada unidad
  - `unidad_medida`: String - "unidad" o "kg"
- **Factura**: Documentos de proveedores para validar
- **Movimiento**: Historial de entradas y salidas
  - `cantidad`: Cantidad en unidades
  - `peso_total`: Peso total (para productos pesables)
- **Existencia**: Stock actual por producto y almacen
  - `cantidad`: Cantidad actual
  - `unidad`: "unidad" o "kg"

---

## Uso

### 1. Inventario (Entradas)

1. Selecciona una categoria
2. Elige un producto
3. **Para productos normales**: Ingresa la cantidad
4. **Para productos pesables**: Ingresa cantidad de unidades y peso por unidad
5. Guarda la entrada

### 2. Validacion de Facturas

1. Ve a la seccion "Validacion"
2. Busca facturas pendientes
3. Selecciona las entradas a validar
4. Ingresa el numero de factura
5. Confirma la validacion (se sincroniza a Supabase)

### 3. Consulta de Stock

1. Ve a "Stock"
2. Filtra por categoria o busca
3. Revisa niveles y alertas

### 4. Historial de Facturas

1. Ve a la seccion "Historial"
2. Usa los filtros de busqueda

---

## Navegacion

### Desktop
```
📦 INVENTARIO      → Registro de entradas (incluye productos pesables)
✓  VALIDACION      → Validar facturas (sync a Supabase)
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
