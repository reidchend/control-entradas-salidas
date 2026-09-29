# =====================================================================
# Verifica que la PC servidor este lista. NO cambia nada.
# =====================================================================
# PowerShell normal (no hace falta Administrador):
#   powershell -ExecutionPolicy Bypass -File tool\windows\verificar_instalacion.ps1
#
# Devuelve un checklist. Lo que dice [FALTA] hay que hacerlo antes de
# seguir con la fase siguiente.

param(
    [string]$RepoPath = '',
    [string]$DbName = 'control_entradas'
)

$ErrorActionPreference = 'Continue'
$fallos = 0
$avisos = 0

function Ok    { param($m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Falta { param($m) Write-Host "  [FALTA] $m" -ForegroundColor Red; $script:fallos++ }
function Aviso  { param($m) Write-Host "  [AVISO] $m" -ForegroundColor Yellow; $script:avisos++ }
function Titulo { param($m) Write-Host "`n$m" -ForegroundColor Cyan }

Write-Host "Verificando la PC servidor..." -ForegroundColor White

# --- 0. Herramientas base -------------------------------------------------
Titulo "Fase 0 - Herramientas"

$g = Get-Command git -ErrorAction SilentlyContinue
if ($g) { Ok "git $((git --version))" } else { Falta "git no esta instalado" }

$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) { Ok "python $((python --version 2>&1))" }
else { Falta "python no esta en el PATH ( reinstalalo tildando 'Add python.exe to PATH')" }

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) { Ok "node $((node --version))" } else { Aviso "node no esta instalado (solo hace falta para el bot)" }

# --- PostgreSQL -----------------------------------------------------------
Titulo "Fase 0 - PostgreSQL"

$pgSvc = Get-Service -Name 'postgresql-x64-*' -ErrorAction SilentlyContinue
if ($pgSvc) {
    foreach ($s in $pgSvc) {
        if ($s.Status -eq 'Running') { Ok "servicio $($s.Name) en ejecucion" }
        else { Falta "servicio $($s.Name) esta $($s.Status). Inicialo con: Start-Service $($s.Name)" }
    }
} else {
    Falta "no hay ningun servicio postgresql-x64-*. Instalalo (Fase 0.1)"
}

$psql = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
if ($psql) {
    Ok "psql en $($psql.DirectoryName)"
    $pgBin = $psql.DirectoryName
    $pgRoot = Split-Path $pgBin
    $ver = (Split-Path $pgRoot -Leaf)
    if ($ver -ne '18') {
        Aviso "PostgreSQL $ver instalado. Los scripts asumen 18; se puede pasar -PgVersion $ver"
    }
} else {
    Falta "no se encuentra psql.exe bajo C:\Program Files\PostgreSQL"
    $pgBin = $null
}

# --- Tailscale ------------------------------------------------------------
Titulo "Fase 0 - Tailscale"

$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts) { Falta "tailscale no esta instalado" }
else {
    $ip = (tailscale ip -4 2>$null)
    if ($ip) { Ok "conectado, IP $ip" }
    else { Falta "Tailscale instalado pero desconectado. Logueate con: tailscale up" }
}

# --- Fase 1: el repo ------------------------------------------------------
Titulo "Fase 1 - Codigo"

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = Join-Path $PSScriptRoot '..\..'
}
if (-not (Test-Path $RepoPath)) {
    Falta "no existe el repo en $RepoPath"
    $RepoPath = $null
} else {
    $RepoPath = (Resolve-Path $RepoPath).Path
    Ok "repo en $RepoPath"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $head = git -C $RepoPath log -1 --oneline 2>$null
        if ($head) { Ok "HEAD $head" } else { Falta "la carpeta no es un repo git" }
    }
}

# --- Fase 2: la base ------------------------------------------------------
Titulo "Fase 2 - Base de datos"

