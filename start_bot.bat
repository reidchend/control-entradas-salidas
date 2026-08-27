@echo off
setlocal
title WhatsApp Bot - Lycoris

set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot
set ZROK=%BOT_DIR%\zrok.exe

taskkill /F /IM node.exe >nul 2>&1
taskkill /F /IM zrok.exe >nul 2>&1

echo [1/3] Instalando dependencias...
cd /d "%BOT_DIR%"
call npm install --production >nul 2>&1

echo [2/3] Iniciando servidor...
start /b "" "%BOT_DIR%\node.exe" "%BOT_DIR%\server.js"

echo [3/3] Iniciando zrok...
"%ZROK%" share private http://localhost:3000 -b --headless

pause
