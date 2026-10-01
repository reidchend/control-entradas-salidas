# Servidores, túneles y arquitectura de conexión

Este documento explica cómo se manejan los servidores (PostgreSQL, proxy SQL,
bot de WhatsApp y túnel Cloudflare) en este proyecto. Sirve como referencia
operativa para entender qué corre dónde, cómo se conectan la app y el bot, y
cómo diagnosticar problemas.

---

## 1. Arquitectura general

La app móvil/desktop se conecta a PostgreSQL **por dos caminos**, elegibles en
Ajustes → Base de datos:

| Camino | Clase | Uso | Red | Ventajas | Limitaciones |
|---|---|---|---|---|---|
| **HTTP (proxy)** | `HttpSqlSession` | Windows, Android | Sale por HTTPS al túnel (Cloudflare) → `tool/server.py` → PostgreSQL (localhost:5432) | No requiere abrir 5432 ni VPN (funciona detrás de CGNAT). La app no conoce la IP interna. | Un salto HTTP extra (latencia pequeña). Requiere `PROXY_SQL_TOKEN`. |
| **TCP directo** | `NativeSqlSession` | Linux/desktop interno o con red privada | Conexión directa TCP a PostgreSQL:5432 | Más rápido, sin proxy intermedio | Requiere que el cliente alcance 5432 (túnel/VPN o LAN). |

La elección se guarda en `DbConfig`. En web siempre usa el proxy (no hay donde
guardar secretos).

**Punto clave:** El túnel no habla directamente con PostgreSQL, habla con
`tool/server.py` (puerto 8123 por defecto).

### 1.1. Qué significa "conectada" en la app

`postgresPoolProvider` solo **construye** el objeto de sesión. Ni
`Pool.withUrl` ni `HttpSqlSession` abren una conexión al construirse, así que
una app con la base apagada se reportaba como conectada y el fallo aparecía
recién en la primera query, como un error técnico sin contexto.

Por eso hay un provider aparte, `sesionVerificadaProvider`, que hace un
`SELECT 1` con un timeout de 8 s. `estadoBdProvider` lo lee, y así:

| Estado | Significa |
|---|---|
| `conectando` | Se está abriendo o comprobando |
| `lista` | El servidor **respondió** |
| `error` | Configurado, pero el servidor no contesta (`DbNoDisponibleError`) |
| `noConfigurada` | Falta completar la configuración (`DbNotConfiguredError`) |

El login corta a la pantalla de conexión también en `error`, no solo en
`noConfigurada`: antes se dejaba escribir el PIN y el fallo salía al enviarlo.
El botón "Reintentar" invalida el pool, lo que arrastra al provider verificado
(refresca URL, sesión y chequeo).

Va deliberadamente **fuera** de `initializePostgres`: los repositorios no deben
esperar al chequeo para trabajar, y meterlo en la construcción rompe el seam que
los tests usan para apuntar a un proxy local.

---

## 2. Proxy SQL (`tool/server.py`)

Es un servidor HTTP minimalista en Python que:

1. Recibe `POST /proxy-sql` con JSON `{action, sql, params, txid}`
2. Verifica el token en `X-Proxy-Token` (debe coincidir con `PROXY_SQL_TOKEN` en `.env.local`)
3. Traduce placeholders `$1..$N` (driver `package:postgres` de Dart) a `%s` (psycopg3)
4. Ejecuta contra PostgreSQL usando `psycopg` / `psycopg_pool`
5. Serializa filas y devuelve `{rows, affectedRows}` (JSON)

Detalles relevantes:

- **Puerto por defecto:** `8123` (`PORT = int(sys.argv[1]) if len(sys.argv)>1 else 8123`)
- **Auth:** si falta token o es incorrecto → `401`. El cuerpo siempre es JSON.
- **Transacciones:** `action: begin/commit/rollback` gestionan `txid` en memoria (expiran por inactividad). `execute` fuera de tx usa conexión directa con `autocommit=True`.
- **Placeholders:** `convert_placeholders()` convierte *cada aparición* de `$n` a `%s`. Por eso **un `$n` repetido** produce más `%s` que parámetros y psycopg falla con `the query has N placeholders but M parameters were passed`. Ese caso debe evitarse en SQL crudo.
- **Serialización:** fechas/decimales/UUIDs → JSON-compatible (ISO strings, números o valores nativos según el caso).
- **Logs:** cuando recibe `POST /log` (web) imprime líneas en la consola del servidor (`[HH:MM:SS] ...`).

