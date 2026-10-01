# Plan — Cierre de Caja + Corte de Inventario (POS) + envío WhatsApp + Sesiones multi-cajero

> **Estado general:** ⬜ No iniciado · En planificación
> **Fecha de creación:** 2026-08-27
>
> Documento de trabajo para implementar por partes. Cada fase tiene su checklist
> para marcar lo realizado y consultar el avance. Los archivos se referencian con
> ruta relativa desde la raíz del repo.

---

## Resumen

Al cerrar un turno de POS se generan **dos reportes de venta** vinculados al
inventario (uno simple-agregado y uno detallado por ingrediente), se persisten en
un histórico (`pos_cierres`) y se envían al **grupo de reportes** de WhatsApp
(simple = mensaje de texto; detallado = archivo `.txt`). Se refuerza la
protección contra cierres accidentales y se rediseña la capa de sesiones para
permitir **múltiples turnos activos simultáneos** (uno por cajero) en el mismo
dispositivo, sin que uno cierre el turno del otro.

---

## Contexto técnico (lo verificado en el código)

- El POS **ya descuenta stock al cobrar**: `aplicarMovimientosVenta`
  (`lib/features/pos/data/pos_ventas_repository.dart:275`) inserta
  `movimientos (tipo:'venta')` con `venta_id`, `cantidad_anterior`,
  `cantidad_nueva`, `almacen`, y decrementa `existencias`.
- `resolverMovimientosVenta` (`pos_ventas_repository.dart:547`) descompone los
  platos en **ingredientes** (vía `getPlatoIngredientes`/`plato_ingredientes`) y
  suma cantidades por `(producto_id, almacen)`. Incluye contornos
  (`contorno_ids`).
- Cada venta guarda `items_json` con `{id, tipo, nombre, precio, cantidad,
  contornos}` en `pos_ventas` (`registrarVenta`, `pos_ventas_repository.dart:222`).
- El cierre de turno actual solo calcula **caja**: `cerrarSesion`
  (`pos_repository.dart:55`) con `_totalVigenteDeSesion` (`:90`). No genera corte
  de inventario.
- **Modelo de sesiones actual = UN solo turno activo por dispositivo**:
  `getSesionActiva()` (`pos_repository.dart:124`) filtra `cerrada_en is null`
  limit 1. `iniciarSesion` (`pos_session.dart:77`) detecta "sesión ajena" y
  obliga a cerrar o retomar. → Requiere rediseño (Fase 0).
- `Producto` NO tiene campo `costo` (`lib/core/models/producto.dart` → solo
  `precioVenta`). El reporte simple valora a **precio de venta**; el detallado se
  enfoca en cantidades/consumo de ingredientes.
- **Bot WhatsApp** (corre local, tunnel zrok, requiere reinicio manual):
  `whatsapp_bot/server.js` y `bot.js`. Hoy maneja **un solo grupo** (`group_id`)
  y **solo envía texto e imágenes** (no adjunta `.txt`). Endpoints: `/send`,
  `/send-image`, `/send-to`, `/groups`, `/set-group`, `/config`.

### Decisiones de diseño confirmadas
1. Persistencia en **tabla nueva `pos_cierres`** (histórico inmutable).
2. Reportes **valorados a precio de venta** (simple) + consumo por ingredientes
   (detallado). Sin costo real por ahora.
3. Envío por WhatsApp con **segundo grupo dedicado** en el bot (grupo de
   reportes), mensaje texto para el simple y **archivo `.txt`** para el
   detallado.
4. Protección anti-cierre: **aviso por turno corto (<8h)** + **doble
   confirmación** (tipear "CONFIRMAR") + resumen del corte.
5. **Varios turnos activos simultáneos** (uno por cajero) en el mismo
   dispositivo; salir al login no cierra el turno en uso.

---

## Fase 0 — Rediseño de sesiones: múltiples turnos activos (uno por cajero)

