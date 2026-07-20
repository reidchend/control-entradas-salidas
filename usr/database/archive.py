"""
Archivado de movimientos antiguos.
Mueve movimientos > N meses a movimientos_archivo y elimina los > N+M meses.
"""
from datetime import datetime, timedelta
from typing import Optional
from usr.database.local_replica import LocalReplica
from usr.database.conn import get_local_conn


def archivar_movimientos(meses_activos: int = 3, meses_retencion: int = 7):
    """
    - Mueve a movimientos_archivo los movimientos sin factura > mes_limite
    - Los movimientos con factura NEVERACION se archivan (quedan siempre en principal)
    - Elimina de movimientos_archivo los registros > meses_retencion
    
    Args:
        meses_activos: meses que se conservan en la tabla principal
        meses_retencion: meses totales que se conservan (principal + archivo)
    """
    ahora = datetime.now()
    fecha_limite_principal = (ahora - timedelta(days=meses_activos * 30)).isoformat()
    fecha_limite_eliminar = (ahora - timedelta(days=meses_retencion * 30)).isoformat()

    conn = get_local_conn()
    cursor = conn.cursor()

    # 1. Seleccionar movimientos a archivar (sin factura_id y antiguos)
    cursor.execute("""
        SELECT * FROM movimientos 
        WHERE fecha_movimiento < ? AND factura_id IS NULL
        ORDER BY fecha_movimiento
    """, (fecha_limite_principal,))
    a_archivar = [dict(row) for row in cursor.fetchall()]

    archivados = 0
    for mov in a_archivar:
        # Insertar en archivo
        cursor.execute("""
            INSERT OR IGNORE INTO movimientos_archivo
            (id, producto_id, factura_id, tipo, cantidad, cantidad_anterior, cantidad_nueva,
             peso_total, peso_registrado, foto_peso_url, registrado_por, observaciones,
             almacen, fecha_movimiento, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            mov.get('id'), mov.get('producto_id'), mov.get('factura_id'),
            mov.get('tipo'), mov.get('cantidad'), mov.get('cantidad_anterior', 0),
            mov.get('cantidad_nueva', 0), mov.get('peso_total', 0),
            mov.get('peso_registrado'), mov.get('foto_peso_url'),
            mov.get('registrado_por'), mov.get('observaciones'),
            mov.get('almacen'), mov.get('fecha_movimiento'), mov.get('created_at')
        ))
        # Eliminar de principal
        cursor.execute("DELETE FROM movimientos WHERE id = ?", (mov['id'],))
        archivados += 1

    # 2. Eliminar archivos muy antiguos
    cursor.execute(
        "DELETE FROM movimientos_archivo WHERE fecha_movimiento < ?",
        (fecha_limite_eliminar,)
    )
    eliminados = cursor.rowcount

    conn.commit()
    conn.close()

    if archivados > 0 or eliminados > 0:
        print(f"[ARCHIVE] {archivados} movimientos archivados, {eliminados} eliminados del archivo")

    return archivados, eliminados