**Variables de entorno necesarias (para correrlo):**

```env
DATABASE_URL_UNPOOLED=postgresql://usuario:pass@localhost:5432/base?sslmode=disable
DATABASE_URL=postgresql://usuario:pass@localhost:5432/base?sslmode=disable
PROXY_SQL_TOKEN=token-compartido-entre-app-y-proxy
```

Normalmente se leen de `.env.local` (precedencia: `DATABASE_URL_UNPOOLED` antes que `DATABASE_URL`).

**Arranque (PC servidor):**

```cmd
cd C:\Lycoris
tool\venv\Scripts\python.exe tool\server.py 8123
```

O con `iniciar_api.bat` (según lo que haya configurado en el equipo servidor).

**Diagnóstico rápido:**

```cmd
# Ver puerto escuchando
netstat -ano | findstr ":8123"

# Smoke test end-to-end (sin Flutter)
tool\venv\Scripts\python.exe tool\smoke_sql.py
```

`smoke_sql.py` prueba conectividad, token, orden de parámetros en UPDATE,
placeholder repetido y el lint de SQL crudo en `lib/`.

---

## 3. Túnel Cloudflare (acceso remoto)

La app fuera de LAN (Windows/Android instaladas fuera de la red donde corre el
servidor) usa **Cloudflare Tunnel** para llegar al proxy HTTP sin abrir puertos.

Flujo:

```
App (HTTPS) → cloudflared (túnel) → tool/server.py (http://localhost:8123)
```

El punto de entrada del túnel publica una URL HTTPS (p.ej.
`https://...trycloudflare.com` o un dominio propio). Esa URL se descubre en la
app por **Gist** (ver siguiente sección), para que un túnel que cambie de URL no
deje la app colgada con un endpoint viejo.

**Procesos típicos en PC servidor:**

```cmd
cloudflared.exe tunnel --url http://localhost:8123
```

El comando anterior imprime una URL pública (si usa `trycloudflare.com`). Esa URL
se guarda en el Gist (manual o automatizado según el setup del servidor).

**Importante:** El túnel **no** necesita PostgreSQL abierto. Solo necesita que
`tool/server.py` esté escuchando en `8123`.

---

## 4. Descubrimiento de URL del proxy (Gist)

Para evitar hardcodear la URL del túnel, la app consulta un **Gist JSON** con la
URL pública actual.

Mismo Gist para los dos túneles, pero archivo y endpoint distintos:

| Consumidor | Archivo en el Gist | Cómo lo lee |
|---|---|---|
| Proxy SQL (BD) | `api_url.json` | `GET https://api.github.com/gists/<GIST_ID>` (API, no `raw`) |
| Bot de WhatsApp | `bot_url.json` | `GET https://gist.githubusercontent.com/<owner>/<id>/raw/bot_url.json` |

El `GIST_ID` del proxy sale de `--dart-define=GIST_ID=...` al compilar; si el
Gist es privado, `GIST_TOKEN` manda la cabecera de solo lectura.

Estructura de `api_url.json` (mínima):

```json
{
  "url": "https://abcd-efgh-1234.trycloudflare.com/",
  "actualizado": "2026-09-29T21:06:36.032Z",
  "puerto": 8501,
  "rapido": true
}
```

Solo importa `url`, y tiene que empezar con `https://`: por HTTP plano la
conexión no viaja cifrada y Android 9+ la bloquea. Si el Gist publica algo que
no es una URL válida, la app lo avisa en vez de reintentar, porque eso sí
necesita que alguien lo arregle.

La respuesta se guarda en `SharedPreferences` (`api_url_cache` y
`api_url_cache_ts`) y se vuelve a usar durante **10 minutos**
(`_validezCache`). Además, **cada arranque fuerza la consulta**
(`forzarProxy: true` en `postgresPoolProvider`): abrir la app ya toma la URL
vigente sin tocar nada. Si el Gist no contesta se cae a esa caché y, en último
caso, a la URL guardada en la configuración, así que forzar nunca deja a la app
sin conexión por culpa de esa consulta.

