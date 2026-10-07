# Control de Entradas y Salidas

Sistema de gestion de inventario con modulo **POS**, desarrollado en **Flutter** (web, Windows y Android). Reemplaza la version anterior hecha con Flet/Python.

---

## Aplicaciones

| App | Entry point | Descripcion | Binarios nativos |
|---|---|---|---|
| **Inventario** | `lib/main.dart` | Inventario, stock, producciones, requisiciones, validacion de facturas, historial, reportes, WhatsApp, configuracion | Windows (`LycorisControl.exe`) + Android (APK) |
| **POS** | `lib/main_pos.dart` | Mesas, habitaciones, comandas, ventas, turnos/cajas, cierres, tasa BCV, impresion ESC/POS | Windows (`LycorisPOS.exe`) |
| **Hosteleria** | `lib/main_hosteleria.dart` | Huespedes, reservas/estancias, check-in/out, estados de habitacion (aseo/mantenimiento), modalidad por horas (OP) y vistas actual/semana/mes | Windows (`LycorisHostel.exe`) + web |

**Arquitectura**: 3 plataformas desde un solo codigo base — **web** (desarrollo/uso en navegador) y **nativos** (Windows/Android) con actualizacion remota via GitHub Releases.

---

## Funcionalidades

### Módulo administrativo (`lib/features/`, app id `inventario`)
- **Inventario**: categorias, productos (con stock), movimientos y lista de compra.
- **Stock / Toma de inventario**: conteo y checkpoint por periodos, con recálculo de existencias sobre todos los movimientos (ver `recalcularExistencias`).
- **Producciones**: recetas, editor de recetas, pendientes e historial.
- **Requisiciones**: formulario, cards, visualizacion y auditoria.
- **Validacion de facturas**: validacion de entradas con OCR y registro de pagos.
- **Historial de facturas**: facturas y estados de pago.
- **Activos**: categorias, tipos con unidades de medida y bienes inventariados.
- **Reportes**: ventas, movimientos, estadisticas y cierres de caja (corte de inventario).
- **Configuracion**: categorias, periodos, productos, proveedores, almacenes, sistema y **usuarios** (CRUD del directorio central, asignacion de modulos/equipos y activacion; solo nivel admin/desarrollador).
- **WhatsApp**: bandeja de mensajes con cola y envio via bot.
- **Calculadora**: dialog invocable con F1/atajo en campos de cantidad y precio.

### POS (`lib/features/pos/`)
- Login con PIN: el operador es nombre + PIN y cada dispositivo queda asociado a el.
- Mesas, habitaciones, comandas activas, ventas y cierre de turnos/cajas.
- **Cierre de turno**: genera `pos_cierres` con reporte simple (agregado por linea/plato desde `pos_ventas.items_json`) y reporte detallado (desglose por ingrediente/producto consumido). Los platos se agrupan por nombre base y los contornos se reportan aparte como informativos.
- Tasa del dia del **BCV** (proxy con *stale-while-revalidate*).
- Impresion de tickets **ESC/POS** (impresora termica).
- Configuracion: categorias, platos, mesas, habitaciones, impresora, tasa, usuarios.

---

## Stack tecnologico

| Necesidad | Paquete |
|---|---|
| PostgreSQL (driver nativo `dart:io`) | `postgres ^3.4` |
| Estado | `flutter_riverpod ^2.5` |
| Cache local de catalogos | `shared_preferences ^2.2` |
| Almacenamiento seguro (password/token) | `flutter_secure_storage ^9` |
| Exportacion Excel | `excel ^4` |
| HTTP | `http ^1.2` |
| Impresion termica (Windows) | `windows_printer ^0.2` |
| Version de la app (updater) | `package_info_plus ^9` |
| UUID por dispositivo | `uuid ^4.4` |
| Imagenes (adjuntos de WhatsApp) | `image ^4.3` |

> **No hay dependencias de Supabase.** La app habla PostgreSQL directo; el
> proveedor anterior quedo decommissionado. Ver
> [`docs/migracion-bd-local.md`](docs/migracion-bd-local.md).

Ver `pubspec.yaml` (version actual: **2.0.1**).

---

## Arquitectura

**PostgreSQL directo**, sin capa de sincronizacion. Todo pasa por una abstraccion
de sesion (`SqlSession`) con dos implementaciones elegidas en runtime.

