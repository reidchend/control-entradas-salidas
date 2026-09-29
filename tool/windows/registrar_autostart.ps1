# =====================================================================
# Registra arranque automatico de los servicios en Windows
# =====================================================================
# Ejecutar como Administrador (PowerShell):
#   powershell -ExecutionPolicy Bypass -File registrar_autostart.ps1
#
# Crea tareas programadas que se ejecutan al iniciar el equipo:
#   - LycorisApi            : tool/iniciar_api.bat = server.py en 8501 + tunel
#   - LycorisServidor8502   : tool/server.py sirviendo la web del POS
#
# Requiere que .env.local tenga DATABASE_URL apuntando a la base local y
# que el bot de WhatsApp se registre aparte (ver README.md de esta carpeta).

param(
    [string]$RepoPath = '',
    [string]$TaskUser = 'SYSTEM'
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Este script debe ejecutarse como Administrador.'
    }
}

Assert-Admin

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$RepoPath = (Resolve-Path $RepoPath).Path

$python = Join-Path $RepoPath 'tool\venv\Scripts\python.exe'
$server = Join-Path $RepoPath 'tool\server.py'
$logDir = Join-Path $RepoPath 'tool\logs'
$botDir = Join-Path $RepoPath 'whatsapp_bot'
$botLauncher = Join-Path $botDir 'iniciar_bot.bat'

foreach ($p in @($python, $server)) {
    if (-not (Test-Path $p)) {
        throw "No se encontro: $p`nEjecuta crear_estructura.bat primero."
    }
}
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# El bot es opcional: la base de datos no depende de el, y en una PC nueva
# todavia puede no estar migrado. Se avisa y se sigue.
$botDisponible = $false
if (Test-Path $botLauncher) {
    if (-not (Test-Path (Join-Path $botDir '.env'))) {
        Write-Host "AVISO: falta whatsapp_bot\.env (GITHUB_TOKEN). El bot no se registrara." -ForegroundColor Yellow
    } elseif (-not (Test-Path (Join-Path $botDir 'auth'))) {
        Write-Host "AVISO: falta whatsapp_bot\auth. El bot arranca pero habra que" -ForegroundColor Yellow
        Write-Host "       escanear un QR de WhatsApp." -ForegroundColor Yellow
    } else {
        $botDisponible = $true
    }
} else {
    Write-Host "AVISO: no se encontro whatsapp_bot\iniciar_bot.bat. Solo se registran los servidores." -ForegroundColor Yellow
}

# schtasks viene con Windows: evita depender de NSSM o de otro servicio.
function Registrar-Tarea {
    param([string]$Nombre, [string]$Comando)
    Write-Host "  registrando $Nombre..." -ForegroundColor Cyan
    # schtasks no sobreescribe: se borra la previa si existe.
    schtasks /Query /TN $Nombre *> $null
    if ($LASTEXITCODE -eq 0) {
        schtasks /Delete /TN $Nombre /F *> $null
    }
    schtasks /Create /TN $Nombre /TR $Comando /SC ONSTART /RU $TaskUser /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "No se pudo crear la tarea $Nombre" }
}

Write-Host "Repo: $RepoPath" -ForegroundColor Gray
Write-Host "Usuario de ejecucion: $TaskUser" -ForegroundColor Gray
Write-Host ""

$nombres = @()

# ---------------------------------------------------------------------------
# API de base de datos: servidor en 8501 + tunel, en una sola tarea.
#
# Antes eran dos tareas sueltas (LycorisServidor8501 y LycorisTunelApi) y
# ambas se disparan en paralelo al prender la maquina: el tunel podia
# empezar antes de que el servidor escuchara, y la app se conectaba a un 502.
# iniciar_api.bat espera a que el puerto responda antes de levantar el tunel.
# ---------------------------------------------------------------------------
$apiLauncher = Join-Path $RepoPath 'tool\iniciar_api.bat'
if (Test-Path $apiLauncher) {
    $apiLog = Join-Path $logDir 'api.log'
    $cmd = "cmd /c `"`"$apiLauncher`" >> `"$apiLog`" 2>&1`""
    $nombre = 'LycorisApi'
    Registrar-Tarea -Nombre $nombre -Comando $cmd
    $nombres += $nombre
    Write-Host "    -> $nombre (servidor 8501 + tunel + Gist)" -ForegroundColor Green
    Write-Host "       log: $apiLog" -ForegroundColor Gray
}

# server.py lee el puerto en argv[1] y el directorio web en argv[2], relativo
# a la raiz del repo. Si se omite argv[2] usa build/web, asi que sin esto el
# POS (8502) serviria el build de inventario.
$webPorPuerto = @{ 8502 = 'build\pos' }

foreach ($puerto in 8502) {
    $log = Join-Path $logDir "server$puerto.log"
    $web = $webPorPuerto[$puerto]
    # Se envuelve en `cmd /c` porque schtasks desarma mal un /TR con comillas
    # sueltas, y de paso redirige stdout a un archivo: corriendo como SYSTEM
    # no hay consola donde ver la salida, y sin log un servicio caido es
    # indistinguible de uno sano.
    $cmd = "cmd /c `"`"$python`" `"$server`" $puerto `"$web`" >> `"$log`" 2>&1`""
    $nombre = "LycorisServidor$puerto"
    Registrar-Tarea -Nombre $nombre -Comando $cmd
    $nombres += $nombre
    Write-Host "    -> $nombre" -ForegroundColor Green
    Write-Host "       puerto $puerto, web $web" -ForegroundColor Gray
    Write-Host "       log: $log" -ForegroundColor Gray
}

if ($botDisponible) {
    $botLog = Join-Path $logDir 'bot.log'
    # El bot no depende de Postgres (publica su URL en un Gist), asi que no
    # necesita esperar a la base. iniciar_bot.bat si espera a que haya red.
    $cmd = "cmd /c `"`"$botLauncher`" >> `"$botLog`" 2>&1`""
    $nombre = 'LycorisBotWhatsapp'
    Registrar-Tarea -Nombre $nombre -Comando $cmd
    $nombres += $nombre
    Write-Host "    -> $nombre (bot + tunel)" -ForegroundColor Green
    Write-Host "       log: $botLog" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Para probarlas sin reiniciar:" -ForegroundColor Cyan
foreach ($n in $nombres) {
    Write-Host "  schtasks /Run /TN $n" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Si algo falla, el detalle queda en:" -ForegroundColor Cyan
foreach ($log in (Get-ChildItem $logDir -Filter *.log -ErrorAction SilentlyContinue)) {
    Write-Host "  $($log.FullName)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Tarea vieja (ya no se usa, se puede borrar):" -ForegroundColor Cyan
Write-Host "  schtasks /Delete /TN LycorisTunelApi /F" -ForegroundColor Gray
Write-Host "  schtasks /Delete /TN LycorisServidor8501 /F" -ForegroundColor Gray
Write-Host ""
Write-Host "Tareas registradas. Se inician solas con el equipo." -ForegroundColor Green
Write-Host ""
Write-Host "Nota: con el tunel API andando, las apps NO necesitan Tailscale:" -ForegroundColor Yellow
Write-Host "van por HTTPS y descubren la URL solas. Tailscale solo hace falta" -ForegroundColor Yellow
Write-Host "para administrar la PC servidor." -ForegroundColor Yellow
