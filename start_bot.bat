@echo off
chcp 65001 >nul
echo === WhatsApp Bot - Inicio ===

set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot
set NGROK=%BOT_DIR%\ngrok.exe

REM 1. Matar instancias previas
echo Cerrando instancias previas...
taskkill /F /IM node.exe 2>nul
taskkill /F /IM ngrok.exe 2>nul
timeout /t 2 /nobreak >nul

REM 2. Configurar authtoken ngrok (solo primera vez)
if not exist "%BOT_DIR%\.ngrok.yml" (
    echo Configurando ngrok...
    "%NGROK%" config add-authtoken 3DBp3i1YC9T67o212BCZbjAxRUN_EhB2S5wq4Y1oDsbKS4Lo
)

REM 3. Iniciar ngrok
echo Iniciando ngrok...
start /b "%NGROK%" http --domain=opt-dazzling-elves.ngrok-free.dev 3000
timeout /t 5 /nobreak >nul

REM 4. Abrir navegador con QR
start https://opt-dazzling-elves.ngrok-free.dev/qr

REM 5. Iniciar bot
cd /d "%BOT_DIR%"
echo.
echo === Instalando dependencias ===
call npm install
if %errorlevel% neq 0 (
    echo [ERROR] npm install fallo
    pause
    exit /b 1
)

echo === Iniciando servidor ===
node server.js
if %errorlevel% neq 0 (
    echo [ERROR] node server.js fallo
    pause
    exit /b 1
)
