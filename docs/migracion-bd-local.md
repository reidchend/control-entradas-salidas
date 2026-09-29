# Migracion de base de datos: Neon → PostgreSQL local

Estado: **en curso**. Fases 1 y 2 listas en codigo, la parte de Windows esta
pendiente de ejecutar en la PC.

## Por que

El proyecto usaba Neon (Supabase) como base de datos, y el plan Free se
quedo sin cuota:

```
ERROR: Your account or project has exceeded the quota.
Upgrade your plan to increase limits.
```

El plan Free de Neon esta limitado a 100 CU-horas/proyecto/mes, 0.5 GB de
storage y 5 GB de transferencia. No deja margen: cualquier mes con uso real
lo vuelve a tumbar, y una cuota agotada deja la app sin poder ni leer.

En vez de pagar por un plan que puede volver a quedar chico, la base se
mueve a **una PC Windows 10 dedicada en la casa**, conectada por Tailscale.
Sin costo, sin cuotas, y con el control de los datos en el mismo lugar que
la operacion.

El dump de Neon se hace **al final**, cuando la infraestructura local ya
esta probada. Ver [Fase 4](#fase-4-dump-y-restauracion).

## Arquitectura

```
                    ┌──────────────────────────────┐
   Internet ────────│  Cloudflare tunnel (HTTP)    │
                    │  whatsapp_bot/start_tunnel   │
                    └──────────────┬───────────────┘
                                   │ expone 8501 / 8502 / 3000
                                   │ (nunca 5432)
                    ┌──────────────▼───────────────┐
                    │  PC Windows 10 (servidor)    │
                    │                              │
   Tailscale        │  ┌────────────────────────┐  │      ┌──────────────┐
   (100.64.0.0/10) ◄─┤  │ tool/server.py         │  ├─────►│ PostgreSQL   │
   ───────┐         │  │ 8501 web inventario    │  │ local │ 5432         │
           │         │  │ 8502 POS               │  │ 5432  │ base local   │
  ┌────────┴────┐    │  │ /proxy-sql             │  │      │              │
  │ Windows app │────┤  └────────────────────────┘  │      └──────────────┘
  │ Android app │    │                              │
  └─────────────┘    │  whatsapp_bot (3000)        │
                     │  node, NO accede a la BD    │
                     └──────────────────────────────┘
```

Dos caminos distintos a proposito:

| Cliente | Como llega a la BD | Por que |
|---|---|---|
| Web y POS | `HttpSqlSession` → `GET /proxy-sql` → `tool/server.py` → Postgres | El navegador no puede abrir sockets TCP. El proxy es el unico camino posible. |
| Windows y Android | `package:postgres` directo a Postgres por Tailscale | La app nativa ya sabe hablar SQL. Meterla por el proxy solo agrega latencia y un punto de falla. |

El bot de WhatsApp (`whatsapp_bot/server.js`, puerto 3000) **no toca la
base**: expone la API HTTP que consume la app. Por eso puede convivir en la
misma PC sin agregar carga a Postgres, y su tunel de Cloudflare no necesita
cambios.

## Decisiones

**Tailscale y no port forwarding.** Postgres queda escuchando en la red pero
`pg_hba.conf` acepta unicamente el rango `100.64.0.0/10` que reparte
Tailscale. Sin esto, abrir 5432 seria abrir la base de inventario a
internet.

**Un solo servicio de BD, varias entradas.** El proxy y las apps nativas
terminan en la misma base, con el mismo esquema. No hay replica ni
sincronizacion que mantener.

**Configuracion en la app, no recompilar.** La URL de la BD se guarda en el
dispositivo (Ajustes → Sistema → Configurar conexion). Si cambia la IP de la
PC servidor, se corrige en cada dispositivo. Precedencia:
configuracion guardada > `--dart-define=DATABASE_URL` > sin conexion.

**Sin credenciales en el repositorio.** Una URL de Neon quedo hardcodeada
en `lib/core/config/app_config.dart` y como el repositorio es publico,
esa credencial quedo expuesta. Ademas, meter la clave de la base local en
el binario de una app que se distribuye es lo mismo. La base local se
configura en el dispositivo; el repo no lleva claves.

## Fases

### Fase 1: codigo (lista)

- [x] `lib/core/config/db_config.dart` — configuracion persistida (host,
      puerto, base, usuario, contrasena, sslmode) + metodo `test()` que
      abre una conexion de prueba y la cierra.
- [x] `lib/core/config/app_config.dart` — se elimino la URL de Neon.
- [x] `lib/core/network/postgres_client.dart` — resuelve la config del
      dispositivo y, si no hay, la del `--dart-define`.
- [x] `lib/features/configuracion/presentation/widgets/db_config_panel.dart`
      — formulario con probar / guardar / borrar.
- [x] `sistema_tab.dart` — tarjeta "Base de datos" que abre el panel.
- [x] `supabase/schema_activos.sql` — DDL de `activos_categorias`,
      `activos_tipos` y `activos`, que no estaba en `schema.sql`.

### Fase 2: preparar la PC Windows

Detalle paso a paso en
[`tool/windows/README.md`](../tool/windows/README.md).

- [ ] Instalar PostgreSQL 18 (servicio de Windows, puerto 5432).
- [ ] `configurar_postgres.ps1` — rol, base, `listen_addresses`, la regla de
      `pg_hba.conf` restringida a Tailscale y **la regla de firewall**. Los
      tres filtros hacen falta: sin la de firewall el síntoma es
      "connection refused" con Postgres levantado.
- [ ] `crear_estructura.bat` — entorno Python + tablas.
- [ ] Instalar Tailscale, fijar la IP de la PC.
- [ ] Clonar el repo y compilar la web.
- [ ] `registrar_autostart.ps1` — arranque automatico con `schtasks`, con
      salida redirigida a `tool/logs/server*.log` (corriendo como SYSTEM no
      hay consola, y sin log un servicio caido es indistinguible de uno sano).

### Fase 3: probar con datos sinteticos

Antes de tocar los datos reales, con la base vacia:

- [ ] Ajustes → "Probar conexion" desde Windows y desde Android: debe dar
      conexion correcta.
- [ ] Crear un producto, venderlo en el POS, cerrar caja. Verificar que
      quedan en la base.
- [ ] Cargar la web y confirmar que lista datos.
- [ ] Reiniciar la PC y verificar que PostgreSQL, Tailscale y los servidores
      levantan solos.

### Fase 4: dump y restauracion

Ultima fase, a proposito: si el restore falla, la base local ya esta
probada y solo se descarta lo importado.

El problema: con la cuota agotada, `pg_dump` a Neon falla por conexion.
Depende de cual barra se haya vaciado (ver dashboard de Neon):

- **Cuota de compute (CU-horas)** — se reinicia al empezar el mes.
- **Cuota de transferencia** — tambien mensual.
- **Storage** — ese error se ve distinto, y es independiente de los dos
  anteriores.

Opciones, en orden de preference:

1. **Esperar el reinicio mensual.** Sin costo, pero deja la app sin base
   hasta entonces.
2. **Upgrade temporal de un mes**, `pg_dump`, y cancelar. Cuesta un mes de
   un plan pagado, y solo si el dump se descarga dentro de ese mes.
3. **Reconstruir los datos a mano.** Ultimo recurso; hay movimientos
   historicos que no se pueden recalcular.

Una vez Neon responda:

```bash
pg_dump --no-owner --no-privileges --format=custom \
  "<DATABASE_URL_NEON>" -d neon.dump
```

Restauracion en la PC Windows, con los archivos en orden
(`schema.sql` primero, porque `schema_activos.sql` usa una funcion que
define el primero):

```bat
set PGPASSWORD=<CONTRASENA>
pg_restore -d control_entradas --clean --if-exists neon.dump
```

> El `--clean` borra lo que haya. Solo correr contra la base local, nunca
> contra Neon.

### Fase 5: verificacion y despliegue

- [ ] Comparar conteos contra Neon. Referencia actual (antes de migrar):
      216 tipos, 750 unidades de activos, 0 huerfanas.
- [ ] `flutter analyze` sin errores.
- [ ] `flutter test`.
- [ ] Recompilar Windows y Android. Como la URL va en el dispositivo, no
      necesita `--dart-define=DATABASE_URL`; se configura en la app.
- [ ] `flutter build web` y desplegar 8501 / 8502.
- [ ] Actualizar `.github/workflows/release.yml` si corresponde.
- [ ] Revocar la credencial de Neon expuesta en el historial de git.

## Riesgos

| Riesgo | Mitigacion |
|---|---|
| La PC se apaga y la app no conecta | PostgreSQL y Tailscale arrancan con Windows; hay que verificar el reinicio automatico (Fase 3) |
| Sin Internet en la LAN, Tailscale no enruta | Tailscale funciona sobre Internet. Sin Internet no hay app contra la base, en ninguna arquitectura |
| Se amplia `pg_hba.conf` por error y queda 5432 abierto | El script deja el rango explicito y comentado; revisar antes de cambiar |
| La base local no tiene replica | Aceptado: una sola base, mismo riesgo de hardware que antes pero sin cuota |
| El restore queda a medias | Se hace al final, con la base vacia y probada |

## Rotacion de la credencial expuesta

La URL de Neon estuvo hardcodeada en `app_config.dart` en commits
publicados. Aunque ya no este en el working tree, sigue en el historial y
por lo tanto en el repo publico. Hay que **revocar y rotar** esa clave en
Neon; no basta con borrar la linea.
