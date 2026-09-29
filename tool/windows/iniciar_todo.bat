@echo off
REM =====================================================================
REM Levanta la stack local para trabajar en la PC servidor.
REM =====================================================================
REM Inicia, en este orden:
REM   1. Tailscale (si esta instalado) - sin el, las apps no llegan a la BD
REM   2. tool/server.py en 8501 (web de inventario)
REM   3. tool/server.py en 8502 (POS)
REM
REM Para el arranque automatico al prender el equipo usar
REM registrar_autostart.ps1 en vez de este script.

setlocal enabledelayedexpansion
cd /d "%~dp0..\.."
REM enabledelayedexpansion es necesario: el bloque else ( ... ) se parsea
REM entero antes de ejecutarse, asi que %TSIP% se expandiria a vacio. Con
REM !TSIP! el valor se resuelve en el momento de la ejecucion.
set "TSIP="

echo.
echo [1/3] Verificando Tailscale...
where tailscale >nul 2>nul
if errorlevel 1 (
    echo       AVISO: Tailscale no esta instalado o no esta en el PATH.
    echo       Las apps Windows/Android NO van a poder conectarse a la base.
) else (
    REM `tailscale ip -4` imprime solo la IPv4. Parsear `tailscale status`
    REM con FOR /F dependeria del formato de cada columna y es fragil.
    for /f "usebackq delims=" %%i in (`tailscale ip -4 2^>nul`) do set "TSIP=%%i"
    if not defined TSIP (
        echo       Tailscale desconectado. Intentando conectar...
        tailscale up
        for /f "usebackq delims=" %%i in (`tailscale ip -4 2^>nul`) do set "TSIP=%%i"
    ) else (
        echo       Tailscale conectado.
    )
    if defined TSIP (
        echo       IP Tailscale: !TSIP!
        echo       ^<-- esta es la que va en Ajustes -^> Sistema -^> Configurar conexion.
    ) else (
        echo       No se pudo obtener la IP de Tailscale. Revisa la conexion.
    )
)

echo.
echo [2/3] Iniciando servidor web de inventario (8501)...
start "Lycoris 8501" /min "tool\venv\Scripts\python.exe" "tool\server.py" 8501 "build\web"

echo [3/3] Iniciando POS (8502)...
start "Lycoris 8502" /min "tool\venv\Scripts\python.exe" "tool\server.py" 8502 "build\pos"

echo.
echo Esperando 3 segundos para que levanten...
timeout /t 3 >nul

echo.
echo Estado:
curl -s -o nul -w "  8501 (inventario): HTTP %%{http_code}`n" http://localhost:8501/
curl -s -o nul -w "  8502 (POS):        HTTP %%{http_code}`n" http://localhost:8502/

echo.
echo Si ambos responden 200, la stack local esta operativa.
echo Para el bot de WhatsApp: start_bot.bat dentro de whatsapp_bot\
endlocal