```
lib/
├── main.dart / main_pos.dart / main_hosteleria.dart  # entry points (inventario / POS / Hosteleria)
├── core/
│   ├── auth/                        # login, PIN, sesion, device_id
│   ├── config/
│   │   ├── app_config.dart          # dart-defines, Gist, repo de releases
│   │   └── db_config.dart           # conexion editable desde la app
│   ├── data/
│   │   ├── sql_session.dart         # abstraccion: execute() + runTx()
│   │   ├── native_sql_session.dart  # package:postgres (Windows/Android, TCP)
│   │   ├── http_sql_session.dart    # POST /proxy-sql (web y modo proxy)
│   │   ├── postgres_service.dart    # CRUD generico (bool<->int por information_schema)
│   │   ├── pg_client.dart           # fachada .from().select().eq() estilo PostgREST
│   │   ├── postgres_guard.dart      # Provider<Repo?> para DB no configurada
│   │   ├── cache_service.dart       # cache local con SharedPreferences + TTL
│   │   └── polling_providers.dart   # sincronizacion entre dispositivos
│   ├── models/                      # modelos de dominio (Producto, Categoria, etc.)
│   ├── network/                     # postgres_client.dart, descubrimiento_servidor.dart
│   ├── router/  theme/  state/  logging/  utils/
│   └── updater/                     # actualizacion remota Windows/Android
├── features/                        # activos, auth, calculadora, configuracion,
│                                    # historial, inventario, pos, producciones,
│                                    # reportes, requisiciones, stock, validacion,
│                                    # whatsapp
│   └── <feature>/
│       ├── data/                    # repository + providers
│       └── presentation/            # screens, widgets, dialogs
└── widgets/
```

### Como se conecta la app

`SqlSession` tiene dos implementaciones y la eleccion se hace en
`core/network/postgres_client.dart`, segun la plataforma y lo que haya
configurado el usuario en **Ajustes → Base de datos**:

| Plataforma | Implementacion | Camino a PostgreSQL |
|---|---|---|
| Web | `HttpSqlSession` | `POST /proxy-sql` → `tool/server.py` → PostgreSQL |
| Windows/Android, modo proxy | `HttpSqlSession` | HTTPS contra `tool/server.py` (tunel Cloudflare) |
| Windows/Android, modo TCP | `NativeSqlSession` | `package:postgres` directo al 5432 |

El modo proxy existe porque el driver nativo usa sockets de `dart:io`, que no
existen en el navegador: en web no hay alternativa. En Windows y Android es
 opcional: el TCP directo evita el viaje HTTP por consulta, a costa de obligar
a que el equipo llegue a la base por una red privada (Tailscale).

**El usuario solo escribe el token.** La URL del servidor se descubre al
arrancar leyendo `api_url.json` de un Gist de GitHub
(`core/network/descubrimiento_servidor.dart`), que publica
`tool/iniciar_tunnel_api.js` cada vez que arranca el tunel. Si el tunel rota de
URL, las apps toman la nueva al proximo arranque sin tocar ningun equipo: cada
arranque fuerza la consulta al Gist en vez de confiar en la cache. La respuesta
se cachea 10 min como fallback para cuando no hay red.

### Configuracion de la conexion

La credencial no viaja en el binario. `DbConfig` la guarda en el dispositivo:

- host, puerto, base, usuario, ssl → `SharedPreferences`
- **password y token del proxy** → `flutter_secure_storage` (DPAPI en Windows,
  keychain en Android). A proposito NO caen de vuelta a `SharedPreferences`
  si el almacen seguro falla: guardar la clave en texto plano para "que
  funcione" es peor que fallar con un mensaje.

Precedencia de la URL: configuracion guardada → `--dart-define=DATABASE_URL` →
sin configurar (la app muestra la pantalla de conexion).

### Modelo de datos

- **PostgreSQL** es la unica fuente de verdad.
- Los repos consultan la base a traves de `PostgresService` o del `PgClient` raw.
- **Modelos de dominio** en `lib/core/models/` desacoplan la UI del SQL.
- Los repos convierten `Map<String, dynamic>` a modelos de dominio.

### Conversion bool↔int

El driver nativo devuelve `int` (0/1) en columnas que PostgreSQL tiene como
`boolean`, y al revés. No hay una regla fija por tabla: el tipo real se consulta
a `information_schema`.

**Regla**: `PostgresService` cachea por tabla las columnas `boolean` y normaliza
automaticamente en las lecturas (`fetchAll`, `count`, `fetchByField`, ...) y en
todos los metodos de escritura (`insert`, `insertBatch`, `upsertBatch`,
`updateById`, `updateWhere`, `upsert`, `upsertById`). Al escribir, un `bool`
sobre una columna `integer` se convierte a `1`/`0`; al leer, un `1`/`0` sobre
una columna `boolean` vuelve a `bool`.

`PgClient` (la fachada `.from()...`) **no** normaliza: sus filtros van
directos al SQL, asi que ahi hay que pasar el valor del tipo correcto. Para los
modelos de dominio estan los helpers `toBool()` / `toInt()` de
`lib/core/utils/supabase_cast.dart` (el nombre del archivo quedo de la epoca de
Supabase; el contenido es independiente del backend).

### Exactitud de decimales

Todas las cantidades y pesos se manejan y despliegan con **3 decimales** (`toStringAsFixed(3)`) en stock, producciones, requisiciones, historial, validacion e inventario. La moneda (`$`, `Bs`, `VES`) se mantiene en 2 decimales.

### Recalculo de existencias

