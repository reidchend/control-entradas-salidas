@echo off
chcp 65001 >nul
echo === WhatsApp Bot - Inicio ===

set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot
set ZROK=%BOT_DIR%\zrok.exe

REM 1. Eliminar shares corruptos/viejos
echo Limpiando shares zrok...
"%ZROK%" delete share lycorys-control 2>nul
"%ZROK%" delete share lycoris-bot 2>nul
"%ZROK%" delete environment 2>nul
timeout /t 3 /nobreak >nul

REM 2. Enable zrok
echo Habilitando zrok...
"%ZROK%" enable
if %errorlevel% neq 0 (
    echo [ERROR] zrok enable fallo
    pause
    exit /b 1
)

REM 3. Crear share nuevo
echo Creando share lycoris-bot...
"%ZROK%" share public http://127.0.0.1:3000 --backend-mode proxy --unique-name lycoris-bot
if %errorlevel% neq 0 (
    echo [ERROR] zrok share fallo
    pause
    exit /b 1
)

REM 4. Abrir navegador con QR
start https://lycoris-bot.shares.zrok.io/qr

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
