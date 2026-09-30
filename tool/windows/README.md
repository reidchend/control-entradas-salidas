# Server local (PC Windows)

Scripts para levantar PostgreSQL + el servidor web en la PC que actúa como
servidor, sin depender de Neon.

## Orden de instalación

Cada paso depende del anterior. Las rutas y el flujo completo, con el
contexto de por qué, están en
[`docs/migracion-bd-local.md`](../../docs/migracion-bd-local.md).

| # | Paso | Quién lo hace | Archivo |
|---|------|---------------|---------|
| 1 | Instalar PostgreSQL 18 | Manual (2 clics) | ver docs |
| 2 | Crear rol, base y abrir puerto a Tailscale | `configurar_postgres.ps1` | este repo |
| 3 | Crear tablas + entorno Python | `crear_estructura.bat` | este repo |
| 4 | Instalar Tailscale yloguearse | Manual | ver docs |
| 5 | Compilar la web (una vez) | Manual | ver docs |
| 6 | Levantar la stack para trabajar | `iniciar_todo.bat` | este repo |
| 7 | Arranque automático al prender el PC | `registrar_autostart.ps1` | este repo |

Los pasos 2 y 7 piden **PowerShell como Administrador**: escriben en
`C:\Program Files\PostgreSQL`, crean reglas de firewall y registran tareas
programadas.

## Instalación de PostgreSQL (paso 1)

El instalador oficial de EDB, que además registra el servicio de Windows:

1. Descargá <https://www.postgresql.org/download/windows/>.
2. Instalá con los defaults, pero **anotá la contraseña del superusuario
   `postgres`** — la vas a necesitar en el paso 3.
3. Dejá el puerto `5432` y desatacá "Stack Builder" al final.

Queda instalado en `C:\Program Files\PostgreSQL\18` y como servicio
`postgresql-x64-18`, que ya arranca solo con Windows.

## Configurar la base (paso 2)

En PowerShell **como Administrador**, desde la carpeta `tool\windows`:

```powershell
powershell -ExecutionPolicy Bypass -File configurar_postgres.ps1 `
    -DbPassword "una-contrasena-fuerte" -DbName "control_entradas"