`configuracion_repository.dart` (`_recalcularExistenciasDesdeMovimientos`) reconstruye el stock unitario y en checkpoint desde **todos** los movimientos (`movimientos` + `movimientos_archivo`):

1. Lee todos los movimientos de entrada, salida, ajuste, traslado, produccion, venta y devolucion.
2. Para cada `(producto_id, almacen)` toma el **ultimo movimiento por `fecha_movimiento`** (desempate `id`) y usa su `cantidad_nueva` como stock real.
3. Persiste las `existencias` (upsert merge-duplicates) y actualiza `stock_checkpoint.fecha_checkpoint`.

> Uso del ultimo `cantidad_nueva` en vez de sumar deltas: es inmune a *resets* historicos donde se escribio `existencias` directamente sin registrar el movimiento intermedio, que inflaban/deflaban el stock con la suma de deltas.

### Cierre de turno y `pos_cierres`

Al cerrar una sesion se inserta una fila en `pos_cierres` (historica, inmutable) con `reporte_simple_json` y `reporte_detallado_json`:

- **Reporte simple** se construye desde `pos_ventas.items_json` (`resumenItemsVentaDeSesion`): agrega por linea tipo+id, agrupa los platos por nombre base (sin concatenar contornos) y acumula los contornos por nombre en una seccion aparte (no suman al total, su costo ya lo incluye el plato). El total del reporte coincide con el corte de caja.
- **Reporte detallado** (`desgloseIngredientesDeSesion`): por ingrediente/producto, el total consumido y el stock final. Los productos se descargan a si mismos (aparecen como linea propia), los platos descomponen sus ingredientes desde `plato_ingredientes`.

### Auth por dispositivo

El operador se identifica por **nombre + PIN** (case-insensitive sobre el nombre).
Los dos datos viven en el directorio central: `usuarios.nombre` y
`usuarios.pin_hash`, que es un sha256, nunca el PIN en claro.
`SessionController.verificarPin` ademas exige que el usuario este `activo` y que
tenga el modulo `inventario` en `usuario_modulos`.

> Un `pin_hash` **vacio no bloquea**: `UsuariosRepository.verificarPin` devuelve
> `true` cuando no hay hash, asi que ese usuario entra sin verificar nada y la
> app ni muestra el dialogo de PIN. La UI lo marca con un badge *Sin PIN*. Hay
> que ponerle PIN a esas cuentas.

**Un operador puede estar en varios dispositivos a la vez.** `usuario_dispositivos`
guarda una fila por `(usuario_id, device_id)`, con lo que un solo usuario en el
telefono, la tablet y el notebook son tres filas que comparten `usuario_id`:

```
fila 1: (Juan, device_id del telefono)
fila 2: (Juan, device_id de la tablet)
fila 3: (Juan, device_id del notebook)
```

`verificarPin` separa las dos cosas que hace:

1. **Valida el PIN** contra `usuarios.pin_hash` (sha256).
2. **Asocia este dispositivo** con `vincularDispositivo`, que es un
   `INSERT ... ON CONFLICT (usuario_id, device_id) DO UPDATE`. Las filas de los
   demas dispositivos no se tocan, asi que entrar desde un equipo nuevo no
   desvincula los anteriores.

> Antes, contra la tabla `dispositivo_usuario` (deprecada, ya sin uso en `lib/`),
> el paso 2 pisaba el `device_id` de la fila que encontraba por nombre, con lo
> que una sola fila podia estar en un solo dispositivo: entrar desde la tablet
> desvinculaba el telefono. Y como `DeviceIdService` genera el UUID en
> `SharedPreferences`, reinstalar la app se llevaba el enlace puesto.

**Autodetección**: cada dispositivo tiene un UUID propio (`DeviceIdService`).
Al abrir la app, `nombrePorDeviceId` busca el operador de ese `device_id` y el
login muestra el nombre fijo, dejando pedir solo el PIN (con un boton *Usar
otro* por si hay que cambiar). Corre cuando `estadoBdProvider` llega a `lista`
—el chequeo de salud respondio—, no al montar la pantalla: el pool de
PostgreSQL resuelve despues de preguntar al Gist y abrir el tunel, y preguntar
antes devolvia `null` sin consultar.

`configurado_en` paso a significar **ultima vinculacion**, no alta: es lo que
desempata cuando el mismo `device_id` quedo en varias filas. `verificarPin` lo
refresca en cada entrada.

> **Costo del modelo**: cada reinstalacion deja la fila anterior atras. Son
> filas inertes —`nombrePorDeviceId` no las ve porque ese `device_id` ya no
> existe en ningun lado— pero se acumulan y hay que borrarlas a mano.

### Cache local de catalogos

Los catalogos (categorias, productos, proveedores, periodos, settings de POS) se
cachean en **SharedPreferences** con timestamp y TTL de 5 min:

1. Primera carga: consulta la base → guarda en cache con `cachedAt`.
2. Mientras no expire el TTL: se sirve del cache, sin tocar la base.
3. Al expirar: `CacheService.get()` devuelve `null` y el repositorio va directo
   a la base.