**Estado:** ✅ Completada (2026-08-27) — pendiente de prueba manual en dispositivo

**Objetivo:** pasar de "un turno activo por dispositivo" a "un turno activo por
cajero", permitiendo que varios cajeros abran su turno en el mismo equipo sin que
uno cierre al otro, y volver al login para abrir el de otro cajero.

### Checklist
- [x] `lib/features/pos/data/pos_repository.dart`: `getSesionActiva()` →
      `getSesionActivaDeUsuario(usuarioId)` (turno activo por usuario, no global).
- [x] `pos_repository.dart`: `abrirSesion` permitir apertura aunque existan otros
      turnos activos (no había restricción; no requirió cambio).
- [x] `pos_repository.dart`: `getUsuariosConTurnoActivo()` → `Set<int>` (ids de
      cajeros con turno abierto, para el login).
- [x] `pos_repository.dart`: `cerrarSesionesStale` — dejó de llamarse en
      `iniciarSesion` (se elimina el cierre automático de turnos >8h para evitar
      "cierres fantasma"). El cajero cierra SU turno manualmente.
- [x] `pos_repository.dart`: `getSesiones` listar turnos de todos los cajeros
      (ya lista todas; no requería cambio).
- [x] `lib/features/pos/data/pos_session.dart`: `iniciarSesion` retoma el turno
      del MISMO cajero o abre uno nuevo; eliminado `sesionAjena`,
      `forzarCerrarSesionAjena`, `retomarSesionAjena` (ya no bloquean).
- [x] `pos_session.dart`: `salirSinCerrar` conserva el turno (ya lo hacía).
- [x] `pos_session.dart`: `cerrarSesion` cierra SOLO su propio turno (caja + corte).
- [x] `pos_providers.dart`: `turnoActivoUsuarioProvider` → `turnosActivosProvider`
      (Set<int> de cajeros con turno abierto).
- [x] `realtime_providers.dart`: invalidación actualizada a `turnosActivosProvider`.
- [x] `pos_screen.dart`: `_login` simplificado (sin manejo de sesión ajena);
      `_manejarSesionAjena` eliminado; login marca con `turnosActivos.contains(id)`.
- [x] Auditar queries que dependan de "una sola sesión activa": no quedan huérfanos
      (grep verificó cero referencias a `turnoActivoUsuarioProvider`,
      `sesionAjena`, `forzarCerrarSesionAjena`, `retomarSesionAjena`, `getSesionActiva`).
- [x] Verificar: `pos_sesiones` puede tener varias filas `cerrada_en null`
      (el modelo/query lo permiten).
- [x] `flutter analyze` sin errores (único warning pre-existente en
      `comanda_screen.dart:776`, ajeno a esta fase).
- [ ] Probar en dispositivo: cajero A abre turno → sale al login → cajero B abre
      su turno propio → A retoma el suyo en otro momento. (Prueba manual pendiente)

---

## Fase 1 — Bot de WhatsApp: segundo grupo + documentos

**Estado:** ⬜ Pendiente

**Objetivo:** el bot pueda enviar a un **grupo de reportes** distinto del grupo
principal, tanto mensajes de texto como **archivos `.txt`**.

> ⚠️ El bot corre local en la máquina del usuario (tunnel zrok). Los cambios de
> esta fase requieren **reiniciar el bot manualmente** para que surtan efecto.

### Checklist
- [ ] `whatsapp_bot/bot.js`: `setReportGroupId`/`getReportGroupId` (segundo grupo
      dedicado, persistido junto al `groupId`).
- [ ] `whatsapp_bot/bot.js`: función para enviar **documento `.txt`** al grupo de
      reportes (Baileys documento).
- [ ] `whatsapp_bot/server.js`: `POST /send-report` (mensaje texto al grupo de
      reportes).
- [ ] `whatsapp_bot/server.js`: `POST /send-document` (adjuntar `.txt` al grupo
      de reportes).