Antes, con una vigencia de 12 horas y sin forzar en el arranque, la app se
quedaba apuntando a un túnel muerto y el usuario tenía que entrar a
Configuración → Base de datos y guardar la configuración a mano para
despertarla.

**Ubicación en código:** `lib/core/network/descubrimiento_servidor.dart`

---

## 5. Bot de WhatsApp (`whatsapp_bot/`)

El bot envía mensajes, reportes y documentos por WhatsApp. Funciona por separado
del proxy SQL.

### Componentes

- `whatsapp_bot/server.js`: **entrypoint** (`npm start` corre esto). Es el
  servidor Express que recibe los pedidos de envío, y monta además el panel web
  del bot. Escucha en `process.env.PORT` o **3000**.
- `whatsapp_bot/bot.js`: la lógica de WhatsApp (Baileys). `server.js` la importa.
  Acá viven el envío, la reintentar de cola y la lectura de `config.json`.
- `whatsapp_bot/panel_bot.html`: el panel que se sirve en `/panel` y `/qr`.
- `whatsapp_bot/config.json`: solo `groupId` y `reportGroupId`. **No contiene
  secretos** (el token va por header). Sí se versiona.
- `whatsapp_bot/start_bot.bat` / `iniciar_bot.bat`: arranque en Windows.
- `auth/`: sesión autenticada de WhatsApp Web, creada al pasar el QR. Es lo que
  evita tener que escanear el QR de nuevo. **No commitear** (ya está en
  `.gitignore`): subirla filtra la sesión de la cuenta.
- `node_modules/`: dependencias. **No commitear**.
- `cloudflared.exe`: binario del túnel del bot. **No commitear**.

Endpoints que expone `server.js`:

| Método | Ruta | Qué hace |
|---|---|---|
| GET | `/` | Estado del bot |
| GET | `/panel`, `/qr` | Panel web y QR de vinculación |
| GET | `/config` | Lee la config (la app la consulta al arrancar) |
| GET | `/groups` | Grupos disponibles |
| POST | `/send` | Mensaje de texto |
| POST | `/send-image` | Imagen |
| POST | `/send-document` | Documento |
| POST | `/send-report` | Reporte al grupo de reportes |
| POST | `/send-to` | Envío a un destino explícito |
| POST | `/set-group`, `/set-report-group` | Fija los grupos |

### Autenticación entre app y bot

El bot valida `x-auth-token` (header, o `?token=` en la query). El valor sale de
`process.env.WHATSAPP_BOT_TOKEN` en el bot, y en la app se inyecta al compilar
con `--dart-define=WHATSAPP_BOT_TOKEN=<token>`. Si no coinciden, responde 401.
Nunca va hardcodeado en el repo.

### Descubrimiento de URL del bot

La app lee la URL del bot del Gist, pero por un camino distinto al del proxy:
`WhatsappRepository` pega directo al `raw` de `bot_url.json`
(`gist.githubusercontent.com/<owner>/<id>/raw/bot_url.json`), sin pasar por la API
de GitHub ni por `SharedPreferences`.

### Flujo de envío

1. App (Inventario/POS) llama a `WhatsappRepository.enviarMensajeTexto()` / `_enviarReporte()` / `_enviarImagenDirecto()`
2. Construye JSON y hace `POST <bot_url>/send` (o `/send-image`, `/send-report`) con header `x-auth-token`
3. Bot recibe, valida el token, envía por WhatsApp (Baileys) y responde `{ok, ...}`
4. Si falla, el repositorio devuelve `false` y **no loguea a stdout**: usa `debugPrint`, que no aparece en release. Los reintentos corren con `_retryTimer` (1 min).

### Arranque (PC servidor)

```cmd
cd C:\Lycoris\whatsapp_bot
node server.js
```

O `start_bot.bat`, que además hace `npm install`, carga `.env` y levanta el
túnel en un paso.

El túnel del bot:

```cmd
start_tunnel.js
```

Ese script levanta `cloudflared` y publica la URL resultante en el Gist
(`bot_url.json`), que es lo que la app lee. El proxy SQL tiene su propio
equivalente, `tool/iniciar_tunnel_api.js`, que publica `api_url.json`.

---

## 6. PostgreSQL