4. Al escribir (create/update/delete): se borra la clave del catalogo afectado.

> **Pendiente**: `CacheService` tiene `getStale()` para servir el dato viejo y
> refrescar en background (*stale-while-revalidate*), pero **ningun repositorio
> lo llama todavia**. Hoy el comportamiento ante cache expirado es ir a la base
> de forma directa. Sin red con cache expirado, la pantalla queda sin datos.

**Tablas con cache**: categorias, productos, proveedores, periodos, pos_settings.
**Tablas sin cache**: existencias, movimientos, ventas, comandas, whatsapp_queue.

### Sincronizacion entre dispositivos (polling)

PostgreSQL directo no tiene Realtime, asi que la sincronizacion se hace por
**polling periodico** desde `core/data/polling_providers.dart`, inicializado una
vez desde `AppShell`:

| Tabla | Intervalo | Providers que invalida |
|-------|-----------|------------------------|
| `pos_comandas` | 5 s | comandas, mesas, habitaciones |
| `pos_sesiones` | 10 s | turno activo |
| `pos_ventas` | 10 s | ventas, ventas de hoy |
| `facturas` | 15 s | historial de facturas |
| `categorias` | 30 s | categorias de configuracion |
| `productos` | 30 s | productos de configuracion |
| `proveedores` | 30 s | proveedores de configuracion |

Cada tick corre `SELECT 1 FROM <tabla> WHERE updated_at >= <checkpoint> LIMIT 1`
y solo invalida si hay algo nuevo. El checkpoint evita recargar providers cada
5 segundos con una ventana de tiempo fija, que es lo que pasaba antes.

Algunas pantallas tienen su propio polling ademas del central:
`StockScreen` (30 s), `ValidacionScreen` (10 s) y `BandejaScreen` (15 s).

---

## Base de datos

PostgreSQL, servido desde una PC propia. El proveedor anterior era Supabase
y quedo decommissionado por cuota; la transicion esta documentada en
[`docs/migracion-bd-local.md`](docs/migracion-bd-local.md).

### Levantar la base local (PC Windows)

Los scripts estan en [`tool/windows/`](tool/windows/README.md), con el orden
de pasos:

```powershell
# 1. Rol, base y pg_hba.conf restringido a Tailscale (como Administrador)
powershell -ExecutionPolicy Bypass -File tool\windows\configurar_postgres.ps1 -DbPassword "..."

# 2. Tablas y entorno Python
tool\windows\crear_estructura.bat

# 3. Arranque automatico al prender el equipo
powershell -ExecutionPolicy Bypass -File tool\windows\registrar_autostart.ps1
```

### Conectar desde la app

En Windows y Android: **Ajustes → Sistema → Configurar conexion**, con la
IP de Tailscale de la PC servidor. Se guarda en el dispositivo, asi que
cambiar la IP del servidor no requiere recompilar.

En web no hay que hacer nada: el navegador va siempre contra
`tool/server.py`, que es quien habla con PostgreSQL.

### Tabla requerida: `dispositivo_usuario`

No esta en `schema.sql`: se crea aplicando las migraciones a mano, en este
orden.

```powershell
psql -U postgres -d control_entradas -f supabase\migrations\20250101000000_add_dispositivo_usuario.sql
psql -U postgres -d control_entradas -f supabase\migrations\20250102000000_add_device_id.sql
```

O copiar y pegar:

```sql
-- Como esta realmente en la base. Ojo: NO hay UNIQUE en `device_id`, y el
-- multi-dispositivo depende de eso (ver "Auth por dispositivo").
CREATE TABLE IF NOT EXISTS dispositivo_usuario (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre        TEXT NOT NULL,
  pin_hash      TEXT,                    -- nullable en la base real
  device_id     TEXT NOT NULL,           -- sin UNIQUE
  configurado_en TIMESTAMPTZ DEFAULT now()
);
```

> Las migraciones activan RLS con una policy `USING (true)`. Eso venia de la
> epoca de Supabase/PostgREST, donde el acceso pasaba por la API. Ahora la app
> se conecta directo a PostgreSQL como dueño de la tabla, y el dueño **no** esta
> sujeto a RLS: la policy no agrega ni quita nada. Se puede dejar como esta o
> quitar; no es lo que protege los datos hoy.

### Mapa de tablas