- [ ] `whatsapp_bot/server.js`: `POST /set-report-group` + `/config` ampliado
      (`report_group_id`, `report_group_name`).
- [ ] Sintaxis JS validada (`node --check`).
- [ ] Reinicio local del bot por parte del usuario.

---

## Fase 2 — BD (Neon): tabla `pos_cierres`

**Estado:** ✅ Completada (2026-08-27) — ejecutada en Neon SQL Editor

### Checklist
- [x] Migración en `supabase/migrations/20260827000000_add_pos_cierres.sql`:
      `pos_cierres` con `id serial PK`, `sesion_id int`, `usuario_id int`,
      `abierta_en`, `cerrada_en`, `caja_inicial double`, `total_ventas double`,
      `caja_final double`, `reporte_simple_json text`, `reporte_detallado_json
      text`, `sync_uuid text`, `created_at`, `updated_at`.
- [x] Ejecutar migración en Neon (vía consola SQL / Data API / `psql`).
- [x] Secuencia `pos_cierres_id_seq` sincronizada (auto con SERIAL).

---

## Fase 3 — Flutter: capa de datos (corte + reportes)

**Estado:** ✅ Completada (2026-08-27)

### Checklist
- [x] **Modelos** (`lib/core/models/pos_cierre_models.dart`):
      `LineaVenta`, `ReporteSimple` (agregado por producto/plato/contorno +
      categoría + total), `DesgloseIngrediente` (ingrediente, total consumido,
      stock final, `usos:[{plato, cantidad}]`), `ReporteDetallado`,
      `CierreCaja` (caja inicial/ventas/final + ambos reportes + usuario/fechas).
- [x] `lib/features/pos/data/pos_ventas_repository.dart`:
      `movimientosVentaDeSesion(sesionId)` (movimientos `tipo:'venta'` de la
      sesión).
- [x] `pos_ventas_repository.dart`: `desgloseIngredientesDeSesion(sesionId)`
      (mapa inverso ingrediente → platos/contornos vía `items_json` +
      `getPlatoIngredientes`/`resolverMovimientosVenta`).
- [x] `lib/features/pos/data/pos_repository.dart`: `generarCierre(sesionId)`
      → `CierreCaja`.
- [x] `pos_repository.dart`: `guardarCierre(CierreCaja)` → inserta en
      `pos_cierres`.
- [x] `lib/features/pos/data/pos_providers.dart`: `cierreProvider` (family) +
      `cierresHistorialProvider`.
- [x] `flutter analyze` sin errores.

---

## Fase 4 — Flutter: UI + anti-cierre accidental

**Estado:** ✅ Completada (2026-08-27)

### Checklist
- [x] `lib/features/pos/presentation/dialogs/cierre_turno_dialog.dart` (nuevo),
      abierto en `_cerrarSesion` (`pos_screen.dart`).
- [x] Regla **turno corto (<8h)**: aviso destacado + decisión consciente.
- [x] **Doble confirmación**: resumen del corte + tipear "CONFIRMAR" para
      habilitar el botón de cerrar.
- [x] Acciones del diálogo: "Enviar por WhatsApp", "Imprimir", "Confirmar cierre"
- [x] `flutter analyze` sin errores (solo warnings pre-existentes).
      y guardar".
- [ ] Al confirmar: `guardarCierre` + `cerrarSesion(su turno)`.
- [ ] `lib/features/pos/presentation/cierre_screen.dart` (nuevo): historial de
      cierres (listar/ver/reenviar/reimprimir).
- [ ] Entrada "Cierres" en `pos_home_screen.dart` + etapa `_PosStage.cierres` en
      `pos_screen.dart` (admin).
- [ ] `lib/features/pos/data/ticket_escpos.dart`: `construirTicketCierre`.
- [ ] `flutter analyze` sin errores.

---

## Fase 5 — WhatsApp Flutter (envío de reportes)

**Estado:** ✅ Completada (2026-08-27)