if ($RepoPath -and $psql) {
    # El script de configuracion es la senal de que la fase 2 corrio.
    $conf = Get-ChildItem 'C:\Program Files\PostgreSQL\*\data\postgresql.conf' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    if ($conf) {
        $listen = Select-String -Path $conf.FullName -Pattern "^\s*listen_addresses\s*=\s*'\*'" -Quiet
        if ($listen) { Ok "postgresql.conf escucha en la red" }
        else { Falta "postgresql.conf no tiene listen_addresses = '*'. Corre configurar_postgres.ps1" }

        $hba = Join-Path $conf.DirectoryName 'pg_hba.conf'
        if (Test-Path $hba) {
            $hbaTxt = Get-Content $hba -Raw
            if ($hbaTxt -match '100\.64\.0\.0/10') { Ok "pg_hba.conf restringido a Tailscale" }
            else { Falta "pg_hba.conf no tiene la regla de Tailscale. Corre configurar_postgres.ps1" }
            if ($hbaTxt -match '(?m)^\s*host.*0\.0\.0\.0/0') {
                Aviso "pg_hba.conf tiene una regla 0.0.0.0/0. Revisala: deja la base abierta."
            }
        }
    }

    $db = $null
    if ($psql) {
        $sql = "SELECT 1 FROM pg_database WHERE datname = '$DbName'"
        $db = (& $psql -U postgres -d postgres -tAc $sql 2>$null)
    }
    if ($db -eq '1') { Ok "base $DbName existe" }
    elseif ($null -eq $db) { Aviso "no se pudo consultar si la base existe (falta PGPASSWORD)" }
    else { Falta "no existe la base $DbName" }

    $venvPy = Join-Path $RepoPath 'tool\venv\Scripts\python.exe'
    if (Test-Path $venvPy) { Ok "entorno Python listo" }
    else { Falta "falta tool\venv. Corre crear_estructura.bat" }

    $envLocal = Join-Path $RepoPath '.env.local'
    if (Test-Path $envLocal) {
        if ((Get-Content $envLocal -Raw) -match 'CAMBIAR_ESTA_CONTRASENA') {
            Falta ".env.local todavia tiene el placeholder de la contrasena"
        } else { Ok ".env.local configurado" }
    } else {
        Falta "falta .env.local (lo crea crear_estructura.bat)"
    }
}

# --- Fase 3: builds web ---------------------------------------------------
Titulo "Fase 3 - Builds web"

if ($RepoPath) {
    foreach ($d in @('build\web', 'build\pos')) {
        $idx = Join-Path (Join-Path $RepoPath $d) 'index.html'
        if (Test-Path $idx) { Ok "$d\index.html presente" }
        else { Falta "falta $d\index.html (el server levanta pero la web da 404)" }
    }
}

# --- Fase 4: bot ----------------------------------------------------------
Titulo "Fase 4 - Bot de WhatsApp"

if ($RepoPath) {
    $bot = Join-Path $RepoPath 'whatsapp_bot'
    if (Test-Path $bot) {
        if (Test-Path (Join-Path $bot '.env')) { Ok "bot\.env presente" }
        else { Falta "falta bot\.env con GITHUB_TOKEN" }
        if (Test-Path (Join-Path $bot 'auth')) { Ok "bot\auth presente (sesion de WhatsApp)" }
        else { Falta "falta bot\auth: habra que escanear un QR de WhatsApp" }
        if (Test-Path (Join-Path $bot 'cloudflared.exe')) { Ok "cloudflared.exe presente" }
        else { Falta "falta cloudflared.exe en la carpeta del bot" }
    } else { Aviso "no hay carpeta whatsapp_bot" }
}

# --- Firewall -------------------------------------------------------------
Titulo "Reglas de firewall"

$rules = Get-NetFirewallRule -DisplayName 'Lycoris*' -ErrorAction SilentlyContinue
$pgRule = Get-NetFirewallRule -DisplayName 'PostgreSQL*' -ErrorAction SilentlyContinue
if ($pgRule) { Ok "regla de PostgreSQL creada" } else { Falta "falta la regla de firewall de PostgreSQL" }
if ($rules) {
    foreach ($r in $rules) { Ok "regla '$($r.DisplayName)'" }
} else {
    Aviso "sin reglas 'Lycoris*'. Las app web (8501/8502) estan inalcanzables"
}

# --- Resultado ------------------------------------------------------------
Write-Host ""
if ($fallos -eq 0 -and $avisos -eq 0) {
    Write-Host "Todo listo." -ForegroundColor Green
} elseif ($fallos -eq 0) {
    Write-Host "Listo con $avisos aviso(s). Podés seguir." -ForegroundColor Yellow
} else {
    Write-Host "Faltan $fallos cosa(s). Revisa lo marcado [FALTA]." -ForegroundColor Red
}
Write-Host ""
