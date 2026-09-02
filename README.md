# Control de Entradas y Salidas

Sistema de gestion de inventario con modulo **POS**, desarrollado en **Flutter** (web, Windows y Android). Reemplaza la version anterior hecha con Flet/Python.

---

## Aplicaciones

| App | Entry point | Descripcion | Binarios nativos |
|---|---|---|---|
| **Inventario** | `lib/main.dart` | Inventario, stock, producciones, requisiciones, validacion de facturas, historial, reportes, WhatsApp, configuracion | Windows (`LycorisControl.exe`) + Android (APK) |
| **POS** | `lib/main_pos.dart` | Mesas, habitaciones, comandas, ventas, turnos/cajas, cierres, tasa BCV, impresion ESC/POS | Windows (`LycorisPOS.exe`) |

**Arquitectura**: 3 plataformas desde un solo codigo base — **web** (desarrollo/uso en navegador) y **nativos** (Windows/Android) con actualizacion remota via GitHub Releases.

---

## Funcionalidades

### Inventario (`lib/features/`)
- **Inventario**: categorias, productos (con stock), movimientos y lista de compra.
- **Stock / Toma de inventario**: conteo y checkpoint por periodos, con recálculo de existencias sobre todos los movimientos (ver `recalcularExistencias`).
- **Producciones**: recetas, editor de recetas, pendientes e historial.
- **Requisiciones**: formulario, cards, visualizacion y auditoria.
- **Validacion de facturas**: validacion de entradas con OCR y registro de pagos.
- **Historial de facturas**: facturas y estados de pago.
- **Reportes**: ventas, movimientos, estadisticas y cierres de caja (corte de inventario).
- **Configuracion**: categorias, periodos, productos, proveedores y sistema.
- **WhatsApp**: bandeja de mensajes con cola y envio via bot.
- **Calculadora**: dialog invocable con F1/atajo en campos de cantidad y precio.

### POS (`lib/features/pos/`)
- Login con PIN por dispositivo (`device_id` unico por dispositivo).
- Mesas, habitaciones, comandas activas, ventas y cierre de turnos/cajas.
- **Cierre de turno**: genera `pos_cierres` con reporte simple (agregado por linea/plato desde `pos_ventas.items_json`) y reporte detallado (desglose por ingrediente/producto consumido). Los platos se agrupan por nombre base y los contornos se reportan aparte como informativos.
- Tasa del dia del **BCV** (proxy con *stale-while-revalidate*).
- Impresion de tickets **ESC/POS** (impresora termica).
- Configuracion: categorias, platos, mesas, habitaciones, impresora, tasa, usuarios.

---

## Stack tecnologico

| Necesidad | Paquete |
|---|---|
| Supabase (Postgres REST + Realtime) | `supabase_flutter ^2.8` |
| Estado | `flutter_riverpod ^2.5` |
| Cache local (stale-while-revalidate) | `shared_preferences ^2.2` |
| Almacenamiento seguro (credenciales/tokens) | `flutter_secure_storage ^9` |
| Exportacion Excel | `excel ^4` |
| HTTP | `http ^1.2` |
| Impresion termica (Windows) | `windows_printer ^0.2` |
| Version de la app (updater) | `package_info_plus ^9` |
| UUID por dispositivo | `uuid ^4.4` |

Ver `pubspec.yaml` (version actual: **2.0.1**).

---

## Arquitectura

**Directo a Supabase**: toda consulta y escritura va directamente a Supabase via REST. No hay base de datos local ni capa de sincronizacion.

```
lib/
├── main.dart / main_pos.dart        # entry points (inventario / POS)
├── core/
│   ├── auth/                        # login, PIN, sesion, device_id
│   ├── config/                      # app_config.dart (URL/key Supabase, appId, repo releases)
│   ├── data/
│   │   ├── supabase_service.dart    # servicio CRUD generico (con conversion bool→int)
│   │   ├── supabase_providers.dart  # providers de Supabase, cache, realtime
│   │   ├── cache_service.dart       # cache local con SharedPreferences + TTL
│   │   └── realtime_service.dart    # suscripciones Realtime generico
│   ├── models/                      # modelos de dominio (Producto, Categoria, etc.)
│   ├── network/                     # cliente Supabase, HTTP
│   ├── router/  theme/  state/  logging/  utils/
│   └── updater/                     # actualizacion remota Windows/Android
├── features/                        # auth, calculadora, configuracion, historial,
│                                    # inventario, pos, producciones, reportes,
│                                    # requisiciones, stock, validacion, whatsapp
│   └── <feature>/
│       ├── data/                    # repository + providers
│       └── presentation/            # screens, widgets, dialogs
└── widgets/
```

