# =====================================================================
# Configura PostgreSQL para servir a la app Control Entradas/Salidas
# =====================================================================
# Ejecutar como Administrador (PowerShell):
#   powershell -ExecutionPolicy Bypass -File configurar_postgres.ps1 `
#       -DbPassword "CONTRASENA_FUERTE" -DbName "control_entradas"
#
# Qué hace:
#   1. Parchea postgresql.conf para escuchar en la red.
#   2. Parchea pg_hba.conf para aceptar scram-sha-256 SOLO desde el rango
#      de Tailscale (100.64.0.0/10). Nunca desde 0.0.0.0/0.
#   3. Abre el puerto 5432 en el firewall de Windows, restringido al mismo
#      rango. Sin esto la app no conecta aunque todo lo demás esté bien.
#   4. Crea el rol de la app y la base, y la deja propietaria.
#   5. Reinicia el servicio.
#
# Idempotente: se puede volver a ejecutar sin romper nada.

param(
    [Parameter(Mandatory = $true)]
    [string]$DbPassword,
    [string]$DbName = 'control_entradas',
    [string]$DbUser = 'control_app',
    [string]$PgVersion = '18',
    [string]$SuperUser = 'postgres',
    # Rango de Tailscale. No ampliar: es la barrera que impide que el puerto
    # 5432 sea alcanzable desde la LAN o internet.
    [string]$TrustedSubnet = '100.64.0.0/10',
    [int]$Port = 5432
)

$ErrorActionPreference = 'Stop'

# psql.exe se invoca por ruta completa, así que el código de salida es
# confiable aunque otro psql esté en el PATH.
function Invoke-Psql {
    param(
        [string[]]$Arguments,
        [string]$InputText = $null
    )
    if ($null -ne $InputText) {
        $InputText | & $psql @Arguments | Out-Host
    } else {
        & $psql @Arguments | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        throw "psql falló (código $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

# Set-Content en Windows PowerShell 5.1 escribe ASCII, lo que destruye los
# acentos de los comentarios de los .conf. Se escribe explícito en UTF-8
# sin BOM, que es lo que PostgreSQL espera.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-TextFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Este script debe ejecutarse como Administrador.'
    }
}

Assert-Admin

$pgRoot = "C:\Program Files\PostgreSQL\$PgVersion"
$dataDir = Join-Path $pgRoot 'data'
$confFile = Join-Path $dataDir 'postgresql.conf'
$hbaFile = Join-Path $dataDir 'pg_hba.conf'
$binDir = Join-Path $pgRoot 'bin'
$psql = Join-Path $binDir 'psql.exe'
$serviceName = "postgresql-x64-$PgVersion"

foreach ($f in @($confFile, $hbaFile, $binDir, $psql)) {
    if (-not (Test-Path $f)) {
        throw "No se encontró: $f`n¿PostgreSQL está instalado en la ruta esperada?"
    }
}

# --- 0. Contraseña del superusuario ---------------------------------
# Se pide una sola vez, oculta, y se exporta a PGPASSWORD para que psql no
# quede esperando un prompt que no puede leer (su stdin está en pipe).
Write-Host "[0/5] Contraseña del superusuario '$SuperUser'..." -ForegroundColor Cyan
$secure = Read-Host "  Contraseña de $SuperUser" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

# --- 1. postgresql.conf: escuchar en la red -------------------------
Write-Host "[1/5] Configurando listen_addresses..." -ForegroundColor Cyan
$backup = "$confFile.bak"
if (-not (Test-Path $backup)) { Copy-Item $confFile $backup }

$conf = [System.IO.File]::ReadAllText($confFile)
# '*' escucha en todas las interfaces; el firewall de Windows y el rango
# de Tailscale en pg_hba son los que filtran el acceso real.
# Se exige un valor numérico para no pisar otra tecla que empiece por "port".
$conf = [regex]::Replace(
    $conf, "(?m)^\s*#?\s*listen_addresses\s*=.*$", "listen_addresses = '*'")
$conf = [regex]::Replace(
    $conf, "(?m)^\s*#?\s*port\s*=\s*\d+.*$", "port = $Port")
Write-TextFile -Path $confFile -Value $conf

# --- 2. pg_hba.conf: solo Tailscale --------------------------------
Write-Host "[2/5] Configurando pg_hba.conf (solo $TrustedSubnet)..." -ForegroundColor Cyan
$hbaBackup = "$hbaFile.bak"
if (-not (Test-Path $hbaBackup)) { Copy-Item $hbaFile $hbaBackup }

