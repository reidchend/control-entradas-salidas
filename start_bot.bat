@echo off
chcp 65001 >nul
echo === WhatsApp Bot - Inicio ===

set ZROK=C:\Users\ADMINISTRACION02\Documents\zrok2.exe
set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot

REM 1. Eliminar shares corruptos/viejos
echo Limpiando shares zrok...
"%ZROK%" delete share lycorys-control 2>nul
"%ZROK%" delete share lycoris-bot 2>nul
"%ZROK%" delete environment 2>nul

REM 2. Enable zrok
"%ZROK%" enable 2>nul

REM 3. Crear share nuevo
echo Creando share lycoris-bot...
"%ZROK%" share public 3000 --unique-name lycoris-bot

REM 4. Abrir navegador con QR
start https://lycoris-bot.shares.zrok.io/qr

REM 5. Iniciar bot
cd /d "%BOT_DIR%"
npm install
node server.js
