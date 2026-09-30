# Montar la PC servidor, paso a paso

Guía para levantar en una PC Windows 10 la máquina que va a hostear
**PostgreSQL**, la **web de inventario (8501)**, el **POS (8502)** y el **bot
de WhatsApp (3000)**.

Tiempos estimados: unas 2 horas la primera vez, casi todo instalación.

> Resumen de la arquitectura y el porqué está en
> [`migracion-bd-local.md`](migracion-bd-local.md).

---

## Antes de empezar

Tenés que tener a mano:

- [ ] La **contraseña del superusuario `postgres`**. La definís vos en el
      paso 0.1, no hace falta tenerla de antemano.
- [ ] Acceso a la **cuenta de Tailscale** (Google, Microsoft o GitHub).
- [ ] La carpeta **`whatsapp_bot/auth/`** de la PC donde corre el bot hoy.
      Sin esto hay que escanear un QR de WhatsApp de nuevo.
- [ ] El **`.env` del bot** con `GITHUB_TOKEN`.
- [ ] Decidir una **carpeta para el repo**, sin espacios ni acentos. Te
      sugiero `C:\Lycoris`. Es importante: algunos scripts asumen rutas
      limpias.

---

## Fase 0 — Instalaciones

### 0.1 PostgreSQL 18

Es la base de datos. Se instala como servicio de Windows, así que ya queda
arrancando solo con la máquina.

1. Descargá el instalador de <https://www.postgresql.org/download/windows/>.
   Buscá la versión **18** (o la más reciente disponible).
2. Instalalo con los valores por defecto, que ya son los que necesitamos:
   - Puerto: `5432`
   - Desmarcá **Stack Builder** al final (no lo vamos a usar).
3. **Anotá la contraseña que le pongas al usuario `postgres`.** Es la que
   te va a pedir el script del paso 2.1. Si la perdés, hay que reinstalar.

Verificación (PowerShell normal):

```powershell
Get-Service postgresql-x64-18
```

Deber decir `Running`.

### 0.2 Tailscale

Es la red privada que une la PC servidor con los celulares y las notebooks.
Sin esto las apps no llegan a la base.

1. Descargá de <https://tailscale.com/download/windows> e instalá.
2. Logueate con tu cuenta. Instalalo en el **celular** también, con la
   **misma cuenta**.
3. Verificá la IP que le asignó:

```powershell
tailscale ip -4
```

Anotá ese número (arranca con `100.`). Es el que después va en la app.

4. En el cliente de Tailscale, activá **"Always-on"** o "unattended mode"
   para la PC. Si no, cuando la machine se apaga y prende sin que alguien
   inicie sesión, Tailscale puede no conectar solo y la base queda
   inalcanzable.

### 0.3 Python 3

Lo necesita `tool/server.py`.

1. De <https://www.python.org/downloads/>.
2. **Importante:** en el primer paso del instalador tildá
   **"Add python.exe to PATH"**. Si lo saltás, los scripts no encuentran
   Python.

Verificación:

```powershell
python --version
```

### 0.4 Node.js

Solo lo necesita el bot de WhatsApp. Versión LTS.

1. De <https://nodejs.org/>.

```powershell
node --version
```

### 0.5 Git

Para traer el código.

1. De <https://git-scm.com/download/win>. Default está bien.

---

## Fase 1 — Traer el código

### 1.1 Clonar

```powershell
cd C:\
git clone https://github.com/reidchend/control-entradas-salidas.git Lycoris
cd Lycoris
git log -1 --oneline
```

Tiene que decir algo sobre la configuración de la base de datos. Si no,
`git pull`.

> Si preferís no usar Git, podés copiar la carpeta a mano. Pero entonces
> perdés la capacidad de actualizar con `git pull`, y la vas a necesitar.

---

## Fase 2 — La base de datos

### 2.1 Rol, base y apertura de puertos

