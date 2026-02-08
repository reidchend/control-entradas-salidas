# Control de Entradas y Salidas

Aplicacion de escritorio/web para gestion de inventario desarrollada con Flet y SQLAlchemy.

## 🆕 Actualizacion v1.1 - Nueva Funcionalidad

### **Historial de Facturas**
Sistema completo de consulta y seguimiento de facturas con:
- ✅ Busqueda por numero de factura
- ✅ Filtrado por proveedor
- ✅ Busqueda por rango de fechas
- ✅ Filtro por estado (Validada/Pendiente/Anulada)
- ✅ Vista detallada de productos incluidos en cada factura
- ✅ Informacion de validacion completa

## Caracteristicas

- **Registro de Entradas**: Agregar productos al inventario por categoria
- **Validacion de Facturas**: Verificar y aprobar facturas de proveedores
- **Consulta de Stock**: Visualizar niveles de inventario en tiempo real
- **Historial de Facturas**: Consultar y revisar facturas registradas con busqueda avanzada
- **Configuracion**: Gestionar categorias, productos y base de datos

## Requisitos

- Python 3.11 o superior
- pip (gestor de paquetes de Python)
- Navegador web moderno (Chrome, Firefox, Edge)

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

4. **Inicializar la base de datos**
```bash
python init_db.py
```

Esto creara:
- La base de datos SQLite (`control_entradas_salidas.db`)
- 6 categorias de ejemplo
- 20 productos de ejemplo

## Ejecucion

```bash
python main.py
```

La aplicacion se abrira automaticamente en tu navegador web en:
- `http://localhost:8502`

## Configuracion

Edita el archivo `.env` para personalizar:

```env
# Tipo de base de datos: sqlite o postgresql
DB_TYPE=sqlite

# SQLite (desarrollo)
SQLITE_PATH=./control_entradas_salidas.db

# PostgreSQL (produccion)
DB_HOST=localhost
DB_PORT=5432
DB_NAME=control_entradas_salidas
DB_USER=postgres
DB_PASSWORD=tu_contrasena

# Configuracion de Flet
FLET_WEB_PORT=8502
FLET_WEB_HOST=0.0.0.0
```

## Estructura del Proyecto

```
proyecto_control/
├── main.py                    # Punto de entrada
├── init_db.py                 # Script de inicializacion
├── requirements.txt           # Dependencias
├── .env                       # Configuracion (no incluir en git)
├── .env.example               # Plantilla de configuracion
├── app/
│   ├── __init__.py
│   ├── database/
│   │   ├── base.py            # Configuracion SQLAlchemy
│   │   └── __init__.py
│   ├── models/
│   │   ├── categoria.py       # Modelo Categoria
│   │   ├── producto.py        # Modelo Producto
│   │   ├── factura.py         # Modelo Factura
│   │   ├── movimiento.py      # Modelo Movimiento
│   │   └── __init__.py
│   ├── views/
│   │   ├── inventario_view.py        # Vista de entradas
│   │   ├── validacion_view.py        # Vista de facturas
│   │   ├── stock_view.py             # Vista de stock
│   │   ├── historial_facturas_view.py # Vista de historial ⭐ NUEVO
│   │   ├── configuracion_view.py     # Vista de configuracion
│   │   └── __init__.py
├── config/
│   ├── config.py              # Configuracion con Pydantic
│   └── __init__.py
├── uploads/
│   └── categorias/            # Imagenes de categorias
└── control_entradas_salidas.db # Base de datos SQLite
```

## Base de Datos

### Modelos

- **Categoria**: Clasificacion de productos (Verduras, Frutas, Granos, etc.)
- **Producto**: Articulos del inventario con stock y umbrales
- **Factura**: Documentos de proveedores para validar
- **Movimiento**: Historial de entradas y salidas

### Datos de Ejemplo

El script `init_db.py` crea automaticamente:
- 6 categorias
- 20 productos
- Stock inicial para cada producto

## Uso

