# Instrucciones para Agente en PC Servidor (Windows)

## Estado actual del proyecto (01/10/2026)

### Bugs reportados: resueltos

Los tres problemas que se listaban aquí tenían **una sola causa raíz**, en
`tool/server.py`:

`_exec_autocommit()` ejecutaba el cursor pero **nunca leía las filas** y
devolvía `[]` fijo. Como `HttpSqlSession.execute` solo manda `txid` dentro de
`runTx`, todo `SELECT` que no estuviera en una transacción explícita llegaba
vacío a la app.

| Síntoma reportado | Causa |
|---|---|
| Login no detecta usuario existente | `existeOperador` chequeaba `rows.isNotEmpty`, siempre `false` |
| La UI se queda en modo "Registro" | misma llamada; `_existeNombre` nunca se ponía en `true` |
| Usuarios duplicados | `registrarOperador` no veía el nombre y siempre insertaba |

Se corrigió delegando en `_exec_sql()`, que ya serializaba bien.

### Segundo bug, independiente: placeholders cruzados

`PgQueryBuilder` asignaba los números de placeholder en orden de
construcción, no de aparición. En un `UPDATE` los filtros del WHERE se
registran antes que los SET, así que el texto salía
`SET factura_id = $3 WHERE id IN ($1, $2)` con los parámetros por índice
`[45, 46, 12]`. Ambos drivers resuelven por posición en el texto, así que se
ejecutaba `SET factura_id = 45 WHERE id IN (46, 12)`: la entrada que debía
vincularse quedaba en `NULL` y el UPDATE escribía sobre filas ajenas.

Corregido con `_bindPlan()` en `lib/core/data/pg_client.dart`, que renumera
por orden de aparición.

### Tercer bug: placeholder repetido

`ReportesRepository.buscarProductos` repetía `$1` en dos `ILIKE`.
`convert_placeholders` convierte *cada aparición* a `%s`, así que psycopg
recibía dos `%s` con un valor y devolvía 500. El autocomplete de productos en
Reportes no funcionaba por proxy.

### Cuarto bug: el mismo, en otra parte

`ActivosRepository.existeCategoria` repetía `$2`:

```sql
WHERE LOWER(nombre) = LOWER($1) AND ($2::int IS NULL OR id <> $2)
```

Mismo 500 (`the query has 3 placeholders but 2 parameters were passed`). Aquí
lo grave es **dónde** se llamaba: la comprobación de duplicados estaba fuera
del `try/catch` de `activos_categorias_grid.dart`, así que la excepción se comía
el `return`, el diálogo se cerraba y **el renombrado de categoría no pasaba
nada** sin error visible. Ahora usa `$2` y `$3`.

> **Por qué no lo detectó el lint**: el lint de placeholders repetidos existía,
> pero `PLACEHOLDER_RE` captura el `$` incluido y hacía
> `sorted(malos, key=int)` sobre `'$2'`, que revienta con `ValueError`. O sea,
> en vez de reportar el bug **murió** con un error propio, y como el crash
> abortaba `main()` antes del resumen, no se leía como un fallo del lint.
> Arreglado (`key=lambda x: int(x[1:])`) y verificado que ahora falla si se
> reintroduce el `$2` repetido.
>
> **Regla**: nunca repetir `$N` en un `executeSql`/`executeCommand`. La
> consulta directa contra la base sí lo tolera (por eso las sondas que pegan
> contra PostgreSQL no lo ven), pero por proxy siempre falla.

### Pendiente: `UNIQUE` de `device_id`

La migración `20250102000000_add_device_id.sql` declara
`device_id TEXT UNIQUE`, pero en la base **solo existe el PRIMARY KEY**.

No se aplica, y ahora por una razón distinta a la original: el modelo es de
**una fila por `(operador, dispositivo)`**, así que un operador en tres equipos
son tres filas; y cambiar de usuario en el mismo equipo (*Usar otro*) deja dos
filas con el mismo `device_id`. Con el `UNIQUE` puesto el login fallaría con
`23505`. Si alguna vez se quiere, el índice va por `(nombre, device_id)`.

Las filas repetidas que ya existen (5 con `acc2a6f6…`) son de la época en que
`verificarPin` pisaba el `device_id` de una sola fila. Hoy esa lógica ya no
genera basura: inserta solo si no hay fila para ese `(nombre, device_id)`.

---

## Diagnóstico

### Logs: ya no hay qué mirar

Los `print()` de debug con prefijo (`[LOGIN_SCREEN]`, `[SESSION]`,
`[VALIDACION]`, `[DIRECT_DB]`, `[COMMIT_OK]`) **se eliminaron**. No se
reponen con otros: `LogBridge.push()` acumula en una lista que nunca se envía y
`flush()` está vacío, así que nunca llegaban a ninguna terminal.

Para ver el estado real, usar `tool/smoke_sql.py` (ver abajo) o consultar la
base directo.

### Smoke test de la ruta SQL

No necesita Flutter ni Dart. Cubre el ciclo completo
app → `tool/server.py` → PostgreSQL.