PowerShell **como Administrador** (clic derecho → "Ejecutar como
administrador"), desde `C:\Lycoris`:

```powershell
cd C:\Lycoris
powershell -ExecutionPolicy Bypass -File tool\windows\configurar_postgres.ps1
```

Te va a pedir la contraseña de `postgres` (la del instalador, paso 0.1),
enmascarada. Elegí para `control_app` una contraseña **fuerte y distinta**:
esta es la que va a usar la app.

Qué hace el script:

- `listen_addresses = '*'`: acepta conexiones de red.
- Una regla en `pg_hba.conf` que acepta **solo** desde `100.64.0.0/10`.
- Una regla de **firewall** para el 5432, también solo desde Tailscale.
- Crea el rol `control_app` y la base `control_entradas`.

Al final imprime un resumen con las líneas que escribió. Mirá que la regla
diga `100.64.0.0/10` y **no** `0.0.0.0/0`.

### 2.2 Abrir los puertos de la app web

También PowerShell **como Administrador**:

```powershell
powershell -ExecutionPolicy Bypass -File tool\windows\configurar_firewall.ps1
```

Abre 8501 y 8502 restringidos a Tailscale.

> **Por qué está restringido y no abierto a la red local.** `tool/server.py`
> expone `/proxy-sql`, que ejecuta SQL arbitrario con las credenciales del
> servidor y **no pide ninguna autenticación**. Si el puerto queda abierto a
> la LAN, cualquiera con un navegador en tu red puede mandar un
> `DROP TABLE productos` sin tener ninguna clave. Con Tailscale solo
> corren los equipos que vos controlás.
>
> **Si necesitás usar el POS desde un navegador de la red local**, decime y
> lo resolvemos agregando un token compartido al proxy antes de abrir el
> puerto sin resolver antes la autenticacion.

### 2.3 Crear las tablas y el entorno de Python

PowerShell normal (no hace falta admin), desde `C:\Lycoris`:

```powershell
cd C:\Lycoris\tool\windows
.\crear_estructura.bat
```

Esto:

1. Crea el virtualenv `tool\venv` e instala `psycopg`.
2. Copia `.env.local.example` a `.env.local`.
3. Te pide la contraseña de `postgres` y aplica `supabase/schema.sql` y
   `supabase/schema_activos.sql`.

Debe terminar con `Estructura creada OK. N tablas en public.` y una lista
sin las tablas faltantes.

### 2.4 Apuntar el proxy a la base local

Editá `C:\Lycoris\.env.local` y reemplazá `CAMBIAR_ESTA_CONTRASENA` por la
que usaste en el paso 2.1:

```
DATABASE_URL_UNPOOLED=postgresql://control_app:TU_CONTRASENA@localhost:5432/control_entradas?sslmode=disable
DATABASE_URL=postgresql://control_app:TU_CONTRASENA@localhost:5432/control_entradas?sslmode=disable
```

`sslmode=disable` porque el tráfico ya va cifrado por Tailscale. La base
local no tiene TLS configurado; si ponés `require`, no conecta.

---

## Fase 3 — La web (inventario y POS)

Acá hay una decisión: **compilar en la PC servidor o en tu máquina de
trabajo**.

### Recomendación: compilar en la máquina de trabajo

La PC servidor no necesita Flutter instalado (son ~2 GB). Compilás en la
máquina de desarrollo y copiás la carpeta.

En la máquina de desarrollo (Linux), desde el repo:

```bash
# El token del bot WhatsApp se inyecta en compilación; tiene que ser el MISMO
# valor que quedó en whatsapp_bot\.env (ver sección 5.5 y .env.example).
flutter build web --release -o build/web \
    --dart-define=WHATSAPP_BOT_TOKEN=<TOKEN>

flutter build web --release -t lib/main_pos.dart -o build/pos \
    --dart-define=WHATSAPP_BOT_TOKEN=<TOKEN>
cp web_pos/favicon.png web_pos/manifest.json build/pos/
cp -r web_pos/icons build/pos/
cp web_pos/index.html build/pos/index.html
```

Después copiá `build/web` y `build/pos` a `C:\Lycoris\build\` en la PC
servidor.

> Los pasos con `cp` son para Linux/macOS. En Windows PowerShell serían
> `Copy-Item`. Si preferís compilar en la PC servidor, instalá Flutter y
> usá `xcopy /E /I build\pos\icons build\pos\icons` en lugar de `cp -r`.

### 3.1 Verificar que los builds están

En la PC servidor:

```powershell
dir C:\Lycoris\build\web\index.html
dir C:\Lycoris\build\pos\index.html
```

Si alguno no está, el server levanta igual pero muestra 404 en todo: no
confíes en "el puerto responde", verificá el archivo.

---

## Fase 4 — El bot de WhatsApp

### 4.1 Copiar lo que no está en el repo

De la PC donde corre el bot hoy, a `C:\Lycoris\whatsapp_bot\`:

| Qué | Por qué |
|---|---|
| `auth\` (carpeta completa) | Sesión de WhatsApp. **Sin esto, QR de nuevo.** |
| `.env` | `GITHUB_TOKEN` que publica la URL del túnel en el Gist |
| `cloudflared.exe` | El binario del túnel; no está en el repo |
| `config.json` | El `groupId` del grupo de destino |

Para `cloudflared.exe`: <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/>

### 4.2 Instalar dependencias y arrancar

```powershell
cd C:\Lycoris\whatsapp_bot
npm install --production
.\iniciar_bot.bat
```

Tiene que imprimir algo como:

```
[bot] Red disponible.
[bot] Iniciando servidor en el puerto 3000...
[bot] Iniciando tunel...
[TUNNEL] URL detected: https://algo.trycloudflare.com
[GIST] URL updated: https://algo.trycloudflare.com
```

Si dice `habra que escanear un QR`, no tenés la carpeta `auth` bien puesta.

### 4.3 Verificar el Gist

Como la URL del túnel **cambia en cada reinicio**, confirmá que se publicó:

<https://gist.githubusercontent.com/reidchend/5b37693a243d8d2235eea0647396b8d3/raw/bot_url.json>

Tiene que devolver `{"url":"https://...trycloudflare.com"}`. Si devuelve la
URL vieja, el `GITHUB_TOKEN` no tiene permiso de escritura sobre el Gist.

---

## Fase 5 — Probar todo junto

### 5.1 Levantar la stack

```powershell
cd C:\Lycoris\tool\windows
.\iniciar_todo.bat
```

Imprime la IP de Tailscale y después el estado de los dos servidores:

```
  8501 (inventario): HTTP 200
  8502 (POS):        HTTP 200
```

Si un puerto no da 200, mirá el error que imprime arriba.

### 5.2 Probar la web

Desde cualquier equipo con Tailscale, en el navegador:

- `http://<IP-TAILSCALE>:8501` → inventario
- `http://<IP-TAILSCALE>:8502` → POS

Van a mostrar las pantallas pero **sin datos**, porque la base está vacía.
Es normal en esta fase.

### 5.3 Probar la app nativa contra la base

Hay dos modos, y el panel deja cambiar entre ellos en cualquier momento.

**Proxy HTTPS (recomendado)**

La app no habla con PostgreSQL: le pregunta al servidor, que le responde. No
necesita Tailscale en el equipo, ni abrir el 5432.

1. Generar un token y ponerlo en `.env.local` de la PC servidor:

   ```powershell
   cd C:\Lycoris
   python -c "import secrets; print(secrets.token_urlsafe(32))"
   ```

   Copiar el valor y agregarlo a `.env.local`:

   ```
   PROXY_SQL_TOKEN=EL_VALOR_QUE_COPIASTE
   ```

   Después reiniciar `tool\server.py` para que lo tome.

2. En la app: **Ajustes → Base de datos → Proxy HTTPS**.
   - URL del servidor: `https://api.tudominio.cl` (sin `/proxy-sql`, se
     agrega sola).
   - Token del proxy: el mismo valor de arriba.
3. **Probar conexión** → tiene que decir "Conexión correcta".
4. **Guardar**, y reiniciar la app.

**TCP directo**

Solo si el equipo ya llega al 5432 por Tailscale o red local.

1. Abrí la app → **Ajustes → Base de datos → TCP directo**.
2. Host: la IP de Tailscale de la PC servidor. Puerto: `5432`.
   Base: `control_entradas`. Usuario: `control_app`.
   Contraseña: la del paso 2.1.
3. **Probar conexión** → tiene que decir "Conexión correcta".
4. **Guardar**.

Si falla con `connection refused`: casi siempre es que falta la regla de
firewall (paso 2.1) o que Tailscale no está conectado.

### 5.4 Exponer el proxy con Cloudflare Tunnel

Solo hace falta si los equipos que usan la app **no** están en la red de
Tailscale. Si todos los clientes tienen Tailscale, usar el modo TCP directo y
saltar esta sección.

Instalar `cloudflared`:

```powershell
winget install --id Cloudflare.cloudflared
```

### Túnel rápido (predeterminado)

Es lo que usa el proyecto, porque no necesita cuenta de Cloudflare ni dominio
propio. La URL cambia en cada reinicio, y eso no rompe las apps: la toman del
Gist (sección 5.5).

```powershell
cd C:\Lycoris
tool\iniciar_api.bat
```

Un `.bat` levanta el servidor en 8501, espera a que responda, levanta el túnel
y publica la URL. Si `cloudflared` se cae, el launcher lo vuelve a levantar
solo y republica la URL nueva. (El cuidador del túnel es
`tool\iniciar_tunnel_api.js`, que el `.bat` invoca al final.)

Conviene tenerlo como tarea de arranque, así sigue arriba solo:

```powershell
.\registrar_autostart.ps1
```

### Túnel con nombre (si tenés un dominio en Cloudflare)

La URL queda fija, que es lo más cómodo a largo plazo, pero Cloudflare pide un
dominio propio administered desde una cuenta de Cloudflare. Se configura una
sola vez:

```powershell
cloudflared tunnel login
cloudflared tunnel create control-entradas
cloudflared tunnel route dns control-entradas api.tudominio.cl
```

Después se levanta con `tool\iniciar_api.bat --con-nombre`.

Y en `C:\Users\<TU_USUARIO>\.cloudflared\config.yml`:

```yaml
tunnel: control-entradas
credentials-file: C:\Users\<TU_USUARIO>\.cloudflared\<ID_DEL_TUNEL>.json

ingress:
  - hostname: api.tudominio.cl
    service: http://localhost:8501
  - service: http_status:404
```

Comprobar que el proxy exige el token **desde internet**:

```powershell
# Sin token: tiene que responder 401
curl.exe -X POST https://api.tudominio.cl/proxy-sql -d '{\"action\":\"execute\",\"sql\":\"SELECT 1\"}'

# Con token: tiene que responder con filas
curl.exe -X POST https://api.tudominio.cl/proxy-sql -H "X-Proxy-Token: EL_TOKEN" -d '{\"action\":\"execute\",\"sql\":\"SELECT 1\"}'
```

Si el primero devuelve filas, el proxy está abierto: hay que borrar el
túnel, definir `PROXY_SQL_TOKEN` y volver a levantarlo.

### 5.5 Publicar la URL para que las apps la encuentren solos

Para que en cada equipo haya que escribir **solo el token**, la URL del túnel
se publica en el Gist y la app la lee al arrancar. Si después el túnel cambia
de URL, alcanza con republicarla: no hay que ir equipo por equipo.

Necesita un token de GitHub con permiso de escritura sobre el Gist. Sirve
cualquiera de los dos:

- **Classic** con el scope `gist`.
- **Fine-grained** con el permiso de cuenta "Gists" en **write**.

Si no lo tenés o venció, generalo en <https://github.com/settings/tokens> y
guardalo en `whatsapp_bot\.env`:

```
GITHUB_TOKEN=ghp_...
```

El repo trae `whatsapp_bot\.env.example` como plantilla: copiala a
`whatsapp_bot\.env` y completá el token. La plantilla también documenta la
`GEMINI_API_KEY` del bot, comentada.

Ese archivo es el mismo que usa el bot, y `tool\iniciar_api.bat` lo lee de
ahí, así que no hay que exportar la variable en cada arranque. Si el token
está vencido o mal copiado, el `.bat` avisa antes de arrancar y el launcher
explica el error 401 en vez de dejar la URL sin publicar.

Cada vez que arranca, el túnel publica en `api_url.json`:

```json
{"url":"https://algo.trycloudflare.com","actualizado":"2026-09-29T21:06:36.032Z","puerto":8501,"rapido":true}
```

Ese archivo **no contiene el token**, solo la dirección. El Gist es secreto (no
listado), pero la app lo lee **sin autenticación** porque solo necesita el
`GIST_ID`; la dirección del túnel no es un secreto, el token sí.

En la app, el paso 5.3 queda así:

1. **Ajustes → Base de datos → Proxy HTTPS**.
2. La **URL aparece sola** y el campo queda bloqueado. No hay que escribirla.
3. **Token del proxy**: el valor de `PROXY_SQL_TOKEN`. Es el único campo que
   se completa a mano.
4. **Probar conexión** → "Conexión correcta".
5. **Guardar**.

Eso es todo lo que se hace en cada equipo, y alcanza aunque la PC servidor se
reinicie: la app vuelve a leer el Gist en cada arranque, así que toma la URL
vigente sin que nadie tenga que corregirla. La URL que se usó la última vez
queda como respaldo para abrir la app sin internet.

Si el Gist no responde, el campo URL se desbloquea solo y avisa qué revisar.
Ahí se puede escribir la URL a mano, y esa elección queda guardada como fija
—no se pisa con la del Gist— hasta que se vuelva al modo automático con
**Usar la URL automática**.

Para verificar el Gist sin abrir la app:

```powershell
cd C:\Lycoris\tool
node diagnostico_gist.js
```

Si el Gist no responde pero la app ya conocía una URL de antes, usa esa y no
molesta: no se queda sin conexión por un problema puntual de GitHub.

### 5.6 Probar con datos sintéticos

Creá un producto, vendelo en el POS, cerrá la caja. Después verificá que
quedó en la base:

```powershell
$env:PGPASSWORD="TU_CONTRASENA_DE_POSTGRES"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U control_app -d control_entradas -h localhost -c "SELECT * FROM productos;"
```

---

## Fase 6 — Arranque automático

Recién acá, con todo probado a mano.

PowerShell **como Administrador**:

```powershell
cd C:\Lycoris
powershell -ExecutionPolicy Bypass -File tool\windows\registrar_autostart.ps1
```

Registra tres tareas: `LycorisServidor8501`, `LycorisServidor8502` y
`LycorisBotWhatsapp` (esta última solo si ya están `auth\` y `.env`).

### 6.1 Reiniciar y verificar

Reiniciá la PC. Después de un minuto:

```powershell
# ¿Levantaron los servicios?
curl.exe -o nul -w "8501: %{http_code}`n" http://localhost:8501/
curl.exe -o nul -w "8502: %{http_code}`n" http://localhost:8502/
curl.exe -o nul -w "3000: %{http_code}`n" http://localhost:3000/

# ¿Está Tailscale arriba?
tailscale status
```

Si algo no levantó, el detalle está en los logs:

```powershell
type C:\Lycoris\tool\logs\server8501.log
type C:\Lycoris\tool\logs\server8502.log
type C:\Lycoris\tool\logs\bot.log
```

---

## Fase 7 — El dump de Neon

**Recién acá.** La cuota de compute se renueva el 30 de septiembre; hasta
entonces `pg_dump` falla por conexión.

Sobre la máquina de desarrollo (donde está el cliente `psql`):

```bash
pg_dump --no-owner --no-privileges --format=custom \
  "<DATABASE_URL_DE_NEON>" -d neon.dump
```

Son 40 MB, tarda segundos.

Restaurar en la PC servidor:

```powershell
$env:PGPASSWORD="TU_CONTRASENA_DE_POSTGRES"
& "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" `
    -h localhost -U postgres -d control_entradas --clean --if-exists neon.dump
```

> `--clean` borra lo que haya en la base destino. Solo contra la base
> local, nunca contra Neon.

Después, verificar que los datos estén comparando con los de referencia:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas -h localhost -c "SELECT count(*) FROM activos_tipos;"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d control_entradas -h localhost -c "SELECT count(*) FROM activos;"
```

Esperado: **216** tipos y **750** unidades.

---

## Si algo sale mal

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `connection refused` desde la app | Tailscale desconectado, o falta la regla de firewall | `tailscale status`, y repetir el paso 2.1 |
| `Token invalido` (HTTP 401) | Token distinto al del `.env.local`, o el servidor no se reinició después de cambiarlo | Comparar con `PROXY_SQL_TOKEN` y reiniciar `tool\server.py` |
| `Proxy SQL sin token configurado` (HTTP 401) | Falta `PROXY_SQL_TOKEN` en `.env.local` | Agregarlo (paso 5.3) y reiniciar el servidor |
| La web da error 401 en cada consulta | El build web se compiló sin el token | Recompilar con `--dart-define=PROXY_SQL_TOKEN=<token>` |
| `password authentication failed` | La contraseña de `.env.local` no es la del rol | Repetir 2.1 y corregir 2.4 |
| El puerto responde pero la web sale en blanco | Falta el build en `build\web` o `build\pos` | `dir C:\Lycoris\build\web\index.html` |
| `schema.sql` falla al aplicarse | Se corrió `schema_activos.sql` primero | El orden importa: siempre `schema.sql` después |
| El bot no publica la URL | `GITHUB_TOKEN` sin permiso de escritura en el Gist | Verificar el Gist (paso 4.3) |
| El bot pide QR | Falta la carpeta `auth\` | Copiarla de la PC anterior |
| Después de reiniciar no levanta nada | Tareas no registradas | Repetir el paso 6 |
| `Your account or project has exceeded the quota` | Cuota de Neon | Normal hasta el 30/09 |

### Volver atrás

Para borrar todo y empezar de cero:

```powershell
# Quitar las tareas
schtasks /Delete /TN LycorisServidor8501 /F
schtasks /Delete /TN LycorisServidor8502 /F
schtasks /Delete /TN LycorisBotWhatsapp /F

# Quitar las reglas de firewall
Get-NetFirewallRule -DisplayName 'Lycoris*' | Remove-NetFirewallRule
Get-NetFirewallRule -DisplayName 'PostgreSQL*' | Remove-NetFirewallRule

# Bajar el túnel de Cloudflare (si se llegó a crearlo)
cloudflared tunnel delete control-entradas

# Restaurar los .conf originales
copy "C:\Program Files\PostgreSQL\18\data\postgresql.conf.bak" "C:\Program Files\PostgreSQL\18\data\postgresql.conf"
copy "C:\Program Files\PostgreSQL\18\data\pg_hba.conf.bak" "C:\Program Files\PostgreSQL\18\data\pg_hba.conf"
Restart-Service postgresql-x64-18
```
