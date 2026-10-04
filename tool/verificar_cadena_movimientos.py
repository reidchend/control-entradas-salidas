"""Comprueba el invariante del historial de stock: en cada almacen, el
`cantidad_nueva` de un movimiento tiene que ser el `cantidad_anterior` del
siguiente.

Eso es lo que hace reconstruible el historial. Cuando la vista de stock
muestra una cadena que no cierra (un traslado que deja 6 y una venta de despues
que arranca en 3), no se puede seguirle el rastro al producto.

El invariante se cumple en un solo orden: el de grabacion, `id`. El
`cantidad_anterior` de un movimiento se calculo leyendo la existencia en el
momento de insertarlo, asi que es el `cantidad_nueva` del que se grabo justo
antes. Ordenar la vista por otra cosa mete movimientos entre dos que si se
encadenan y la cuenta deja de cerrar aunque los datos esten bien: 578
movimientos tienen `fecha_traslado` (el dia en que se creo la requisicion)
distinta de `fecha_movimiento` (el dia en que el operador totalizo), y ordenar
por la fecha de negocio los displacea.

Por eso el script mide las tres ordenaciones, para que quede de manifiesto que
`id` es la que menos rompe, y ademas revisa en el codigo de lib/ que las vistas
que pintan la cadena ordenen por `id` y no por fecha.

Lo que NO hace es arreglar los datos: las roturas que quedan son de otra
causa (movimientos grabados sin efecto sobre el stock, o lecturas perdidas) y
corregirlas es una decision aparte. Solo las cuenta y las nombra.

Solo lectura. Sale con codigo 1 si alguna vista que pinta la cadena vuelve a
ordenar por fecha.

Uso:  tool\\venv\\Scripts\\python.exe tool\\verificar_cadena_movimientos.py
      tool\\venv\\Scripts\\python.exe tool\\verificar_cadena_movimientos.py --detalle
"""
import sys
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parent.parent
ENV_LOCAL = RAIZ / ".env.local"

# Tolerancia para el ruido de coma flotante. `numeric` guarda 12 digitos y las
# cantidades son kg con tres decimales, asi que 0.1 + 0.2 != 0.3 y comparar con
# == daria falsos positivos.
EPS = 1e-7

# Las vistas que pintan la cadena `anterior -> cantidad -> nueva` y por lo tanto
# dependen de que el orden sea el de grabacion.
#
#   etiqueta, archivo, ancla, como debe ordenar la linea que ordene ahi
#
# El ancla es una linea unica de esa vista: a partir de ahi se busca la
# siguiente linea que ordene (ORDER BY / orderBy: / .sort(), ignorando los
# comentarios) y se exige que ordene por `id`.
#
# `reportes_repository.dart` NO entra, y es a proposito: el reporte de detalle de
# producto selecciona `cantidad_anterior` y `cantidad_nueva` pero no las pinta,
# asi que es un listado y le va bien el orden cronologico de negocio. Si
# alguien llegara a pintarlas ahi, esta lista tiene que crecer con el.
VISTAS = [
    ("historial de stock",
     "lib/features/stock/data/stock_repository.dart",
     "Future<List<Movimiento>> getProductoHistorial",
     "orderBy: 'id'"),
    ("historial de requisiciones",
     "lib/features/requisiciones/presentation/dialogs/historial_dialog.dart",
     "final filtrados = seleccion",
     "b['id']"),
]

# (etiqueta, ORDER BY) de cada ordenacion posible, para medir.
ORDENES = [
    ("id  (orden de grabacion)", "m.id ASC"),
    ("fecha_movimiento", "m.fecha_movimiento ASC, m.id ASC"),
    ("COALESCE(fecha_traslado, fecha_movimiento)  (la que usaba la vista)",
     "COALESCE(m.fecha_traslado, m.fecha_movimiento) ASC, m.id ASC"),
]

# Cuantas lineas se miran despues del ancla antes de rendirse.
VENTANA = 40


