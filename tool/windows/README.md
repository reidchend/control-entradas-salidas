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

El orden importa: `schema_activos.sql` reutiliza `set_pos_updated_at()` que
define `schema.sql`.

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

Crea las tareas `LycorisServidor8501` y `LycorisServidor8502` con
`schtasks` (viene con Windows, no hace falta instalar NSSM).

> Tailscale no se registra acá porque necesita tu sesión y tu cuenta: se
> instala a mano y queda como servicio de Windows que inicia con el equipo.
> Verificá que quede en modo "always-on" en su cliente, o la base queda
> inalcanzable cuando la PC se apaga.

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
