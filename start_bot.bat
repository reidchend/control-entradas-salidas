@echo off
chcp 65001 >nul
echo === WhatsApp Bot - Inicio ===

set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot
set NGROK=%BOT_DIR%\cloudflared.exe

REM 1. Matar instancias previas
echo Cerrando instancias previas...
taskkill /F /IM node.exe 2>nul
taskkill /F /IM cloudflared.exe 2>nul
timeout /t 2 /nobreak >nul

REM 2. Iniciar bot Node.js
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

REM 3. Iniciar cloudflared tunnel
echo === Iniciando cloudflared tunnel ===
echo Copia la URL que apareca abajo y pegala en el navegador:
echo.
"%NGROK%" tunnel --url http://localhost:3000