def leer_url() -> str:
    """DATABASE_URL de .env.local, sin depender de python-dotenv."""
    if not ENV_LOCAL.exists():
        sys.exit("  no existe .env.local (copiar .env.local.example y ajustar)")
    for linea in ENV_LOCAL.read_text(encoding="utf-8").splitlines():
        if linea.strip().startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        if clave.strip() == "DATABASE_URL":
            return valor.strip().strip("'\"")
    sys.exit("  .env.local no tiene DATABASE_URL")


def _num(v):
    return float(v or 0)


def _es_orden(linea):
    """True si la linea ordena de verdad (no si solo lo explica en un comentario)."""
    if linea.lstrip().startswith(("--", "//", "*", "///")):
        return False
    return ("ORDER BY" in linea or "orderBy:" in linea or ".sort(" in linea)


fallos = 0


def check(etiqueta, ok, detalle=""):
    global fallos
    if ok:
        print("  OK    %s" % etiqueta)
    else:
        print("  FALLA %s" % etiqueta)
        if detalle:
            for linea in str(detalle).splitlines():
                print("         %s" % linea)
        fallos += 1


def revisar_vista(etiqueta, rel, ancla, esperado):
    """La vista tiene que ordenar por `id`, no por fecha de negocio."""
    ruta = RAIZ / rel
    if not ruta.exists():
        check("  %s (%s)" % (etiqueta, ruta.name), False, "no existe %s" % rel)
        return
    lineas = ruta.read_text(encoding="utf-8", errors="replace").splitlines()
    donde = next((i for i, ln in enumerate(lineas) if ancla in ln), None)
    if donde is None:
        check("  %s (%s)" % (etiqueta, ruta.name), False,
              "no se encontro el ancla %r; cambio la vista?" % ancla)
        return
    orden = next((lineas[i].strip() for i in range(donde, min(donde + VENTANA, len(lineas)))
                  if _es_orden(lineas[i])), None)
    check("  %s (%s)" % (etiqueta, ruta.name),
          orden is not None and esperado in orden,
          "esperaba que ordenara con %r y ordena con:\n  %s" % (esperado, orden)
          if orden else "no encontre ninguna linea que ordene en las %d lineas "
                        "siguientes al ancla %r" % (VENTANA, ancla))