| Tabla | Usada por |
|-------|-----------|
| `categorias` | Inventario, Stock, Configuracion, POS |
| `productos` | Inventario, Stock, Configuracion, Producciones, POS |
| `existencias` | Stock, Configuracion, Requisiciones |
| `movimientos` | Stock, Historial, Requisiciones, Producciones |
| `movimientos_archivo` | Archivo de movimientos (recalculos de stock) |
| `proveedores` | Configuracion, Validacion |
| `facturas` | Historial, Validacion |
| `factura_pagos` | Historial |
| `periodos` | Configuracion |
| `requisiciones` | Requisiciones |
| `requisicion_detalles` | Requisiciones |
| `recetas` | Producciones |
| `receta_componentes` | Producciones |
| `producciones` | Producciones |
| `produccion_detalles` | Producciones |
| `platos_categorias` | POS |
| `platos` | POS |
| `plato_ingredientes` | POS |
| `plato_contornos` | POS |
| `pos_settings` | Configuracion, POS |
| `usuarios` | Inventario, POS, Hostelería (directorio central) |
| `usuario_modulos` | Inventario, POS, Hostelería (acceso por módulo) |
| `usuario_dispositivos` | Inventario (auto-login por equipo) |
| `pos_sesiones` | POS (turnos/cajas) |
| `pos_cierres` | Reportes (corte de caja/inventario) |
| `pos_temporales` | POS (ventas temporales pre-cierre) |
| `pos_mesas` | POS |
| `habitaciones` | Hostelería, POS (comandas; estados libre/aseo/mantenimiento) |
| `tipos_habitacion` | Hostelería, POS (capacidad de personas) |
| `pos_categorias` | POS |
| `pos_comandas` | POS |
| `pos_ventas` | POS |
| `dispositivo_usuario` | (obsoleta) migrada a `usuario_dispositivos` |
| `compras_lista` | Inventario (lista de compra) |
| `whatsapp_queue` | WhatsApp |
| `stock_checkpoint` | Stock (toma de inventario) |
| `almacenes` | Stock, Requisiciones, Producciones, POS (catalogo de almacenes) |
| `activos` | Activos |
| `activos_categorias` | Activos |
| `activos_tipos` | Activos |
| `hosteleria_huespedes` | Hostelería (datos completos del huésped) |
| `hosteleria_reservas` | Hostelería (estancias + hora entrada/salida) |
| `hosteleria_reserva_personas` | Hostelería (titular + acompañantes por estancia) |
| `hosteleria_vehiculos` | Hostelería (vehículos por estancia) |

Las cuatro ultimas no estan en `schema.sql`: `almacenes` viene de la
migracion `20260901120000_add_almacenes.sql` y las de activos de
`supabase/schema_activos.sql`.

Ver `supabase/schema.sql` para el esquema completo (idempotente).

---

## Compilacion y despliegue

### Web (desarrollo)

```bash
# <TOKEN>    = WHATSAPP_BOT_TOKEN (el mismo de whatsapp_bot/.env, ver .env.example)
# <PROXY>    = PROXY_SQL_TOKEN (el mismo de .env.local; sin el, /proxy-sql responde 401)

# Inventario (puerto 8501)
flutter build web --release -o build/web \
    --dart-define=WHATSAPP_BOT_TOKEN=<TOKEN> \
    --dart-define=PROXY_SQL_TOKEN=<PROXY>
tool/venv/bin/python tool/server.py 8501 build/web

# POS (puerto 8502)
flutter build web --release -t lib/main_pos.dart -o build/pos \
    --dart-define=WHATSAPP_BOT_TOKEN=<TOKEN> \
    --dart-define=PROXY_SQL_TOKEN=<PROXY>
cp web_pos/favicon.png web_pos/manifest.json build/pos/
cp -r web_pos/icons build/pos/
cp web_pos/index.html build/pos/index.html
tool/venv/bin/python tool/server.py 8502 build/pos

# Hostelería (puerto 8503)
flutter build web --release -t lib/main_hosteleria.dart -o build/hosteleria \
    --dart-define=WHATSAPP_BOT_TOKEN=<TOKEN> \
    --dart-define=PROXY_SQL_TOKEN=<PROXY>
cp web_hosteleria/favicon.png web_hosteleria/manifest.json build/hosteleria/
cp -r web_hosteleria/icons build/hosteleria/
cp web_hosteleria/index.html build/hosteleria/index.html
tool/venv/bin/python tool/server.py 8503 build/hosteleria
```

El `PROXY_SQL_TOKEN` **va embebido en web** porque el navegador no tiene
almacen seguro para guardar un secreto. Es el precio de que el proxy.execute SQL
con las credenciales del servidor: sin token, responde 401 y no ejecuta nada.

`tool/server.py` expone `/proxy-bcv` (tasa del BCV con cache y *stale-while-revalidate*), `/proxy-sql` (acceso a PostgreSQL desde Flutter web) y recibe los logs de Flutter web (`POST /log`).

**Proxy SQL con psycopg** (requerido en web): el driver nativo `package:postgres` usa sockets de `dart:io`, inexistentes en Flutter web; por eso las queries viajan por `POST /proxy-sql`. El servidor aplica las transacciones iniciadas con `HttpSqlSession` y limpia las olvidadas. Las dependencias están todas en `tool/requirements.txt` y se instalan una sola vez:

```bash
python3 -m venv tool/venv
tool/venv/bin/pip install -r tool/requirements.txt
```

Ojo: los extras `[binary,pool]` no son opcionales. Sin `[pool]` el servidor
arranca pero contesta 503 en cada consulta.