- **Instancia local:** `postgresql-x64-18` en Windows, escucha `localhost:5432`
- **Base:** `control_entradas` (nombre por defecto)
- **Credenciales:** en `.env.local` (`DATABASE_URL_UNPOOLED`)
- **Conexión desde proxy:** directa localhost (sin SSL en red local). `sslmode=disable`
- **Pool:** `psycopg_pool.ConnectionPool` (para transacciones con `txid`) y conexiones directas para autocommit

**Servicio Windows:**

```powershell
Get-Service postgresql-x64-18
```

Debe estar `Running`.

---

## 7. Variables de entorno y configuración

### `.env.local` (PC servidor)

```env
DATABASE_URL_UNPOOLED=postgresql://postgres:PASS@localhost:5432/control_entradas?sslmode=disable
DATABASE_URL=postgresql://postgres:PASS@localhost:5432/control_entradas?sslmode=disable
PROXY_SQL_TOKEN=token-largo-y-compartido
```

### Build de Flutter (defines)

La app recibe defines al compilar (CI o local):

| Define | Uso |
|---|---|
| `PROXY_SQL_TOKEN` | Token para `HttpSqlSession` (obligatorio en web; también usado en builds con proxy) |
| `WHATSAPP_BOT_TOKEN` | Token para hablar con el bot de WhatsApp |
| `GIST_ID` | (opcional) ID del Gist para descubrimiento de URL |
| `APP_ID`, `APP_LABEL` | Branding por app (POS vs Inventario) |

En el workflow de GitHub se inyectan desde `secrets.*`.

---

## 8. Puertos y procesos (resumen)

| Servicio | Puerto | Proceso | Notas |
|---|---|---|---|
| PostgreSQL | 5432 | `postgres.exe` | Local, sólo localhost (ideal) |
| Proxy SQL (`server.py`) | 8123 | `python.exe` | Punto de entrada del túnel |
| Bot WhatsApp | 3000 (`$PORT`) | `node.exe` | `server.js`; REST para envíos y panel web |
| Cloudflared | dinámico (salida HTTPS) | `cloudflared.exe` | Reenvía al proxy/bot |

**Checklist de arranque típico (PC servidor):**

1. PostgreSQL corriendo (5432)
2. `tool/server.py` corriendo (8123) → lee `.env.local`
3. (Opcional) Bot WhatsApp corriendo
4. `cloudflared` túnel apuntando a 8123 → actualiza Gist con URL pública
5. App consulta Gist, obtiene URL, habla por HTTPS con proxy, proxy habla con PostgreSQL

---

## 9. Diagnóstico y verificaciones

### Proxy SQL

```cmd
# Puerto
netstat -ano | findstr ":8123"

# Smoke test completo (end-to-end)
cd C:\Lycoris
tool\venv\Scripts\python.exe tool\smoke_sql.py
```

Debe pasar: conectividad, rechazo de token, orden de parámetros, placeholder
repetido, lint de SQL crudo.

### Base de datos

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas -c "SELECT 1;"
```

### Bot WhatsApp

Probar `POST /send` con `x-auth-token` correcto. Si el QR no aparece, revisar `auth/` (sesión).

### Túnel

Si la app no logra conectar por proxy: verificar que `cloudflared` sigue corriendo y que el Gist tiene la URL correcta (la URL de `trycloudflare.com` cambia al reiniciar el túnel).

---

## 10. Notas importantes

- **No commitear secretos.** `.env.local`, tokens, `auth/` de WhatsApp, `cloudflared.exe`, `node_modules/`, dumps (`neon.dump`), etc., deben quedar fuera de git.
- **Placeholder repetido:** Prohibido en SQL crudo (`executeSql`). Usar números distintos (`$1`, `$2`) aunque el valor sea el mismo. El builder (`PgClient`) ya renumera por orden de aparición.
- **Orden de parámetros:** Corregido en `PgClient._bindPlan()` (renumera por orden textual). Esto evita el cruce entre SET y WHERE en `UPDATE`.
- **SELECT fuera de transacción:** El proxy devuelve filas correctamente (corregido `_exec_autocommit()`).
- **Logs de debug:** Se eliminaron de `lib/`. `LogBridge` está a medio construir (no envía a `/log` aún).