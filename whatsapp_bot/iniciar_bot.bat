@echo off
REM =====================================================================
REM Levanta el bot de WhatsApp y su tunel. Para arranque automatico.
REM =====================================================================
REM Diferencias con start_bot.bat, que es el launcher historico:
REM   - No hace `taskkill /F /IM node.exe` ni de cloudflared.exe. Eso mataba
REM     TODOS los procesos Node de la maquina; en una PC que ademas corre
REM     otros servicios es un footgun.
REM   - No abre `pause`, asi que puede correr como tarea programada.
REM   - No abre el navegador: corriendo como SYSTEM no hay sesion
REM     interactiva. La URL se publica sola en el Gist.
REM
REM La carpeta `auth/` guarda la sesion de WhatsApp. Sin ella hay que
REM escanear un QR de nuevo.

setlocal enabledelayedexpansion
cd /d "%~dp0"

REM GITHUB_TOKEN se necesita para publicar la URL del tunel en el Gist.
if not exist ".env" (
    echo ERROR: falta .env con GITHUB_TOKEN.
    echo   Copialo desde la PC anterior o crealo con: GITHUB_TOKEN=ghp_xxx
    exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%a in (".env") do set "%%a=%%b"

if not exist "cloudflared.exe" (
    echo ERROR: falta cloudflared.exe en esta carpeta.
    echo   Descargalo de https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
    exit /b 1
)
if not exist "node_modules" (
    echo [bot] Instalando dependencias...
    call npm install --production
    if errorlevel 1 (
        echo ERROR: fallo npm install.
        exit /b 1
    )
)
if not exist "auth" (
    echo AVISO: no existe la carpeta auth. Habra que escanear un QR de WhatsApp.
)

REM Espera a que haya Internet. Como tarea ONSTART se dispara al prender
REM la maquina, cuando la red todavia puede no estar lista; si cloudflared
REM arranca sin red muere y start_tunnel.js hace process.exit, dejando el bot
REM caido sin reintentar.
set "RED=0"
for /l %%i in (1,1,30) do (
    ping -n 1 -w 1000 1.1.1.1 >nul 2>&1
    if not errorlevel 1 (
        set "RED=1"
        goto :red_lista
    )
    echo [bot] Sin red todavia... (%%i/30)
    timeout /t 2 >nul
)

:red_lista
if "%RED%"=="1" goto :con_red
echo [bot] ERROR: sin Internet. cloudflared no puede levantar el tunel.
echo [bot] Reintenta con: schtasks /Run /TN LycorisBotWhatsapp
exit /b 1

:con_red
echo [bot] Red disponible.

echo [bot] Iniciando servidor en el puerto 3000...
start "Bot Servidor" /b node server.js

REM El tunel corre aparte: es quien detecta la URL y la sube al Gist.
REM Se espera a que el servidor levante para no apuntar el tunel al vacio.
timeout /t 3 >nul
echo [bot] Iniciando tunel...
start "Bot Tunel" /b node start_tunnel.js

echo [bot] Bot y tunel lanzados. Mivilos con: tasklist ^| findstr node
endlocal
