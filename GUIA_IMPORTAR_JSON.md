# Guía para integrar requisiciones desde Control Entradas

## Cambios en Sistema Restaurante

### 1. `database/movements.py` - Agregar al final del archivo

```python
def get_requisiciones_pendientes():
    """Obtiene requisiciones pendientes del almacén restaurante"""
    with get_conn() as conn:
        cursor = conn.cursor()
        if DB_TYPE.lower() == "postgresql":
            cursor.execute("""
                SELECT r.id, r.numero, r.origen, r.destino, r.estado, 
                       r.fecha_creacion, r.creada_por
                FROM requisiciones r
                WHERE r.destino = 'restaurante' AND r.estado = 'pendiente'
                ORDER BY r.fecha_creacion DESC
            """)
        else:
            cursor.execute("""
                SELECT id, numero, origen, destino, estado, fecha_creacion, creada_por
                FROM requisiciones
                WHERE destino = 'restaurante' AND estado = 'pendiente'
                ORDER BY fecha_creacion DESC
            """)
        rows = cursor.fetchall()
        fields = [d[0] for d in cursor.description] if cursor.description else None
        return [row_to_dict(r, fields) for r in rows]


def get_requisicion_detalles(requisicion_id: int):
    """Obtiene los detalles de una requisición"""
    with get_conn() as conn:
        cursor = conn.cursor()
        if DB_TYPE.lower() == "postgresql":
            cursor.execute("""
                SELECT rd.*, p.nombre as producto_nombre
                FROM requisicion_detalles rd
                LEFT JOIN productos p ON rd.producto_id = p.id
                WHERE rd.requisicion_id = %s
            """, (requisicion_id,))
        else:
            cursor.execute("SELECT * FROM requisicion_detalles WHERE requisicion_id = ?", (requisicion_id,))
        rows = cursor.fetchall()
        fields = [d[0] for d in cursor.description] if cursor.description else None
        return [row_to_dict(r, fields) for r in rows]


def marcar_requisicion_completada(requisicion_id: int, procesada_por: str = "Sistema"):
    """Marca una requisición como completada"""
    from datetime import datetime
    with get_conn() as conn:
        cursor = conn.cursor()
        fecha = datetime.now().isoformat()
        if DB_TYPE.lower() == "postgresql":
            cursor.execute("""
                UPDATE requisiciones 
                SET estado = 'completada', procesada_por = %s, fecha_procesamiento = %s
                WHERE id = %s
            """, (procesada_por, fecha, requisicion_id))
        else:
            cursor.execute("""
                UPDATE requisiciones 
                SET estado = 'completada', procesada_por = ?, fecha_procesamiento = ?
                WHERE id = ?
            """, (procesada_por, fecha, requisicion_id))
```

### 2. `views/traslados.py` - Agregar después de `cancelar_todo`