# Marcador para reemplazar el bloque en re-ejecuciones.
$begin = '# >>> control-entradas-app >>>'
$end = '# <<< control-entradas-app <<<'

$block = @"
$begin
# Generado por configurar_postgres.ps1
# Solo clientes Tailscale. NO ampliar a 0.0.0.0/0.
host    all             all             $TrustedSubnet        scram-sha-256
$end
"@

$hba = [System.IO.File]::ReadAllText($hbaFile)
# Quita el bloque previo si existe (re-ejecución).
$hba = [regex]::Replace($hba, "(?ms)^$begin.*?^$end\r?\n?", '')
# Las reglas por defecto de Postgres quedan intactas: local por socket y
# loopback. El bloque de la app se antepone para que coincida primero.
$hba = $block + "`r`n" + $hba
Write-TextFile -Path $hbaFile -Value $hba

# --- 3. Firewall de Windows ----------------------------------------
# Sin esta regla la app no conecta: Windows bloquea por defecto el tráfico
# entrante a 5432. Se restringe al rango de Tailscale, igual que pg_hba.
Write-Host "[3/5] Abriendo puerto $Port en el firewall (solo Tailscale)..." -ForegroundColor Cyan
$ruleName = "PostgreSQL $Port (Tailscale)"
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -RemoteAddress $TrustedSubnet `
    -Profile Any | Out-Null

# --- 4. Rol y base de datos ----------------------------------------
Write-Host "[4/5] Creando rol '$DbUser' y base '$DbName'..." -ForegroundColor Cyan

$safePass = $DbPassword.Replace("'", "''")
$safeUser = $DbUser.Replace("'", "''")
$safeName = $DbName.Replace("'", "''")

# El `$$` del bloque DO se escapa con backtick para que PowerShell no intente
# interpolarlo; las variables sí deben interpolarse.
$sql = @"
DO `$`$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$safeUser') THEN
    CREATE ROLE ""$safeUser"" LOGIN PASSWORD '$safePass';
  ELSE
    ALTER ROLE ""$safeUser"" WITH LOGIN PASSWORD '$safePass';
  END IF;
END
`$`$;
"@

Invoke-Psql -Arguments @('-U', $SuperUser, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1') `
    -InputText $sql

$exists = & $psql -U $SuperUser -d postgres -tAc `
    "SELECT 1 FROM pg_database WHERE datname = '$safeName'"
if ($LASTEXITCODE -ne 0) { throw "Falló la consulta de existencia de la base." }
if (($exists | Out-String).Trim() -ne '1') {
    Invoke-Psql -Arguments @('-U', $SuperUser, '-d', 'postgres', '-c',
        "CREATE DATABASE ""$safeName"" OWNER ""$safeUser"" ENCODING 'UTF8'")
    Write-Host "      Base creada." -ForegroundColor Green
} else {
    Write-Host "      La base ya existía." -ForegroundColor Yellow
}

Invoke-Psql -Arguments @('-U', $SuperUser, '-d', $DbName, '-c',
    "GRANT ALL ON SCHEMA public TO ""$safeUser""")
Invoke-Psql -Arguments @('-U', $SuperUser, '-d', $DbName, '-c',
    "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ""$safeUser""")

# --- 5. Reiniciar el servicio --------------------------------------
Write-Host "[5/5] Reiniciando servicio PostgreSQL..." -ForegroundColor Cyan
Restart-Service -Name $serviceName -Force
Start-Sleep -Seconds 3

$env:PGPASSWORD = $null

$state = (Get-Service -Name $serviceName).Status
Write-Host ""
Write-Host "Servicio PostgreSQL: $state" -ForegroundColor Green
Write-Host ""
Write-Host "listen_addresses:" -ForegroundColor Gray
Select-String -Path $confFile -Pattern '^\s*listen_addresses' | ForEach-Object { "  $($_.Line)" }
Write-Host "pg_hba (regla de la app):" -ForegroundColor Gray
Select-String -Path $hbaFile -Pattern '100\.64|control-entradas-app' | ForEach-Object { "  $($_.Line)" }
Write-Host "Firewall:" -ForegroundColor Gray
Write-Host "  $ruleName -> TCP $Port desde $TrustedSubnet" -ForegroundColor Gray
Write-Host ""
Write-Host "Verificacion (deberia dar una linea con la IP de Tailscale):" -ForegroundColor Cyan
Write-Host "  tailscale ip -4" -ForegroundColor Gray
Write-Host ""
Write-Host "Siguiente paso: crear_estructura.bat" -ForegroundColor Cyan