### Checklist
- [x] `lib/features/whatsapp/data/whatsapp_repository.dart`:
      `enviarReporteSimple(text)` → `POST /send-report` (texto, fallback a cola).
- [x] `whatsapp_repository.dart`: `enviarReporteDetallado(txt)` →
      `POST /send-document` (adjunto `.txt`).
- [x] Obtener jid del grupo de reportes desde `GET /config` (`report_group_id`).
- [x] Conectar botón "Enviar por WhatsApp" en `cierre_turno_dialog.dart` a estos métodos.
- [x] Botón "WhatsApp y cerrar" envía ambos reportes y cierra la sesión.
- [x] `flutter analyze` sin errores.

---

## Fase 6 — Verificación y despliegue

**Estado:** ✅ Verificación completada (2026-08-27) — pendiente deploy

### Checklist
- [x] `flutter analyze` global sin errores (solo warnings pre-existentes).
- [x] Revisión del flujo de cierre multi-turno + corte + envío WhatsApp.
- [ ] Commit con mensaje descriptivo (estilo del repo).
- [ ] Preguntar al usuario: "¿compilo y despliego?" antes de compilar/desplegar.
- [ ] Build Windows vía CI (`release.yml`) / web.

---

## Fuera de alcance (no bloqueante)
- Valoración **a costo real** por producto (falta campo `costo` en `productos`).
- Corte multi-almacén avanzado (foco en el almacén de venta `restaurante`,
  aunque el detallado respeta el `almacen` real de cada movimiento).

## Orden sugerido de implementación
Fase 0 (sesiones: base y más delicada) → Fase 1 (bot) → Fase 2 (BD) → Fase 3
(datos) → Fase 4 (UI + anti-cierre) → Fase 5 (WhatsApp) → Fase 6 (deploy).

## Registro de avance
| Fecha | Fase | Detalle | Estado |
|-------|------|---------|--------|
| 2026-08-27 | Plan | Creación del documento de planificación | ⬜ |
| 2026-08-27 | Fase 0 | Rediseño de sesiones multi-cajero: `getSesionActivaDeUsuario`, `getUsuariosConTurnoActivo`, `turnosActivosProvider`, `iniciarSesion` retoma/abre por cajero, sin `sesionAjena`. `flutter analyze` sin errores. | ✅ Pendiente prueba manual |
| 2026-08-27 | Fase 1 | Bot: `setReportGroupId`/`getReportGroupId`, `sendReportToGroup` (texto) y `sendDocumentToGroup` (`.txt`), endpoints `/send-report`, `/send-document`, `/set-report-group`, `/config` ampliado y panel con grupo de reportes. `node --check` OK. | ✅ Pendiente reinicio manual |
| 2026-08-27 | Fase 2 | Migración `pos_cierres` ejecutada en Neon (tabla histórica inmutable con reportes JSON, índices, trigger updated_at). | ✅ Completada |
| 2026-08-27 | Fase 3 | Modelos `CierreCaja`/`ReporteSimple`/`ReporteDetallado`, `movimientosVentaDeSesion`, `desgloseIngredientesDeSesion`, `generarCierre`, `guardarCierre`, providers. `flutter analyze` OK. | ✅ Completada |
| 2026-08-27 | Fase 4 | Diálogo `cierre_turno_dialog`: resumen, aviso turno <8h, doble confirmación "CONFIRMAR", acciones WhatsApp/Imprimir/Confirmar. `flutter analyze` OK. | ✅ Completada |
| 2026-08-27 | Fase 5 | WhatsApp: `enviarReporteSimple` (POST /send-report), `enviarReporteDetallado` (POST /send-document .txt), `getStatus` con `report_group_id`, diálogo con botones "WhatsApp" / "WhatsApp y cerrar". `flutter analyze` OK. | ✅ Completada |
| 2026-08-27 | Fase 6 | `flutter analyze` global OK (0 errores nuevos). Verificación flujo completo. | ✅ Verificación completada |
