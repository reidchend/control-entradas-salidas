# =====================================================================
# Registra arranque automatico de los servicios en Windows
# =====================================================================
# Ejecutar como Administrador (PowerShell):
#   powershell -ExecutionPolicy Bypass -File registrar_autostart.ps1
#
# Crea tareas programadas que se ejecutan al iniciar el equipo:
#   - LycorisServidor8501  : tool/server.py sirviendo la web de inventario
#   - LycorisServidor8502  : tool/server.py sirviendo el POS
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

foreach ($p in @($python, $server)) {
    if (-not (Test-Path $p)) {
        throw "No se encontro: $p`nEjecuta crear_estructura.bat primero."
    }
}
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

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

foreach ($puerto in 8501, 8502) {
    $log = Join-Path $logDir "server$puerto.log"
    # Se envuelve en `cmd /c` porque schtasks desarma mal un /TR con comillas
    # sueltas, y de paso redirige stdout a un archivo: corriendo como SYSTEM
    # no hay consola donde ver la salida, y sin log un servicio caido es
    # indistinguible de uno sano.
    $cmd = "cmd /c `"`"$python`" `"$server`" $puerto >> `"$log`" 2>&1`""
    $nombre = "LycorisServidor$puerto"
    Registrar-Tarea -Nombre $nombre -Comando $cmd
    Write-Host "    -> $nombre" -ForegroundColor Green
    Write-Host "       log: $log" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Para probarlas sin reiniciar:" -ForegroundColor Cyan
Write-Host "  schtasks /Run /TN LycorisServidor8501" -ForegroundColor Gray
Write-Host "  schtasks /Run /TN LycorisServidor8502" -ForegroundColor Gray
Write-Host ""
Write-Host "Si algo falla, el detalle queda en:" -ForegroundColor Cyan
Write-Host "  tool\logs\server8501.log" -ForegroundColor Gray
Write-Host "  tool\logs\server8502.log" -ForegroundColor Gray
Write-Host ""
Write-Host "Para eliminarlas:" -ForegroundColor Cyan
Write-Host "  schtasks /Delete /TN LycorisServidor8501 /F" -ForegroundColor Gray
Write-Host "  schtasks /Delete /TN LycorisServidor8502 /F" -ForegroundColor Gray
Write-Host ""
Write-Host "Tareas registradas. Se inician solas con el equipo." -ForegroundColor Green
Write-Host ""
Write-Host "Nota: Tailscale debe estar conectado para que las apps puedan" -ForegroundColor Yellow
Write-Host "alcanzar la base. Ver README.md de esta carpeta." -ForegroundColor Yellow
