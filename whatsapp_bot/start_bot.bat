@echo off
setlocal
title WhatsApp Bot - Lycoris

set BOT_DIR=C:\Users\ADMINISTRACION02\Documents\APP REID\whatsapp_bot

taskkill /F /IM node.exe >nul 2>&1
taskkill /F /IM cloudflared.exe >nul 2>&1

echo [1/3] Instalando dependencias...
cd /d "%BOT_DIR%"
call npm install --production >nul 2>&1

echo [2/3] Iniciando servidor...
start /b "" node "%BOT_DIR%\server.js"

echo [3/3] Iniciando tunnel y guardando URL...
node "%BOT_DIR%\start_tunnel.js"

pause