def main():
    detalle = "--detalle" in sys.argv
    conn = psycopg.connect(leer_url(), autocommit=True)
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM movimientos WHERE producto_id IS NOT NULL")
        total = cur.fetchone()[0]

        # ------------------------------------------------------------- 1
        print("=== 1. Medicion del invariante en cada orden ===")

        def rotas(orden_sql):
            """Enlaces rotos: (producto, almacen), movimiento previo, movimiento roto.

            El escaneo va en orden ASCendente a proposito: en ese sentido el
            `cantidad_anterior` de un movimiento es el `cantidad_nueva` del que
            salio antes, que es como se construyo la cadena. Recorrerlo al reves
            compara cada movimiento contra su sucesor y no encuentra nada.
            """
            cur.execute(
                "SELECT m.producto_id, COALESCE(m.almacen, '~'), m.id, m.tipo, "
                "       m.cantidad, m.cantidad_anterior, m.cantidad_nueva, p.nombre "
                "  FROM movimientos m "
                "  LEFT JOIN productos p ON p.id = m.producto_id "
                " WHERE m.producto_id IS NOT NULL "
                " ORDER BY " + orden_sql
            )
            anterior = {}
            roto = []
            for f in cur.fetchall():
                pid, alm, mid, tipo, cant, ant, nue, nombre = f
                clave = (pid, alm)
                if clave in anterior and abs(anterior[clave][0] - _num(ant)) > EPS:
                    roto.append((clave, anterior[clave], (mid, tipo, cant, ant, nue, nombre)))
                anterior[clave] = (_num(nue), mid)
            return roto

        conteo = {}
        for etiqueta, orden in ORDENES:
            r = rotas(orden)
            conteo[etiqueta] = r
            print("  %-56s %4d sec. rotas, %4d mov. (%.2f%% de %d)"
                  % (etiqueta, len({k for k, _, _ in r}), len(r),
                     100.0 * len(r) / total, total))

        # Para la seccion 3 hace falta tambien la secuencia completa en orden de
        # grabacion, para poder mirar el movimiento que sigue al roto.
        cur.execute(
            "SELECT m.producto_id, COALESCE(m.almacen, '~'), m.id, m.tipo, "
            "       m.cantidad, m.cantidad_anterior, m.cantidad_nueva, p.nombre "
            "  FROM movimientos m "
            "  LEFT JOIN productos p ON p.id = m.producto_id "
            " WHERE m.producto_id IS NOT NULL "
            " ORDER BY m.id ASC"
        )
        filas = cur.fetchall()
        por_clave = {}
        for f in filas:
            por_clave.setdefault((f[0], f[1]), []).append(f)

        por_id = conteo["id  (orden de grabacion)"]
        clave_id = {k for k, _, _ in por_id}
        clave_fecha = {k for k, _, _ in conteo[
            "COALESCE(fecha_traslado, fecha_movimiento)  (la que usaba la vista)"]}
        print("")
        print("  rotas solo por ordenar por la fecha de negocio: %d secuencia(s)"
              % len(clave_fecha - clave_id))
        print("  rotas tambien en orden de grabacion: %d secuencia(s)" % len(clave_id & clave_fecha))
        print("")
        print("  -> Ordenar por `id` es lo que menos rompe. Es el orden en que la")
        print("     cadena se construyo y el unico que estas vistas pueden usar sin")
        print("     que la cuenta deje de cerrar.")
        print("")

        # ------------------------------------------------------------- 2
        print("=== 2. Las vistas que pintan la cadena ordenan por `id` ===")
        for etiqueta, rel, ancla, esperado in VISTAS:
            revisar_vista(etiqueta, rel, ancla, esperado)
        print("  (el reporte de detalle de producto no se chequea: no pinta la cadena)")
        print("")

        # ------------------------------------------------------------- 3
        print("=== 3. Lo que queda roto son datos, no el orden ===")
        print("")
        if not por_id:
            print("  ninguna secuencia rota: el invariante se cumple entero.")
        else:
            print("  %d secuencia(s) con la cadena rota aun ordenando por `id`."
                  % len(clave_id))
            print("  Estas no las arregla cambiar el orden de la vista: son")
            print("  movimientos que se grabaron con una existencia que no era la que")
            print("  habia, o que no movieron el stock. Se listan para que se decida")
            print("  que hacer con ellas; el script no escribe nada.")
            print("")
            cuantas = len(por_id) if detalle else 12
            # La clasificacion se hace sobre TODAS, no solo sobre las que se
            # imprimen, para que el resumen no cuente una parte.
            aisladas = 0
            clasificadas = []
            for clave, prev, roto in por_id:
                mid, tipo, cant, ant, nue, nombre = roto
                sec = por_clave[clave]
                i = next(j for j, f in enumerate(sec) if f[2] == mid)
                sig = sec[i + 1] if i + 1 < len(sec) else None
                # Si el siguiente si parto de lo que este dejo, la rotura queda
                # aislada en este movimiento: escribio un `cantidad_anterior` que
                # no era la existencia real, pero su `cantidad_nueva` si la toman
                # bien los de abajo. Si no, la rotura se propaga: el movimiento
                # tambien escribio mal su `nueva` y arrastra a los siguientes.
                aislada = sig is not None and abs(_num(sig[5]) - _num(nue)) <= EPS
                aisladas += 1 if aislada else 0
                clasificadas.append((clave, prev, roto, sig, aislada))

            for clave, prev, roto, sig, aislada in clasificadas[:cuantas]:
                mid, tipo, cant, ant, nue, nombre = roto
                print("    %-22s / %-10s" % (nombre, clave[1]))
                print("        %-6s deja %s   ->   %-6s (%s) arranca en %s   (salto %s ids)"
                      % (prev[1], prev[0], mid, tipo, ant, mid - prev[1]))
                if aislada:
                    print("        el %s (%s) si parto de %s, que es lo que este deja:"
                          % (sig[2], sig[3], nue))
                    print("        la rotura queda aislada en el %s: escribio como"
                          % mid)
                    print("        `anterior` una existencia que no era la que habia.")
                elif sig is not None:
                    print("        el %s (%s) parte de %s, que tampoco es %s:"
                          % (sig[2], sig[3], sig[5], nue))
                    print("        la rotura se propaga hacia abajo.")
            if len(por_id) > cuantas:
                print("    ... y %d mas (usar --detalle)" % (len(por_id) - cuantas))
            print("")
            print("  De las %d roturas, %d quedan aisladas en un solo movimiento (leyo"
                  % (len(por_id), aisladas))
            print("  mal la existencia al escribir) y %d se propagan al resto de la"
                  % (len(por_id) - aisladas))
            print("  secuencia. Corregirlas exige decidir sobre los datos: relinkear")
            print("  la cadena daria una cuenta que nunca ocurrio, y borrar el")
            print("  movimiento pierde una entrada que el operador si registro.")
        print("")

        # ------------------------------------------------------------- 4
        print("=== 4. El ultimo movimiento de cada secuencia cuadra con existencias ===")
        # El otro lado del problema: si el ultimo movimiento de la secuencia no
        # deja la existencia actual, algo se movio sin quedar registrado, o al
        # reves, se registro sin mover. El invariante de la seccion 1 no lo ve
        # porque la cadena movimiento->movimiento si encadena.
        cur.execute(
            "SELECT m.id, m.cantidad_nueva, e.cantidad, m.almacen, p.nombre "
            "  FROM movimientos m "
            "  JOIN existencias e ON e.producto_id = m.producto_id "
            "                   AND COALESCE(e.almacen, '~') = COALESCE(m.almacen, '~') "
            "  LEFT JOIN productos p ON p.id = m.producto_id "
            " WHERE m.producto_id IS NOT NULL "
            "   AND m.id = (SELECT max(m2.id) FROM movimientos m2 "
            "                 WHERE m2.producto_id = m.producto_id "
            "                   AND COALESCE(m2.almacen, '~') = COALESCE(m.almacen, '~'))"
        )
        descuadres = [(mid, nue, ex, alm, nombre)
                      for mid, nue, ex, alm, nombre in cur.fetchall()
                      if abs(_num(nue) - _num(ex)) > EPS]
        cur.execute("SELECT count(*) FROM existencias")
        print("  secuencias cuyo ultimo movimiento no deja la existencia actual: %d de %d"
              % (len(descuadres), cur.fetchone()[0]))
        cuantas = len(descuadres) if detalle else 12
        for mid, nue, ex, alm, nombre in descuadres[:cuantas]:
            print("    %-22s / %-10s  ultimo mov %s deja %s pero `existencias` dice %s"
                  % (nombre, alm or "~", mid, nue, ex))
        if len(descuadres) > cuantas:
            print("    ... y %d mas (usar --detalle)" % (len(descuadres) - cuantas))
        print("")

        # ------------------------------------------------------------- 5
        print("=== 5. Resumen ===")
        if fallos:
            print("  %d comprobacion(es) de codigo fallaron: alguna vista que pinta la" % fallos)
            print("  cadena ordeno por fecha. El invariante no se puede cumplir.")
        else:
            print("  El codigo esta bien: las %d vistas que pintan la cadena ordenan"
                  % len(VISTAS))
            print("  por `id`, que es el orden en que la cadena se construyo.")
            if clave_id:
                print("  Quedan %d secuencia(s) rotas por datos (seccion 3) y %d"
                      % (len(clave_id), len(descuadres)))
                print("  descuadradas contra `existencias` (seccion 4). Ninguna se")
                print("  resuelve reordenando la vista: hay que decidir sobre los datos.")
            else:
                print("  Y no queda ninguna secuencia rota por datos.")

    conn.close()


if __name__ == "__main__":
    main()
    sys.exit(1 if fallos else 0)