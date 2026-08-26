@echo off
chcp 65001 >nul
echo === WhatsApp Bot - Inicio ===

set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot

REM 1. Matar instancias previas
echo Cerrando instancias previas...
taskkill /F /IM node.exe 2>nul
timeout /t 2 /nobreak >nul

REM 2. Abrir navegador con QR
start https://lycoris-bot.serveo.net/qr

REM 3. Iniciar bot Node.js
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
start /b node server.js
timeout /t 3 /nobreak >nul

REM 4. Iniciar tunnel SSH serveo
echo === Iniciando tunnel serveo ===
echo URL: https://lycoris-bot.serveo.net
ssh -o StrictHostKeyChecking=accept-new -R lycoris-bot:80:localhost:3000 serveo.net