### 1. Inventario (Entradas)
1. Selecciona una categoria
2. Elige un producto
3. Ingresa la cantidad
4. Guarda la entrada

### 2. Validacion de Facturas
1. Ve a la seccion "Validacion"
2. Busca facturas pendientes
3. Revisa los productos
4. Valida o anula la factura

### 3. Consulta de Stock
1. Ve a "Stock"
2. Filtra por categoria o busca
3. Revisa niveles y alertas

### 4. 🆕 Historial de Facturas
1. Ve a la seccion "Historial" (icono 🕒)
2. Usa los filtros de busqueda:
   - **Numero de factura**: Busca facturas especificas
   - **Proveedor**: Filtra por nombre del proveedor
   - **Rango de fechas**: Define periodo de consulta
   - **Estado**: Selecciona Validada, Pendiente o Anulada
3. Haz clic en "Ver Productos" para ver detalles completos
4. Revisa informacion de validacion y productos incluidos

#### Ejemplos de busqueda:
```
📌 Buscar factura especifica:
   Numero: FAC-2024-001
   
📌 Ver facturas de un proveedor:
   Proveedor: Distribuidora XYZ
   
📌 Facturas del ultimo mes:
   Desde: 2024-01-01
   Hasta: 2024-01-31
   
📌 Solo facturas validadas:
   Estado: Validada
```

#### Casos de uso:
- **Auditoria**: Verificar que productos llegaron con una factura especifica
- **Control de proveedores**: Revisar historial de facturas por proveedor
- **Reportes**: Generar listados de facturas por periodo
- **Seguimiento**: Verificar quien valido cada factura y cuando

### 5. Configuracion
- Gestiona categorias (agregar/editar/eliminar)
- Gestiona productos
- Configura base de datos

## Navegacion

### Desktop
```
📦 INVENTARIO      → Registro de entradas
✓  VALIDACION      → Validar facturas
📊 STOCK           → Consultar inventario
🕒 HISTORIAL       → Ver facturas historicas ⭐ NUEVO
⚙️ CONFIGURACION   → Ajustes del sistema
```

### Mobile
El mismo menu aparece en la barra inferior con iconos intuitivos.

## Produccion

Para usar PostgreSQL en produccion:

1. Instala PostgreSQL
2. Crea la base de datos
3. Actualiza `.env` con las credenciales
4. Ejecuta `python init_db.py` para crear las tablas

## 🔄 Historial de Cambios

### Version 1.1.0 (Febrero 2024)
- ✨ **Nueva funcionalidad**: Historial de Facturas
- 🔍 Busqueda avanzada multi-criterio
- 📋 Vista detallada de productos por factura
- 🎨 Interfaz mejorada con Material Design 3
- 📱 Completamente responsive

**Archivos nuevos:**
- `app/views/historial_facturas_view.py`

**Archivos modificados:**
- `main.py` - Integracion de nueva vista
- `app/views/__init__.py` - Exportacion de nueva vista

**No requiere cambios en la base de datos** ✅

### Version 1.0.0
- Sistema base de inventario
- Validacion de facturas
- Consulta de stock
- Configuracion

## Caracteristicas Tecnicas

### Stack
- **Frontend**: Flet (Python UI Framework)
- **Backend**: SQLAlchemy ORM
- **Base de datos**: SQLite (desarrollo) / PostgreSQL (produccion)
- **Configuracion**: Pydantic + python-dotenv
- **Diseno**: Material Design 3

### Arquitectura
- Patron MVC (Model-View-Controller)
- Separacion de responsabilidades
- Base de datos relacional
- Interfaz responsive

## Proximas Mejoras

- [ ] Exportacion de reportes a Excel/PDF
- [ ] Graficos y estadisticas
- [ ] Sistema de usuarios y roles
- [ ] Notificaciones automaticas
- [ ] API REST
- [ ] Aplicacion movil nativa

## Licencia

Libre uso.

---

**Desarrollado con** ❤️ **usando Flet + SQLAlchemy**