```

Te va a pedir la contraseña del superusuario `postgres` (la del instalador),
enmascarada. No la pasa por parámetro para que no quede en el historial.

Qué hace, y por qué importa:

- **`listen_addresses = '*'`** — acepta conexiones de red, no solo locales.
- **`pg_hba.conf`**: agrega una regla `scram-sha-256` **solo** para
  `100.64.0.0/10`, que es el rango que Tailscale reparte. El script deja las
  reglas por defecto de Postgres intactas.

  > ⚠️ **No amplíes ese rango a `0.0.0.0/0`.** Con `0.0.0.0/0` el puerto
  > 5432 queda abierto a la LAN y, con un port forwarding, a internet. Es
  > una base de inventario: el firewall y Tailscale son la única barrera.

- **Regla de firewall `PostgreSQL 5432 (Tailscale)`**: sin esto la app no
  conecta. Windows bloquea por defecto el tráfico entrante a 5432, y el
  síntoma sería "connection refused" con Postgres perfectamente levantado.
  La regla se restringe al rango de Tailscale, igual que `pg_hba`.
- Crea el rol `control_app` y la base `control_entradas`, con el rol como
  propietario. Es idempotente: volver a ejecutarlo solo actualiza la
  contraseña y rehace la regla de firewall.

Los originales quedan respaldados como `postgresql.conf.bak` y
`pg_hba.conf.bak` en el directorio de datos.

## Crear las tablas (paso 3)

```bat
crear_estructura.bat
```

Prepara `tool\venv` con `psycopg` y aplica, en orden:

1. `supabase/schema.sql` — el esquema general.
2. `supabase/schema_activos.sql` — categorías, tipos y unidades de activos.
3. `supabase/migrations/*.sql` — tablas y columnas que se fueron agregando
   después (turnos de caja del POS, cola de WhatsApp, cierres, almacenes...).

El orden importa: `schema_activos.sql` reutiliza `set_pos_updated_at()` que
define `schema.sql`. La única migración que se saltea es
`20260922000000_activos_tipos.sql`: es la transformación de la tabla
`activos` *plana* a unidades individuales, y `schema_activos.sql` ya deja esa
estructura final (aplicarla en un bootstrap fallaría en el backfill).

Después editá `.env.local` para que apunte a la base local. Se crea desde el
ejemplo versionado:

```bat
copy .env.local.example .env.local
```

```env
DATABASE_URL_UNPOOLED=postgresql://control_app:TU_CONTRASENA@localhost:5432/control_entradas?sslmode=disable
DATABASE_URL=postgresql://control_app:TU_CONTRASENA@localhost:5432/control_entradas?sslmode=disable
```

Reemplazá `TU_CONTRASENA` por la que pasaste en `-DbPassword`.

`sslmode=disable` porque el tráfico ya viaja cifrado por Tailscale. La base
local no tiene TLS configurado; poner `require` haría fallar la conexión.

`tool/server.py` prefiere `DATABASE_URL_UNPOOLED` para el proxy, porque abre
y cierra una conexión por request. Con las dos variables iguales no hay
diferencia de comportamiento, pero conviene dejarlas sincronizadas.

## Compilar la web (paso 5)

Una sola vez, o cada vez que cambie el código:

```bat
flutter build web --release -o build\web
flutter build web --release -t lib\main_pos.dart -o build\pos
copy web_pos\index.html build\pos\index.html
copy web_pos\manifest.json build\pos\
copy web_pos\favicon.png build\pos\
xcopy /E /I web_pos\icons build\pos\icons
```

## Trabajar en la PC (paso 6)

```bat
iniciar_todo.bat
```

Levanta Tailscale, 8501 (inventario) y 8502 (POS), y muestra la **IP de
Tailscale** — que es el valor que se carga en la app.

## Arranque automático (paso 7)

```powershell
powershell -ExecutionPolicy Bypass -File registrar_autostart.ps1
```

Crea las tareas `LycorisServidor8501`, `LycorisServidor8502` y
`LycorisBotWhatsapp` con `schtasks` (viene con Windows, no hace falta instalar
NSSM). La del bot solo se registra si `whatsapp_bot/` ya tiene su `.env` y su
carpeta `auth`; si falta alguna, avisa y sigue con los servidores, porque la
base de datos no depende del bot.

> Tailscale no se registra acá porque necesita tu sesión y tu cuenta: se
> instala a mano y queda como servicio de Windows que inicia con el equipo.
> Verificá que quede en modo "always-on" en su cliente, o la base queda
> inalcanzable cuando la PC se apaga.

## El bot de WhatsApp, en la misma PC

El bot corre en **esta misma máquina** (puerto 3000). No toca PostgreSQL: es
un servicio HTTP que expone la API que consume la app, y publica la URL de
su túnel en un Gist. Por eso puede convivir con la base sin agregado de carga.

Para migrarlo a la PC nueva hay que copiar **cuatro cosas**:

| Qué | De dónde | Por qué |
|---|---|---|
| `whatsapp_bot/auth/` | PC anterior | Sesión de WhatsApp. **Sin esto hay que escanear un QR de nuevo.** |
| `whatsapp_bot/.env` | PC anterior | `GITHUB_TOKEN` con permiso de escritura en el Gist |
| `whatsapp_bot/cloudflared.exe` | Descarga oficial | El binario del túnel; no está en el repo |
| `config.json` | PC anterior | `groupId` del grupo de destino |

En la PC nueva:

```bat
cd whatsapp_bot
npm install --production
iniciar_bot.bat
```

`iniciar_bot.bat` es el launcher apto para servicios. El histórico
`start_bot.bat` no sirve para autostart por dos motivos: mata **todos** los
procesos `node.exe` y `cloudflared.exe` de la máquina (y en una PC que corre
varios servicios eso se lleva por delante cosas que no debería), y termina
en `pause`.

### La URL del túnel cambia en cada reinicio

`start_tunnel.js` usa un *quick tunnel* de Cloudflare
(`cloudflared tunnel --url`), que da un `https://algo.trycloudflare.com`
**distinto cada vez que arranca**. El bot lo detecta y lo sube al Gist
(`update_gist.js`), y la app lo lee desde ahí
(`lib/features/whatsapp/data/whatsapp_repository.dart:12`).

Consecuencias prácticas:

- Después de cada reinicio hay que verificar que la URL nueva se publicó.
  Si el PATCH al Gist falla, la app queda apuntando a una URL muerta.
- `GITHUB_TOKEN` necesita scope de escritura sobre el Gist, o el paso
  anterior falla en silencio.
- Un quick tunnel es para pruebas, no para producción. Si esto va a estar
  arriba en un local real, conviene un tunnel con dominio propio (un
  `trycloudflare.com` aleatorio no es una URL estable para una app que la
  tiene embebida en un Gist).

## Conectar las apps Windows y Android

En cada equipo (y en el celular):

1. Instalá Tailscale ylogueate con la misma cuenta.
2. Abrí la app → **Ajustes → Sistema → Configurar conexión**.
3. Cargar host = IP de Tailscale de la PC servidor, puerto 5432, base y
   usuario.
4. **Probar conexión**. Debería dar "Conexión correcta".
5. **Guardar**.

Se guarda en el dispositivo, así que si cambia la IP de la PC servidor se
corrige ahí mismo, sin recompilar.