La `DATABASE_URL` se lee de la variable de entorno o de `.env.local` (prioriza `DATABASE_URL_UNPOOLED`).

### Nativos (CI / GitHub Actions)

Flutter no puede compilar Windows desde Linux, asi que los binarios nativos se generan en **CI** con `.github/workflows/release.yml`.

**Version por app.** `versions.json` (raiz) guarda la version vigente de cada app:

```json
{ "inventario": {"version":"2.1.10"}, "pos": {"version":"2.1.10"}, "hosteleria": {"version":"2.1.10"} }
```

Cada build se sella con `--dart-define=APP_VERSION=<version>` y cada app publica su **propia release** con tag `<appId>-vX.Y.Z`. El updater lee `versions.json`, compara solo su entrada de `APP_ID` y descarga el asset de **su** release. Por eso puedes publicar una app sin que las otras crean que deben actualizarse.

**Que se construye.** El workflow es **manual**: se eligen las apps con `apps` (`all` o una lista) y, opcionalmente, `version`. Solo se compilan las apps seleccionadas. La version por defecto es la de `versions.json` (no se auto-incrementa); si indicas `version`, esa se usa para las apps seleccionadas y se commitea al manifiesto.

| Job | Producto | Assets de su release |
|---|---|---|
| `windows-pos` | `LycorisPOS.exe` (icono azul), si se elige `pos` | `app-pos-windows.zip` |
| `windows-inventario` | `LycorisControl.exe`, si se elige `inventario` | `app-inventario-windows.zip` |
| `windows-hosteleria` | `LycorisHostel.exe`, si se elige `hosteleria` | `app-hosteleria-windows.zip` |
| `linux` | `LycorisPOS` + `LycorisControl` + `LycorisHostel` (Linux) | `app-pos-linux.tar.gz`, `app-inventario-linux.tar.gz`, `app-hosteleria-linux.tar.gz` |
| `android` | APK inventario | `app-inventario-android.apk` |
| `release` | Publica `<appId>-vX.Y.Z` y actualiza `versions.json` | — |

**Como generar una release**:
1. Agregar los secrets en *Settings → Secrets and variables → Actions*:
   - `WHATSAPP_BOT_TOKEN` — lo usan los jobs de build.
   - `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` — solo para el APK de Android.
2. *Actions → "Build & Release nativa" → Run workflow* con:
   - `apps` — `all` (default) publica las tres; `inventario,pos` (o `hosteleria`) publica solo esas.
   - `version` (opcional) — ej. `2.1.10`. Si se deja vacio, usa la de `versions.json`.
3. El job `release` crea una release por app seleccionada y commitea `versions.json` a `main` con `[skip ci]`.

> Para subir de version, edita `versions.json` (o pasa `version` en el workflow). No hay auto-incremento: lo que dice el manifiesto es lo que se publica.

> Ya no hay tag global `vX.Y.Z`: cada app usa `<appId>-vX.Y.Z`. El workflow ya **no** corre solo con cada push.

> Los builds nativos **no** llevan `DATABASE_URL` ni `PROXY_SQL_TOKEN`: la app
> nativa lee la conexion del almacen seguro del equipo, asi que las credenciales
> no se distribuyen dentro del binario. El token del proxy se configura desde
> Ajustes → Base de datos.

> Ya no hay tag global `vX.Y.Z`: cada app usa `<appId>-vX.Y.Z`.


---

## Configuracion (dart-define)

| Define | Default | Descripcion |
|---|---|---|
| `PROXY_SQL_TOKEN` | — | **Obligatorio en web.** Token que valida `/proxy-sql` en el header `X-Proxy-Token`. Sin el, el proxy responde 401 |
| `GIST_ID` | `5b37693a...` | Gist donde se publica la URL del tunel (`api_url.json`) |
| `GIST_TOKEN` | — | Solo si el Gist es privado. El default es publico y se lee sin autenticar |
| `DATABASE_URL` | — | Connection string de PostgreSQL. Solo como fallback: la config del dispositivo tiene prioridad |
| `APP_ID` | `inventario` | `pos`, `inventario` o `hosteleria` — define icono, binario, entrada del manifiesto y asset del updater |
| `APP_LABEL` | segun `APP_ID` | Nombre mostrado en dialogos y titulos |
| `APP_VERSION` | — | Version de **esta** app sellada al compilar (la del `versions.json`). Si falta, el updater cae a `PackageInfo` |
| `WHATSAPP_BOT_TOKEN` | — | Token del bot de WhatsApp (`whatsapp_bot/.env`, ver `.env.example`) |
| `UPDATE_URL` | GitHub `versions.json` | URL del manifiesto de versiones por app |
| `UPDATE_REPO` | `reidchend/control-entradas-salidas` | Repo de releases para el updater |
| `WEB_PORT` | `8502` | Legacy, ya no se usa |

