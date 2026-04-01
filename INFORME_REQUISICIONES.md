# 📋 INFORME: Sistema de Requisiciones para Traslados

**Fecha:** 01 de Abril 2026  
**Proyecto:** Control de Entradas/Salidas ↔ Sistema Restaurante  
**Objetivo:** Permitir gestión de traslados de productos entre almacenes

---

## 1. RESUMEN DEL SISTEMA

Se ha implementado un sistema de **requisiciones** en el proyecto Control de Entradas/Salidas que permite:

1. ✅ Crear órdenes de requisición con productos y cantidades
2. ✅ Definir almacén de origen y destino
3. ✅ Exportar la requisición en formato JSON
4. ✅ Importar la requisición en el Sistema Restaurante para ejecutar el traslado

---

## 2. ESTRUCTURA DE DATOS

### Tabla: requisiciones

| Campo | Tipo | Descripción |
|-------|------|-------------|
| id | INTEGER | Identificador único |
| numero | VARCHAR(50) | Número de requisición (ej: REQ-001) |
| origen | VARCHAR(50) | Almacén de origen |
| destino | VARCHAR(50) | Almacén de destino |
| estado | VARCHAR(20) | pendiente, completada, cancelada |
| observaciones | TEXT | Notas adicionales |
| creada_por | VARCHAR(100) | Usuario que creó |
| fecha_creacion | TIMESTAMPTZ | Fecha/hora de creación |

### Tabla: requisicion_detalles

| Campo | Tipo | Descripción |
|-------|------|-------------|
| id | INTEGER | Identificador único |
| requisicion_id | INTEGER | FK a requisiciones |
| producto_id | INTEGER | FK a productos (nullable) |
| ingrediente | VARCHAR(200) | Nombre del producto |
| cantidad | FLOAT | Cantidad a trasladar |
| unidad | VARCHAR(50) | Unidad de medida |
| cantidad_surtida | FLOAT | Cantidad ya trasladada |

---

## 3. FORMATO JSON EXPORTADO

Ejemplo de archivo JSON exportado:

```json
{
  "requisicion": "REQ-001",
  "fecha": "2026-04-01T10:30:00",
  "origen": "principal",
  "destino": "restaurante",
  "estado": "pendiente",
  "productos": [
    {
      "ingrediente": "Arroz",
      "cantidad": 50.0,
      "unidad": "kg"
    },
    {
      "ingrediente": "Frijoles",
      "cantidad": 25.0,
      "unidad": "kg"
    }
  ]
}
```

---

## 4. PASOS DE IMPLEMENTACIÓN

### 4.1 Crear tablas en Supabase

**Opción A: Ejecutar SQL manualmente**

1. Ir a Supabase Dashboard → SQL Editor
2. Copiar el contenido de `migracion_requisiciones.sql`
3. Ejecutar el script

**Opción B: Ejecutar desde Python**

```python
# En el proyecto control-entradas-salidas
python -c "
from config.config import get_settings
from sqlalchemy import create_engine, text

settings = get_settings()
url = f'postgresql+pg8000://{settings.DB_USER}:{settings.DB_PASSWORD}@{settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}'
engine = create_engine(url)

with open('migracion_requisiciones.sql', 'r') as f:
    sql = f.read()

with engine.connect() as conn:
    conn.execute(text(sql))
    conn.commit()
print('Tablas creadas exitosamente')
"
```

---

### 4.2 En el Sistema Restaurante

#### 4.2.1 Crear función para importar requisiciones

Agregar en `database/movements.py`:

