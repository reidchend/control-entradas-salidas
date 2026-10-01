# Instrucciones para Agente en PC Servidor (Windows)

## Estado actual del proyecto (30/09/2026)

### Problemas pendientes
1. **Login no detecta usuario existente** - Al escribir "Reidchend" + PIN "1234", la UI se queda en modo "Registro" en vez de cambiar a "Login"
2. **Validación de entradas no persiste** - Al validar, se crea la factura pero el UPDATE de `movimientos.factura_id` no persiste en BD (logs dicen `affected=1` pero BD queda `NULL`)
3. **Creación de usuarios duplicados** - Al intentar loguear, crea usuario nuevo en vez de encontrar el existente

### Logs clave a revisar
- `[LOGIN_SCREEN]` - en consola Flutter (login_screen.dart)
- `[SESSION]` - en consola Flutter (session_controller.dart)
- `[DIRECT_DB]` / `[COMMIT_OK]` - en consola Python (tool/server.py)

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

## Logs esperados (qué buscar)

### En consola Flutter (app):
```
[LOGIN_SCREEN] _verificarNombreExistente: existe=true para "Reidchend"
[LOGIN_SCREEN] _existeNombre actualizado a true
[LOGIN_SCREEN] _submit: yaExiste=true para "Reidchend"
[SESSION] verificarPin: rows=1 for "Reidchend"
[SESSION] verificarPin: found id=5, nombre=Reidchend, pin_hash=1234
```

### En consola Python (server.py):
```
[DIRECT_DB] sql=SELECT 1 FROM dispositivo_usuario WHERE LOWER(TRIM(nombre)) = LOWER($1) LIMIT 1 params=['Reidchend']
[DIRECT_DB] affected=1 rowcount=1
[DIRECT_DB] VERIFICACIÓN post-UPDATE: [(5,)]
[COMMIT_OK] affected=1
```

---

## Archivos modificados recientemente (claves)

| Archivo | Cambio |
|---------|--------|
| `tool/server.py` | `_exec_autocommit` usa conexión directa con autocommit + verificación post-UPDATE |
| `lib/core/auth/session_controller.dart` | Logs en `existeOperador`, `verificarPin`, `registrarOperador` |
| `lib/features/auth/presentation/login_screen.dart` | Debounce 300ms + logs en `_verificarNombreExistente` y `_submit` |
| `lib/features/validacion/data/validacion_providers.dart` | Provider `entradasPendientesProvider` con invalidación |
| `lib/features/validacion/presentation/validacion_screen.dart` | Usa provider + `ref.invalidate` tras validar/eliminar |

---

## Qué NO tocar (ya funciona)
- Migración de BD (completada)
- Tunnel Cloudflare + Gist (funciona)
- Compilación Linux/Android (en CI)
- Optimizaciones de rendimiento Lotes A/B/C (commiteadas)

---

## Contacto
Si algo no está claro, revisa `graphify-out/` o pregunta al usuario.