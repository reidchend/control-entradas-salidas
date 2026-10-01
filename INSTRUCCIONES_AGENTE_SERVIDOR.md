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

### Pendiente: `UNIQUE` de `device_id`

La migración `20250102000000_add_device_id.sql` declara
`device_id TEXT UNIQUE`, pero en la base **solo existe el PRIMARY KEY**.
Hay 5 filas con el mismo `device_id` (`ids 4, 16, 17, 18, 19`).

No se aplicó el índice a propósito: `SessionController.verificarPin`
reescribe el `device_id` del operador al que inicia sesión, así que con el
`UNIQUE` puesto el login fallaría con `23505` en cuanto el dispositivo destino
ya exista. Hay que deduplicar y hacer ese update tolerante al conflicto.

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
`UPDATE`, el caso del placeholder repetido, `buscarProductos`, que no queden
tablas de prueba, y un lint que recorre `lib/` avisando si algún SQL crudo
repite un `$n`.

Sale con código 1 si algo falla.

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
- Esperar ~300ms después de terminar de escribir el nombre (debounce)
- Verificar que cambie a modo "Login" (botón "Desbloquear")

### 5. Verificar en BD
```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas -c "SELECT id, factura_id FROM movimientos WHERE tipo='entrada' ORDER BY id DESC LIMIT 5;"
```

---

## Archivos modificados recientemente (claves)

| Archivo | Cambio |
|---------|--------|
| `tool/server.py` | `_exec_autocommit` delega en `_exec_sql` (devuelve filas); fuera el bloque de verificación post-UPDATE |
| `lib/core/data/pg_client.dart` | `_bindPlan()` renumera placeholders por orden de aparición |
| `lib/features/reportes/data/reportes_repository.dart` | `buscarProducts` sin `$1` repetido |
| `test/pg_client_bind_test.dart` | Regresión del orden de parámetros |
| `tool/smoke_sql.py` | Smoke test end-to-end + lint de placeholders |

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

## Contacto
Si algo no está claro, revisa `graphify-out/` o pregunta al usuario.