> **Las credenciales no viajan en el repositorio.** En web el token viene
> embebido (`PROXY_SQL_TOKEN`) porque el navegador no tiene almacen seguro; en
> Windows y Android se configura en el dispositivo desde Ajustes → Base de
> datos, y por eso `DATABASE_URL` es solo un fallback. Ver
> [`docs/migracion-bd-local.md`](docs/migracion-bd-local.md).

---

## Tests

```bash
flutter test
```

Tests actuales (109 en 16 archivos, contados con `Select-String` sobre
`test/*_test.dart`):

| Archivo | Casos | Que cubre |
|---|---|---|
| `db_config_test.dart` | 31 | Precedencia de la URL, persistencia, secure storage |
| `postgres_client_test.dart` | 14 | `initializePostgres`, `forzarProxy`, normalizacion de URL, seleccion de sesion |
| `descubrimiento_servidor_test.dart` | 11 | Lectura del Gist, cache 10 min, contenido invalido |
| `pg_client_bind_test.dart` | 10 | Orden de los placeholders que genera `PgClient` al armar el SQL |
| `stock_whatsapp_models_test.dart` | 8 | Modelos: Producto, Categoria, Existencia, Movimiento, MensajeWhatsapp |
| `ticket_escpos_test.dart` | 6 | Bytes ESC/POS |
| `cache_service_test.dart` | 5 | TTL de `CacheService` con SharedPreferences |
| `db_config_panel_test.dart` | 5 | Panel de configuracion de BD |
| `postgres_guard_test.dart` | 7 | Estado de la BD: configurada, comprobada, caida, reintento |
| `pos_catalogo_test.dart` | 3 | Catalogo del POS |
| `pos_tasa_bcv_test.dart` | 3 | Tasa del BCV con cache |
| `pos_login_bootstrap_test.dart` | 2 | Bootstrap de login |
| `pos_comanda_test.dart` | 1 | Comanda |
| `pos_login_test.dart` | 1 | Login por PIN |
| `pos_ventas_test.dart` | 1 | Ventas |
| `widget_test.dart` | 1 | AppShell arranca |

Los 16 usan `flutter_test`, asi que **no corren sin el SDK de Flutter**. Para
poder verificar la logica en una maquina que solo tiene Dart, hay un package
aparte en `tool/`:

```bash
cd tool && dart pub get && dart test
```

Ahi corren 21 casos (`tool/test/`): la replica ejecutable de `_bindPlan` y la de
la vigencia de la cache del Gist. Ambas leen la constante real del codigo de la
app, asi que siguen siendo validas si le cambian el valor.

> **Cobertura acotada**: ademas de lo de arriba, `tool/smoke_sql.py` corre 12
> pruebas contra PostgreSQL real (orden de parametros en `UPDATE`, placeholder
> repetido, `buscarProductos`, catalogo del POS con booleanos, y lints que
> recorren `lib/` buscando `.eq()` numerico sobre una columna boolean, listeners
> con la firma equivocada y SQL crudo que repite un `$n`). Ademas replica el
> flujo de un operador en varios dispositivos y comprueba que registrar en uno no
> desvincula los otros. Ese es el camino donde mas bugs han aparecido, y queda
> fuera de `flutter test`.

> Ejecutar con `LD_LIBRARY_PATH=/tmp/opencode/libs` si hay problemas con SQLite en Linux.

---

## Historial de migraciones

### Migracion Drift → Supabase → PostgreSQL (completada)

Fases 1-10: de Drift a Supabase (2026-08), y despues de Supabase a PostgreSQL
directo (2026-09), al agotarse la cuota del plan gestionado. Los archivos
conservaron nombres de la epoca de Supabase (`supabase_cast.dart`,
`supabase/`), pero el backend es PostgreSQL.

- **Fase 0**: Modelos de dominio (12+ archivos en `lib/core/models/`)
- **Fase 1**: Servicio base CRUD (`postgres_service.dart` + `pg_client.dart`)
- **Fase 2**: Repositorios migrados (10 features)
- **Fase 3**: Limpieza Drift — eliminados `lib/core/db/`, `lib/core/sync/`, dependencias drift/sqlite3
- **Fase 4**: Sincronizacion entre dispositivos (WebSocket en Supabase, hoy polling)
- **Fase 5**: Cache local con SharedPreferences
- **Fase 6**: Null-safe providers — `Provider<Repo?>` con `postgres_guard.dart`
- **Fase 7**: Auth por dispositivo — `DeviceIdService` con UUID + `device_id` en `dispositivo_usuario`
- **Fase 8**: Fix bool↔int — conversion automatica por tipo real de columna
- **Fase 9**: Fix N+1 queries — batch queries en historial, requisiciones y facturas
- **Fase 10**: Fix error handling — try/catch en comanda_screen, validacion_screen, bandeja_screen
- **Fase 11**: PostgreSQL gestionado → PostgreSQL local — `SqlSession` con implementaciones nativa y HTTP, proxy `/proxy-sql`, descubrimiento por Gist, conexion configurable desde la app