```python
    def cargar_requisiciones():
        """Carga requisiciones pendientes desde la BD"""
        try:
            requisiciones = db.get_requisiciones_pendientes()
            req_list_ref.current.controls.clear()
            
            if not requisiciones:
                req_list_ref.current.controls.append(
                    txt("No hay requisiciones pendientes", 12, color=c("text_muted"))
                )
            else:
                for req in requisiciones:
                    req_detalles = db.get_requisicion_detalles(req["id"])
                    num_productos = len(req_detalles)
                    
                    req_card = ft.Container(
                        content=ft.Column([
                            ft.Row([
                                txt(f"#{req['numero']}", 13, FontWeight.W_700),
                                txt(req['fecha_creacion'].split('T')[0] if req['fecha_creacion'] else '', 11, color=c("text_muted")),
                            ], alignment=MainAxisAlignment.SPACE_BETWEEN),
                            txt(f"De: {req['origen'].title()} → {req['destino'].title()}", 11, color=c("text_muted")),
                            txt(f"{num_productos} producto(s)", 11, color=ACCENT),
                            ft.Row([
                                ft.ElevatedButton("Cargar", icon=Icons.DOWNLOAD, 
                                                  on_click=lambda _, r=req, d=req_detalles: cargar_detalles_requisicion(r, d),
                                                  bgcolor=ACCENT, color="white"),
                                ft.ElevatedButton("Completar", icon=Icons.CHECK,
                                                  on_click=lambda _, r=req: completar_requisicion(r),
                                                  bgcolor=SUCCESS, color="white"),
                            ], spacing=5),
                        ], tight=True, spacing=4),
                        padding=12,
                        bgcolor=c("bg3"),
                        border_radius=8,
                    )
                    req_list_ref.current.controls.append(req_card)
            
            req_list_ref.current.update()
        except Exception as ex:
            snack(page, f"Error cargando requisiciones: {ex}", error=True)

    def cargar_detalles_requisicion(req, detalles):
        """Carga los detalles de una requisición a pendientes"""
        origen_map = {"principal": "Almacen_Principal", "restaurante": "Almacen_Restaurante"}
        destino_map = {"principal": "Almacen_Principal", "restaurante": "Almacen_Restaurante"}
        
        origen = origen_map.get(req.get("destino", "principal"), "Almacen_Principal")
        destino = destino_map.get(req.get("destino", "restaurante"), "Almacen_Restaurante")
        usr = req.get("creada_por", "Sistema") or "Sistema"
        
        for d in detalles:
            pendientes.append({
                "ingrediente": d.get("ingrediente") or d.get("producto_nombre") or "",
                "cantidad": float(d.get("cantidad", 0)),
                "origen": origen,
                "destino": destino,
                "usuario": usr,
            })
        
        rebuild()
        snack(page, f"✓ {len(detalles)} producto(s) cargados de #{req['numero']}", error=False)

    def completar_requisicion(req):
        """Marca una requisición como completada"""
        def do_it(e):
            try:
                db.marcar_requisicion_completada(req["id"])
                snack(page, f"✓ Requisición #{req['numero']} completada", error=False)
                cargar_requisiciones()
            except Exception as ex:
                snack(page, f"Error: {ex}", error=True)
        
        confirm_dialog(page, "Completar Requisición",
                       f"¿Marcar #{req['numero']} como completada?",
                       do_it)
```

### 3. `views/traslados.py` - Agregar refs al inicio

```python
    req_list_ref    = ft.Ref[Column]()
```

### 4. `views/traslados.py` - Agregar panel al final del return

Agregar ANTES del último `return` o al final de la estructura:

```python
        Container(height=16),
        card(Column([
            Row([
                txt("REQUISICIONES DE ALMACÉN", 12, FontWeight.W_700, ACCENT),
                Container(expand=True),
                ft.IconButton(Icons.REFRESH, on_click=lambda _: cargar_requisiciones(), tooltip="Actualizar"),
            ], alignment=MainAxisAlignment.SPACE_BETWEEN),
            Container(height=8),
            Container(
                ref=req_list_ref,
                content=Column([txt("Cargando...", 12, color=c("text_muted"))], tight=True),
                height=200,
            ),
        ])),
    ], spacing=0, scroll=ScrollMode.AUTO, expand=True)
    
    page.run_task(lambda: cargar_requisiciones())
```

---

## Uso

1. **Control Entradas**: Crear requisición con destino "Restaurante" → Guardar
2. **Sistema Restaurante**: Ir a Traslados → Ver requisiciones en panel inferior
3. Clic **"Cargar"** → Productos se agregan a pendientes
4. Clic **"Completar"** → Requisición se marca como completada

## Mapeo de almacenes

| Control Entradas | Sistema Restaurante |
|------------------|---------------------|
| principal        | Almacen_Principal   |
| restaurante      | Almacen_Restaurante |

## Requisitos

- Ambas apps deben usar la misma base de datos (Supabase/PostgreSQL)
- Las tablas `requisiciones` y `requisicion_detalles` deben existir
