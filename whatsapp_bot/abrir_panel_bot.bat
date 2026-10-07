@echo off
REM =====================================================================
REM Abre el panel del bot ya apuntando a la URL vigente y con el token
REM puesto. Evita copiar y pegar la URL cada vez que el tunel cambia.
REM =====================================================================
REM Como funciona, y por que asi:
REM
REM   1. Lee WHATSAPP_BOT_TOKEN del .env de esta misma carpeta. El navegador
REM      no puede leer archivos locales: por eso esto va en un .bat y no
REM      dentro de la pagina. El .bat si puede, y le pasa el token al panel.
REM
REM   2. Descubre la URL del bot con la misma idea que usa la app para la
REM      base de datos: la lee del Gist (bot_url.json), que el tunel publica
REM      en cada arranque. Si el Gist no responde, usa la ultima URL buena
REM      que guardo; si tampoco hay, cae a localhost:3000. Asi el panel no
REM      depende de que el tunel haya quedado en la misma URL de antes.
REM
REM   3. Abre {url}/panel con el token en el #fragmento. El fragmento no
REM      viaja al servidor, asi que el token no queda en los logs del bot
REM      ni en los del proxy, a diferencia de pasarlo como ?token=.
REM
REM Para abrir un servidor puntual sin tocar el Gist:
REM     abrir_panel_bot.bat https://otra-url.trycloudflare.com
REM =====================================================================

setlocal enabledelayedexpansion
title Panel del Bot - Lycoris
cd /d "%~dp0"

REM LOCALAPPDATA puede faltar si esto se lanza como servicio.
if not defined LOCALAPPDATA set "LOCALAPPDATA=%TEMP%"

set "GIST_RAW=https://gist.githubusercontent.com/reidchend/5b37693a243d8d2235eea0647396b8d3/raw/bot_url.json"
set "CACHE=%LOCALAPPDATA%\LycorisBot\panel_url.txt"

REM ---- 1. Token del .env (mismo patron que iniciar_bot.bat) ----
set "TOKEN="
if exist ".env" (
    for /f "usebackq tokens=1,* delims==" %%a in (".env") do (
        if /i "%%a"=="WHATSAPP_BOT_TOKEN" set "TOKEN=%%b"
    )
)
if not defined TOKEN (
    echo [panel] ERROR: no encontre WHATSAPP_BOT_TOKEN en "%CD%\.env".
    echo [panel] Revisa que exista la linea:  WHATSAPP_BOT_TOKEN=tu_token
    pause
    exit /b 1
)

REM ---- 2. URL del bot ----
REM El argumento opcional gana: sirve para apuntar a otro servidor a mano.
set "ORIGEN=manual"
set "URL=%~1"
if defined URL goto :normalizar

set "ORIGEN=Gist"
set "TMPURL=%TEMP%\lycoris_boturl_%RANDOM%%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { $r = Invoke-RestMethod -Uri '%GIST_RAW%' -TimeoutSec 8; if ($r -and $r.url) { $r.url } } catch { }" > "%TMPURL%" 2>nul
if exist "%TMPURL%" set /p URL=<"%TMPURL%"
del "%TMPURL%" >nul 2>&1

REM Si algo intercepta la respuesta, el Gist puede devolver cualquier cosa:
REM solo se acepta si es una URL https, igual que hace la app.
if defined URL (
    echo(!URL!| findstr /b /i /c:"https://" >nul
    if errorlevel 1 set "URL="
)
if not defined URL set "ORIGEN=nada"

if not defined URL (
    if exist "%CACHE%" (
        set /p URL=<"%CACHE%"
        set "ORIGEN=cache"
    )
)
if not defined URL (
    set "URL=http://localhost:3000"
    set "ORIGEN=localhost"
    echo [panel] AVISO: no pude leer el Gist - sin red o GitHub bloqueado -
    echo [panel] y no tenia URL guardada. Abro localhost:3000.
)

:normalizar
if "!URL:~-1!"=="/" set "URL=!URL:~0,-1!"

REM Guardar la URL del Gist como respaldo para la proxima vez sin red.
if /i "!ORIGEN!"=="Gist" (
    if not exist "%LOCALAPPDATA%\LycorisBot" mkdir "%LOCALAPPDATA%\LycorisBot" >nul 2>&1
    >"%CACHE%" echo(!URL!
)

echo [panel] URL del bot (!ORIGEN!): !URL!
echo [panel] Abriendo el panel...
start "" "!URL!/panel#token=!TOKEN!"

endlocal