### Modelo de datos

- **Supabase** es la unica fuente de verdad (PostgreSQL).
- Los repos consultan Supabase directamente via `supabase_flutter`.
- **Modelos de dominio** en `lib/core/models/` desacoplan la UI de Supabase.
- Los repos convierten `Map<String, dynamic>` a modelos de dominio.

### Conversion bool→int

Las columnas `integer` de Supabase que representan booleanos (`activo`, `es_pesable`, `es_contorno`, etc.) requieren `0`/`1` en vez de `true`/`false`.

**Regla**: `SupabaseService._encodeMap()` aplica conversion automatica en todos los metodos de escritura (`insert`, `insertBatch`, `updateById`, `updateWhere`, `upsert`, `upsertById`). Los filtros `.eq()` directos al cliente deben usar `1`/`0` explicitamente.

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

Cada dispositivo genera un UUID unico (`DeviceIdService`) almacenado en `SharedPreferences`. El PIN se asocia al `device_id` en la tabla `dispositivo_usuario`. Un solo usuario por dispositivo.

### Cache local (stale-while-revalidate)

Los catalogos (categorias, productos, proveedores, periodos, settings) se cachean localmente con **SharedPreferences**:

1. Primera carga: consulta Supabase → guarda en cache con timestamp.
2. Siguientes cargas: sirve desde cache si no expiro (TTL 5 min).
3. Si expiro: sirve cache stale → refresca en background.
4. Sin red: muestra datos cacheados (con "ultima actualizacion").
5. Al escribir (create/update/delete): invalida cache de esa tabla.

**Tablas con cache**: categorias, productos, proveedores, periodos, pos_settings.
**Tablas sin cache** (Realtime): existencias, movimientos, ventas, comandas, whatsapp_queue.

### Supabase Realtime

Suscripciones WebSocket en tiempo real para sync entre dispositivos:

| Tabla | Ubicacion | Efecto |
|-------|-----------|--------|
| `pos_sesiones` | AppShell centralizado | Invalida turno activo |
| `pos_comandas` | AppShell centralizado | Invalida comandas/mesas |
| `pos_venta_detalle` | AppShell centralizado | Invalida ventas |
| `categorias` | AppShell centralizado | Invalida config categorias |
| `productos` | AppShell centralizado | Invalida config productos |
| `proveedores` | AppShell centralizado | Invalida config proveedores |
| `facturas` | AppShell centralizado | Invalida historial facturas |
| `existencias` | StockScreen interno | Reload automatico |
| `movimientos` | StockScreen interno | Reload automatico |
| `whatsapp_queue` | BandejaScreen interno | Refresh automatico |

---

## Base de datos Supabase

### Tabla requerida: `dispositivo_usuario`

Ejecutar en Supabase SQL Editor el archivo:

```sql
supabase/migrations/20250101000000_add_dispositivo_usuario.sql
supabase/migrations/20250102000000_add_device_id.sql
```

O copiar y pegar:

```sql
CREATE TABLE IF NOT EXISTS dispositivo_usuario (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre        TEXT NOT NULL,
  pin_hash      TEXT NOT NULL,
  device_id     TEXT UNIQUE,
  configurado_en TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE dispositivo_usuario ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dispositivo_usuario_all" ON dispositivo_usuario
  FOR ALL USING (true) WITH CHECK (true);
```

### Todas las tablas de Supabase

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
| `pos_usuarios` | POS |
| `pos_sesiones` | POS (turnos/cajas) |
| `pos_cierres` | Reportes (corte de caja/inventario) |
| `pos_temporales` | POS (ventas temporales pre-cierre) |
| `pos_mesas` | POS |
| `pos_habitaciones` | POS |
| `pos_categorias` | POS |
| `pos_comandas` | POS |
| `pos_ventas` | POS |
| `dispositivo_usuario` | Auth (login PIN por dispositivo) |
| `compras_lista` | Inventario (lista de compra) |
| `whatsapp_queue` | WhatsApp |
| `stock_checkpoint` | Stock (toma de inventario) |

Ver `supabase/schema.sql` para el esquema completo (idempotente).

---