```cmd
cd C:\ruta\al\repo
tool\venv\Scripts\python.exe tool\server.py 8123
:: en otra terminal
tool\venv\Scripts\python.exe tool\smoke_sql.py
```

Verifica conectividad, rechazo de token inválido, orden de parámetros en
`UPDATE`, el caso del placeholder repetido, `buscarProductos`, el catálogo del
POS (que los booleanos vayan como `true`/`false` y no como `1`/`0`), que no
queden tablas de prueba, el flujo de un operador en varios dispositivos sin que
uno desvincule a los otros, y tres lints que recorren `lib/`: `.eq()` numérico
sobre una columna boolean, listeners con la firma equivocada para
`addListener`, y SQL crudo que repite un `$n`.

Sale con código 1 si algo falla. Son 12 pruebas.

> Cuando se agrega un lint o una prueba nueva, **verificar que falla** con el
> bug reintroducido a propósito. Un lint que nunca se vio rojo no se sabe si
> sirve: el de placeholders repetidos llevaba tiempo roto sin enterarse.

---

## Pasos para reproducir y diagnosticar

### 1. Preparar entorno
```cmd
cd C:\ruta\al\repo
git pull origin main
```

### 2. Recompilar app Windows (Inventario)
```cmd
flutter run -d windows -t lib\main.dart ^
  --dart-define=APP_ID=inventario ^
  --dart-define=APP_LABEL="Control de Entradas y Salidas" ^
  --dart-define=WHATSAPP_BOT_TOKEN=TU_TOKEN ^
  --dart-define=PROXY_SQL_TOKEN=TU_TOKEN ^
  --dart-define=GIST_ID=5b37693a243d8d2235eea0647396b8d3
```

### 3. Actualizar y reiniciar servidor Python
```cmd
# En otra terminal
cd C:\ruta\al\repo
git pull origin main
taskkill /F /IM python.exe /IM cloudflared.exe
iniciar_todo.bat
```

El túnel de Cloudflare no sirve de nada si `server.py` no está corriendo: el
proxy es el único que habla con PostgreSQL. Verificar con
`Get-NetTCPConnection -State Listen -LocalPort 8123`.

### 4. Probar login
- Usuario: `Reidchend` (con mayúscula)
- PIN: `1234`
- Al abrir la app el nombre **debería venir puesto y fijo** (autodetección por
  `device_id`), con un botón *Usar otro* al lado. Si aparece el campo de texto
  vacío, la autodetección no corrió: mira si `estadoBdProvider` llegó a `lista`.
- Solo hace falta el PIN.
- Para probar el flujo manual, tocar *Usar otro*: ahí sí se espera ~300 ms
  después de terminar de escribir el nombre (debounce) y debería cambiar a modo
  "Login" (botón "Desbloquear").

### 5. Verificar en BD
```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas -c "SELECT d.id, u.nombre, d.device_id, d.configurado_en FROM usuario_dispositivos d JOIN usuarios u ON u.id = d.usuario_id ORDER BY d.id;"
```

Un operador en varios dispositivos tiene **una fila por dispositivo**, todas con
el mismo `nombre` y distinto `device_id`. Si dos filas del mismo `device_id`
tienen operadores distintos, es lo normal: se cambió de usuario en ese equipo.

---

## Archivos modificados recientemente (claves)

| Archivo | Cambio |
|---------|--------|
| `lib/core/auth/session_controller.dart` | Base por callback (no capturada al construirse) y `verificarPin` en dos pasos: valida el PIN y asocia **este** dispositivo, sin pisar los demás |
| `lib/features/auth/presentation/login_screen.dart` | Autodetección cuando la BD responde; el nombre queda fijo con *Usar otro* |
| `lib/features/activos/data/activos_repository.dart` | `existeCategoria` sin `$2` repetido (el renombrado fallaba con 500) |
| `tool/smoke_sql.py` | Prueba de multi-dispositivo, lint de placeholders arreglado, lints de booleanos y de listeners |
| `tool/server.py` | `_exec_autocommit` delega en `_exec_sql` (devuelve filas); fuera el bloque de verificación post-UPDATE |
| `lib/core/data/pg_client.dart` | `_bindPlan()` renumera placeholders por orden de aparición |
| `lib/features/reportes/data/reportes_repository.dart` | `buscarProducts` sin `$1` repetido |
| `test/pg_client_bind_test.dart` | Regresión del orden de parámetros |

---

## Qué NO tocar (ya funciona)
- Migración de BD (completada)
- Tunnel Cloudflare + Gist (funciona)
- Compilación Linux/Android (en CI)
- Optimizaciones de rendimiento Lotes A/B/C (commiteadas)

---

## Pendiente de infraestructura

- **Flutter no está instalado** en la PC del agente. `pubspec.lock` pide Dart
  >=3.12 / Flutter >=3.44, así que `flutter analyze` y `flutter test` no se
  pueden correr. Los cambios en Dart se revisaron a mano, no compilados.
