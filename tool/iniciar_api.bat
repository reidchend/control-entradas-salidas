@echo off
REM =====================================================================
REM Levanta la API de base de datos y su tunel de Cloudflare. Para arranque
REM automatico.
REM =====================================================================
REM Se apoya en tool\iniciar_tunnel_api.js, que publica la URL del tunel en el
REM Gist para que las apps Windows y Android la descubran solas y el usuario
REM solo tenga que escribir el token.
REM
REM Diferencias con iniciar_todo.bat, que solo levanta las dos webs:
REM   - Espera a que el servidor RESPONDA en vez de a que pase un tiempo fijo.
REM     Con un timeout fijo el tunel puede apuntar a un puerto donde todavia
REM     no escucha nadie, y la app se conecta a un 502.
REM   - Verifica que el venv tenga psycopg_pool. Sin ese extra el server.py
REM     arranca igual y contesta 503 en cada consulta, que es un fallo
REM     dificil de encontrar despues.
REM   - No abre `pause`, asi que puede correr como tarea programada.

setlocal enabledelayedexpansion
cd /d "%~dp0"

if "%API_PORT%"=="" set "API_PORT=8501"
set "PY=venv\Scripts\python.exe"
set "TUNEL=iniciar_tunnel_api.js"
set "ENVLOCAL=..\.env.local"

if not exist "%ENVLOCAL%" (
    echo ERROR: no existe %ENVLOCAL%.
    echo   Copialo desde .env.local.example y cargale la contrasena y el token.
    exit /b 1
)
findstr /B /C:"PROXY_SQL_TOKEN=" "%ENVLOCAL%" >NUL 2>&1
if errorlevel 1 (
    echo ERROR: %ENVLOCAL% no define PROXY_SQL_TOKEN.
    echo   Sin el, /proxy-sql responde 401 a todas las apps.
    exit /b 1
)

if not exist "%PY%" (
    echo ERROR: falta %PY%.
    echo   Crealo con:  python -m venv tool\venv
    echo   Y despues:   %PY% -m pip install -r requirements.txt
    exit /b 1
)

REM El venv puede existir incompleto. Probar los imports es la unica forma de
REM saberlo antes de que falle con la base andando.
"%PY%" -c "import psycopg, psycopg_pool" >NUL 2>&1
if errorlevel 1 (
    echo ERROR: al venv le faltan dependencias.
    echo   Corre:  %PY% -m pip install -r requirements.txt
    exit /b 1
)

REM cloudflared puede estar en el PATH (winget) o junto al bot. El launcher lo
REM resuelve solo; esto es para fallar antes de lanzar nada.
where cloudflared >NUL 2>&1
if not errorlevel 1 goto :cloudflared_ok
if exist "..\whatsapp_bot\cloudflared.exe" goto :cloudflared_ok
if exist "..\whatsapp_bot\cloudflared" goto :cloudflared_ok
echo ERROR: no se encuentra cloudflared.
echo   Instalalo con:  winget install --id Cloudflare.cloudflared
exit /b 1

:cloudflared_ok
echo [api] Entorno OK (puerto !API_PORT!).

REM Espera a que haya Internet: como tarea ONSTART se dispara al prender la
REM maquina, cuando la red todavia puede no estar lista, y sin esto cloudflared
REM arranca sin conexion y muere sin reintentar.
set "RED=0"
for /l %%i in (1,1,30) do (
    ping -n 1 -w 1000 1.1.1.1 >NUL 2>&1
    if not errorlevel 1 (
        set "RED=1"
        goto :red_lista
    )
    echo [api] Sin red todavia... (%%i/30)
    timeout /t 2 >NUL
)

:red_lista
if "!RED!"=="1" goto :con_red
echo [api] ERROR: sin Internet. El tunel no puede levantar.
echo [api] Reintenta con: schtasks /Run /TN LycorisApi
exit /b 1

:con_red
echo [api] Red disponible.

echo [api] Iniciando servidor en el puerto !API_PORT!...
start "Lycoris API" /b "%PY%" "server.py" !API_PORT!

REM curl sale con codigo 7 (connection refused) si no hay nadie escuchando, y
REM con 0 ante cualquier respuesta HTTP. Con eso alcanza: no hace falta
REM mandar un POST ni leer el codigo de respuesta, y asi el cuerpo JSON no
REM arrastra el escapado de comillas de cmd.
set "LISTO=0"
for /l %%i in (1,1,30) do (
    curl -s -o NUL "http://localhost:!API_PORT!/proxy-sql"
    if not errorlevel 1 (
        set "LISTO=1"
        goto :servidor_listo
    )
    echo [api] Esperando al servidor... (%%i/30)
    timeout /t 1 >NUL
)

:servidor_listo
if "!LISTO!"=="1" goto :con_servidor
echo [api] ERROR: el servidor no respondio en el puerto !API_PORT!.
echo [api] Probalo a mano:  %PY% server.py !API_PORT!
exit /b 1

:con_servidor
echo [api] Servidor respondiendo.

echo [api] Iniciando tunel y publicando la URL en el Gist...
start "Lycoris Tunel API" /b node "%TUNEL%"

echo [api] API y tunel lanzados.
echo [api]   Procesos:  tasklist ^| findstr /i "python node cloudflared"
echo [api]   Probar:    curl -X POST http://localhost:!API_PORT!/proxy-sql -H "X-Proxy-Token: EL_TOKEN" -d ...
endlocal
