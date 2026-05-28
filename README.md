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