- `tool/e2e_proxy_test.py` requiere `dart` y `E2E_DATABASE_URL`. Su primer
  caso (un `SELECT` que debe traer filas) **ya detectaba el bug de
  `_exec_autocommit` y llevaba tiempo fallando** sin que nadie lo corriera.

---

## Módulo nuevo: Lycoris Hosteleria (pendiente de aplicar migración)

Se agregó un módulo independiente (`lib/main_hosteleria.dart`) para huéspedes
y reservas. Reutiliza las habitaciones `habitaciones` (misma tabla que usa el POS).

**Falta aplicar la migración en la BD del servidor** antes de usar el módulo:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -f supabase\migrations\20261002000000_hosteleria.sql
```

Crea `hosteleria_huespedes` y `hosteleria_reservas` (con FK a
`habitaciones`). Verificar:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -c "SELECT count(*) FROM hosteleria_huespedes; SELECT count(*) FROM hosteleria_reservas;"
```

El módulo no necesita cambios en `tool/server.py` ni en el túnel: usa el mismo
`PostgresService` que la app de inventario.

### Check-in con datos completos (migración adicional)

Aplicar **después** de las migraciones de Hostelería y de usuarios:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -f supabase\migrations\20261002020000_hosteleria_checkin.sql
```

Crea `pos_tipos_habitacion` (catalogo con `capacidad` de personas) y enlaza
`pos_habitaciones.tipo_id`; agrega al huésped apellido, documento, nacimiento,
estado civil, nacionalidad, profesion, procedencia y destino; crea
`hosteleria_reserva_personas` (titular + acompanantes) y `hosteleria_vehiculos`
(varios por estancia); y agrega `hora_entrada`/`hora_salida` a
`hosteleria_reservas`. (La migracion de estados renombra despues
`pos_tipos_habitacion`→`tipos_habitacion` y `pos_habitaciones`→`habitaciones`.)
Verificar:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -c "SELECT count(*) FROM pos_tipos_habitacion; SELECT count(*) FROM hosteleria_reserva_personas; SELECT count(*) FROM hosteleria_vehiculos;"
```

Flujo: reserva (habitacion no ocupada) o check-in directo, con datos completos
del titular, acompanantes limitados por la capacidad del tipo y vehiculos; el
check-in registra `hora_entrada` y el check-out `hora_salida`.

### Estados de habitacion y modalidad por horas OP (migracion adicional)

Aplicar **al final**, despues de la migracion de check-in (depende de
`tipos_habitacion`):

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -f supabase\migrations\20261002030000_habitaciones_estados_op.sql
```

Renombra `pos_habitaciones`→`habitaciones` y `pos_tipos_habitacion`→
`tipos_habitacion` (conserva ids/FKs); agrega `habitaciones.estado`
(`libre`/`aseo`/`mantenimiento`), `estado_notas` y `estado_actualizado_en`; y
agrega a `hosteleria_reservas` `modalidad` (`noche`/`horas`), `bloque_horas` y
`hora_limite`. Verificar:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -c "SELECT estado, count(*) FROM habitaciones GROUP BY estado; SELECT modalidad, count(*) FROM hosteleria_reservas GROUP BY modalidad;"
```

Flujo: al hacer check-out la habitacion pasa automaticamente a `aseo`; "Marcar
limpia" la devuelve a `libre`; en `mantenimiento` no es vendible. La modalidad
"Operativa OP" (por horas, 3 h por defecto) se elige al reservar/hacer check-in
y guarda `hora_limite` para avisar con cuenta atras.

---

## Usuarios centralizados (pendiente de aplicar migración)

Los 3 módulos (inventario, POS y hostelería) ahora comparten un **directorio
central de usuarios**: `usuarios` + `usuario_modulos` + `usuario_dispositivos`.
Se unificaron `pos_usuarios` (PIN sha256) y `dispositivo_usuario` (PIN texto
plano del inventario, que queda obsoleta).

**Falta aplicar la migración en la BD del servidor** (después de la de
Hostelería):

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -f supabase\migrations\20261002010000_usuarios_centrales.sql
```

Renombra `pos_usuarios` -> `usuarios` (conserva ids, las FK de
`pos_sesiones`/`pos_cierres`/`pos_ventas` siguen válidas), agrega `nivel`
(`basico`/`admin`/`desarrollador`), crea las tablas nuevas y migra los
operadores de inventario con su PIN a sha256. Verificar:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas ^
  -c "SELECT u.id, u.nombre, u.nivel, array_agg(m.modulo) FROM usuarios u LEFT JOIN usuario_modulos m ON m.usuario_id = u.id GROUP BY u.id ORDER BY u.id;"
```

Login por módulo:
- POS: grid + PIN, abre turno/caja (sin cambios de flujo).
- Inventario: auto-login por `usuario_dispositivos`; mantiene el alta inicial.
- Hostelería: grid + PIN, **sin** turno/caja.

La administración de usuarios (asignar módulos/roles desde la app) queda
pendiente para una segunda pasada; por ahora se gestiona vía BD/POS.

---

## Contacto
Si algo no está claro, revisa `graphify-out/` o pregunta al usuario.