```python
def importar_requisicion(data: dict, usuario: str) -> tuple[bool, str]:
    """
    Procesa una requisición de traslado desde JSON.
    
    Args:
        data: Dict con formato de requisición JSON
        usuario: Nombre del usuario que procesa
    
    Returns:
        (success, message)
    """
    origen = data.get("origen", "").replace("Almacen_", "").lower()
    destino = data.get("destino", "").replace("Almacen_", "").lower()
    
    if origen == destino:
        return False, "Origen y destino no pueden ser iguales"
    
    if origen not in {"principal", "restaurante"}:
        return False, f"Almacén origen '{origen}' no válido"
    
    if destino not in {"principal", "restaurante"}:
        return False, f"Almacén destino '{destino}' no válido"
    
    productos = data.get("productos", [])
    if not productos:
        return False, "No hay productos en la requisición"
    
    traslados = []
    for p in productos:
        traslados.append({
            "ingrediente": p.get("ingrediente", ""),
            "cantidad": float(p.get("cantidad", 0)),
            "origen": f"Almacen_{origen.title()}",
            "destino": f"Almacen_{destino.title()}",
            "usuario": usuario,
        })
    
    return procesar_traslados(traslados)
```

#### 4.2.2 Crear vista para importar JSON

En `views/traslados.py`, agregar función para cargar desde portapapeles:

```python
def importar_desde_portapapeles():
    """Importa requisición desde el portapapeles del sistema."""
    import pyperclip
    import json
    
    try:
        json_str = pyperclip.paste()
        data = json.loads(json_str)
        
        if "productos" not in data:
            return False, "JSON no es una requisición válida"
        
        success, msg = importar_requisicion(data, get_current_user())
        
        if success:
            refresh_cache()
        
        return success, msg
    except json.JSONDecodeError:
        return False, "El portapapeles no contiene JSON válido"
    except Exception as e:
        return False, f"Error: {str(e)}"
```

#### 4.2.3 Agregar botón en la UI

En la sección de traslados del restaurante:

```python
import_btn = ft.ElevatedButton(
    text="Importar desde Control",
    icon=ft.Icons.UPLOAD_FILE,
    on_click=lambda _: importar_desde_portapapeles(),
)
```

---

## 5. FLUJO DE TRABAJO

### Paso 1: Crear requisición (Control de Entradas)
```
1. Ir a la sección "Requisiciones"
2. Hacer clic en [+] 
3. Ingresar:
   - Número de requisición: REQ-001
   - Origen: principal
   - Destino: restaurante
4. Agregar productos con cantidades
5. Hacer clic en "Crear"
```

### Paso 2: Exportar requisición (Control de Entradas)
```
1. En la lista de requisiciones, buscar REQ-001
2. Hacer clic en "Ver" o "Exportar"
3. Hacer clic en "Copiar al Portapapeles"
4. El JSON está ahora en el portapapeles
```

### Paso 3: Importar requisición (Sistema Restaurante)
```
1. Ir a la sección de Traslados
2. Hacer clic en "Importar desde Control"
3. El sistema importa y procesa automáticamente:
   - Resta del almacén origen (principal)
   - Suma al almacén destino (restaurante)
   - Registra movimientos en historial
```

---

## 6. VERIFICACIÓN

### Verificar que las tablas existen:
```sql
SELECT * FROM requisiciones LIMIT 5;
SELECT * FROM requisicion_detalles LIMIT 5;
```

### Verificar almacenes disponibles:
```sql
SELECT DISTINCT almacen FROM existencias ORDER BY almacen;
```

---

## 7. ALMACENES VÁLIDOS

Los almacenes deben coincidir en ambas aplicaciones:

| Almacén | Descripción |
|---------|-------------|
| `principal` | Almacén principal/depósito |
| `restaurante` | Almacén del restaurante |

---

## 8. RESOLUCIÓN DE PROBLEMAS

### Error: "Almacén no válido"
- Verificar que los almacenes existan en `existencias`
- Verificar que el nombre coincida exactamente (case-sensitive)

### Error: "Stock insuficiente"
- Verificar que haya suficiente stock en el almacén origen
- Los productos deben existir en el almacén origen

### Error: "JSON no válido"
- Verificar que el portapapeles contenga JSON válido
- Usar la función de exportar para copiar el formato correcto

---

## 9. CONTACTOS

Para dudas técnicas, contactar al desarrollador del sistema.

---

**Documento generado automáticamente**  
Control de Entradas/Salidas v2.0