### Migraciones recientes

- `20261002030000_habitaciones_estados_op.sql` — renombra `pos_habitaciones`→`habitaciones` y `pos_tipos_habitacion`→`tipos_habitacion`; agrega estado operativo (`libre`/`aseo`/`mantenimiento` + notas) y modalidad Operativa OP (`modalidad`, `bloque_horas`, `hora_limite`) en `hosteleria_reservas`.
- `20261002020000_hosteleria_checkin.sql` — check-in de Hostelería: tipos de habitación con capacidad (`pos_tipos_habitacion` + `pos_habitaciones.tipo_id`, renombrados luego), datos completos del huésped, `hosteleria_reserva_personas`, `hosteleria_vehiculos` y horas de entrada/salida.
- `20261002010000_usuarios_centrales.sql` — directorio central de usuarios (`usuarios`, `usuario_modulos`, `usuario_dispositivos`). Todo operador que se registra en el módulo administrativo queda como `admin`; desde Configuración → Usuarios se crea/edita el resto del directorio y se ajustan niveles.
- `20261002000000_hosteleria.sql` — tablas propias del modulo Hosteleria (`hosteleria_huespedes`, `hosteleria_reservas`), vinculadas a `habitaciones`.
- `20260922000000_activos_tipos.sql` — tipos de activo con unidades de medida.
- `20260901120000_add_almacenes.sql` — catalogo de almacenes (antes eran strings libres).
- `20260901000000_add_stock_fecha_checkpoint.sql` — `stock_checkpoint.fecha_checkpoint` y columnas `venta_id`/`venta_sync_uuid` en `movimientos_archivo`.
- `20260827000000_add_pos_cierres.sql` — tabla historica `pos_cierres` para el corte de caja/inventario al cerrar turno.
- `20260826000000_add_pos_sesiones_whatsapp_queue.sql` — turnos de caja y cola de WhatsApp.

---

## Documentacion

- `lib/` — codigo organizado por feature (core, features/...), siguiendo la estructura modular de `AGENTS.md`.
- `supabase/schema.sql` — esquema base (idempotente). El directorio quedo con el nombre de la epoca de Supabase.
- `supabase/schema_activos.sql` — categorias, tipos y unidades de activos.
- `supabase/migrations/` — migraciones SQL, en orden por timestamp.
- `docs/migracion-bd-local.md` — transicion de PostgreSQL gestionado a PostgreSQL local.
- `docs/montar-pc-servidor.md` — montaje paso a paso de la PC servidor.
- `tool/windows/` — scripts para preparar la PC servidor.
- `INSTRUCCIONES_AGENTE_SERVIDOR.md` — estado del servidor y diagnostico.
- `tool/smoke_sql.py` — smoke test de la ruta SQL (app → proxy → PostgreSQL),
  corre sin Flutter.

### Deuda tecnica conocida

- **34 referencias a Supabase en el codigo**: mensajes de error
  (`'Supabase no configurado'`), el boton *"Verificar Supabase"* en
  `sistema_tab.dart` (que ademas esta duplicado con *"Probar Conexion Local"*:
  ambos llaman `testLocalConnection()`), y el nombre `supabase_cast.dart`.
- **`syncIntervalSeconds`** en `app_config.dart` y `webPort`: constantes sin
  ningun call site, remanentes de la epoca de Supabase.
- **Cache sin stale-while-revalidate**: `getStale()` existe sin usarse.
- **`device_id` sin indice UNIQUE**: la migracion
  `20250102000000_add_device_id.sql` lo declara, pero en la base solo existe
  el PRIMARY KEY. **No se puede aplicar**: el modelo de multi-dispositivo
  permite N filas por operador, y ademas cambiar de usuario en el mismo
  equipo (*Usar otro*) deja dos filas con el mismo `device_id`. Con el
  `UNIQUE` puesto, el login fallaria con `23505`. Si alguna vez se quiere,
  el indice tendria que ir por `(nombre, device_id)`, no por `device_id`.
- **`pin_hash` guarda el PIN en texto plano**: la columna se llama asi pero
  no hashea nada; `verificarPin` compara con `==`. Cualquiera con acceso de
  lectura a la tabla tiene los PIN de todos los operadores.
- **Filas huerfanas de `dispositivo_usuario`**: cada reinstalacion genera un
  `device_id` nuevo y deja la fila anterior sin borrar. Son inertes (15 filas
  hoy, varias repetidas) pero hay que limpiarlas a mano.
- **`LogBridge` a medio construir**: `push()` acumula en una lista que nunca se
  envia y `flush()` esta vacio, asi que los logs de la app web nunca llegan a
  la terminal. Por eso los `print()` de debug no ayudaban a diagnosticar.
- **`tool/e2e_proxy_test.py` no se ejecuta**: necesita `dart` y
  `E2E_DATABASE_URL`. Para verificar la ruta SQL sin Flutter esta
  `tool/smoke_sql.py`.