## Compilacion y despliegue

### Web (desarrollo)

```bash
# Inventario (puerto 8501)
flutter build web --release -o build/web
python3 tool/server.py 8501 build/web

# POS (puerto 8502)
flutter build web --release -t lib/main_pos.dart -o build/pos
cp web_pos/favicon.png web_pos/manifest.json build/pos/
cp -r web_pos/icons build/pos/
cp web_pos/index.html build/pos/index.html
python3 tool/server.py 8502 build/pos
```

`tool/server.py` expone `/proxy-bcv` (tasa del BCV con cache y *stale-while-revalidate*) y recibe los logs de Flutter web (`POST /log`).

### Nativos (CI / GitHub Actions)

Flutter no puede compilar Windows desde Linux, asi que los binarios nativos se generan en **CI** con `.github/workflows/release.yml`:

| Job | Producto | Assets publicados en la release |
|---|---|---|
| `windows-pos` | `LycorisPOS.exe` (icono azul) | `app-pos-windows.zip` |
| `windows-inventario` | `LycorisControl.exe` (icono normal) | `app-inventario-windows.zip` |
| `android` | APK inventario (icono normal) | `app-inventario-android.apk` |
| `release` | Publica la release `vX.Y.Z` | — |

**Como generar una release**:
1. Push a `main`.
2. Agregar los secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` en *Settings → Secrets and variables → Actions*.
3. *Actions → "Build & Release nativa" → Run workflow* con la version deseada (ej. `2.0.1`).
4. Descargar los binarios desde la pagina de la release.

> El workflow tambien dispara con un tag `v*` pusheado.

---

## Configuracion (dart-define)

| Define | Default | Descripcion |
|---|---|---|
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | constantes compiladas | Credenciales de Supabase |
| `APP_ID` | `inventario` | `pos` o `inventario` — define icono, binario y asset del updater |
| `APP_LABEL` | segun `APP_ID` | Nombre mostrado en dialogos y titulos |
| `UPDATE_REPO` | `reidchend/control-entradas-salidas` | Repo de releases para el updater |

---

## Tests

```bash
flutter test
```

Tests actuales (28):
- Modelos de dominio: Producto, Categoria, Existencia, Movimiento, MensajeWhatsapp
- TemporalesRepository (in-memory)
- CacheService (SharedPreferences)
- POS: login, catalogo, comanda, ventas, tasa BCV, ticket ESC/POS
- Widget: AppShell boots

> Ejecutar con `LD_LIBRARY_PATH=/tmp/opencode/libs` si hay problemas con SQLite en Linux.

---

## Historial de migraciones

### Migracion Drift → Supabase (completada)

- **Fase 0**: Modelos de dominio (12+ archivos en `lib/core/models/`)
- **Fase 1**: Servicio base Supabase (`supabase_service.dart` + providers)
- **Fase 2**: Repositorios migrados (10 features)
- **Fase 3**: Limpieza Drift — eliminados `lib/core/db/`, `lib/core/sync/`, dependencias drift/sqlite3
- **Fase 4**: Supabase Realtime — suscripciones WebSocket para sync entre dispositivos
- **Fase 5**: Cache local — stale-while-revalidate con SharedPreferences
- **Fase 6**: Null-safe providers — `Provider<Repo?>` con `supabase_guard.dart`
- **Fase 7**: Auth por dispositivo — `DeviceIdService` con UUID + `device_id` en `dispositivo_usuario`
- **Fase 8**: Fix bool→int — conversion automatica en `SupabaseService._encodeMap()` + filtros directos
- **Fase 9**: Fix N+1 queries — batch queries en historial, requisiciones y facturas
- **Fase 10**: Fix error handling — try/catch en comanda_screen, validacion_screen, bandeja_screen

### Migraciones recientes

- `20260827000000_add_pos_cierres.sql` — tabla historica `pos_cierres` para el corte de caja/inventario al cerrar turno.
- `20260901000000_add_stock_fecha_checkpoint.sql` — `stock_checkpoint.fecha_checkpoint` (fecha del snapshot) y columnas `venta_id`/`venta_sync_uuid` en `movimientos_archivo` (espejo de movimientos).

---

## Documentacion

- `lib/` — codigo organizado por feature (core, features/...), siguiendo la estructura modular de `AGENTS.md`.
- `supabase/schema.sql` — esquema remoto (idempotente).
- `supabase/migrations/` — migraciones SQL.
