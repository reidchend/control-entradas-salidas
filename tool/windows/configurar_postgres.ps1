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
    # Opcional a propósito: si se pasa por línea de comandos queda escrito en
    # ConsoleHost_history.txt para siempre. Mejor prompt interactivo.
    [string]$DbPassword = '',
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

# Los .conf del instalador de PostgreSQL vienen en la página de códigos ANSI
# del Windows (Windows-1252 en una instalación en español), NO en UTF-8.
#
# Leerlos con .NET los decodifica como UTF-8 y cada acento no representable
# se vuelve un caracter de reemplazo U+FFFD. Al reescribir, el archivo queda
# corrupto y PostgreSQL deja de arrancar con "no se pudo cargar pg_hba.conf".
#
# ISO-8859-1 (28591) es el único códec con mapeo 1:1 byte<->char, así que
# ReadAllText/Latin1 + WriteBytes/Latin1 deja los bytes originales intactos
# pase lo que pase. El bloque que agregamos es ASCII puro, válido en
# cualquier codificación.
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)

function Read-RawText {
    param([string]$Path)
    return $Latin1.GetString([System.IO.File]::ReadAllBytes($Path))
}

function Write-RawText {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllBytes($Path, $Latin1.GetBytes($Content))
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

# --- 0b. Contraseña del rol de la app ---------------------------------
# Se pide también oculta, y con confirmación: es la que va a usar la app.
if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    while ($true) {
        Write-Host "[0b/5] Contraseña del rol '$DbUser' (la usará la app)..." -ForegroundColor Cyan
        $p1 = Read-Host '  Contraseña' -AsSecureString
        $p2 = Read-Host '  Repetir' -AsSecureString
        $a = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1)
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
        try {
            $DbPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($a)
            $repeat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($a)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
        }
        if ($DbPassword -eq $repeat -and $DbPassword.Length -ge 8) { break }
        Write-Host "      No coinciden o son muy cortas (minimo 8). De nuevo." -ForegroundColor Yellow
    }
}

# --- Respaldo antes de tocar nada ------------------------------------
# Se crean los dos .bak acá arriba, no en cada paso, para que el `trap` de
# abajo siempre encuentre un respaldo completo. Un pg_hba.conf roto deja la
# base sin aceptar conexiones, así que el fallo tiene que ser reversible.
$backup = "$confFile.bak"
$hbaBackup = "$hbaFile.bak"
foreach ($pair in @(@($confFile, $backup), @($hbaFile, $hbaBackup))) {
    if (-not (Test-Path $pair[1])) { Copy-Item $pair[0] $pair[1] }
}

trap {
    Write-Host ""
    Write-Host "FALLO: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Restaurando postgresql.conf y pg_hba.conf desde los .bak..." -ForegroundColor Yellow
    try {
        Copy-Item $hbaBackup $hbaFile -Force
        Copy-Item $backup $confFile -Force
        Restart-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Write-Host "Configuracion original restaurada. La base deberia volver a responder." -ForegroundColor Green
    } catch {
        Write-Host "LA RESTAURACION FALLO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Copia a mano los .bak que quedaron junto a los .conf originales." -ForegroundColor Red
    }
    $env:PGPASSWORD = $null
    exit 1
}

# --- 1. postgresql.conf: escuchar en la red -------------------------
Write-Host "[1/5] Configurando listen_addresses..." -ForegroundColor Cyan

$conf = Read-RawText -Path $confFile
# '*' escucha en todas las interfaces; el firewall de Windows y el rango
# de Tailscale en pg_hba son los que filtran el acceso real.
# Se exige un valor numérico para no pisar otra tecla que empiece por "port".
$conf = [regex]::Replace(
    $conf, "(?m)^\s*#?\s*listen_addresses\s*=.*$", "listen_addresses = '*'")
$conf = [regex]::Replace(
    $conf, "(?m)^\s*#?\s*port\s*=\s*\d+.*$", "port = $Port")

if ($conf -notmatch "listen_addresses\s*=\s*'\*'") {
    throw 'No se pudo fijar listen_addresses. Se aborta sin escribir.'
}
if ($conf -notmatch "(?m)^\s*port\s*=\s*$Port\s*$") {
    throw "No se pudo fijar el puerto a $Port. Se aborta sin escribir."
}
Write-RawText -Path $confFile -Content $conf

# --- 2. pg_hba.conf: solo Tailscale --------------------------------
Write-Host "[2/5] Configurando pg_hba.conf (solo $TrustedSubnet)..." -ForegroundColor Cyan

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

$hba = Read-RawText -Path $hbaFile
$before = $hba.Length

# Escape por disciplina: los marcadores son texto fijo y no deben depender
# de que sus caracteres sean inofensivos para regex.
$hba = [regex]::Replace($hba,
    "(?ms)^" + [regex]::Escape($begin) + ".*?^" + [regex]::Escape($end) + "\r?\n?", '')

# Barrera de seguridad. NO es la causa del fallo anterior (esa sigue sin
# explicarse), pero un pg_hba.conf que perdió casi todo su contenido deja la
# base entera inaccesible, así que es mejor abortar y dejar que el trap
# restaure el .bak que escribir un archivo que PostgreSQL no va a poder leer.
if ($hba.Length -lt ($before / 2) -or $hba.Length -lt 200) {
    throw "La limpieza del bloque anterior redujo pg_hba.conf de $before a $($hba.Length) bytes. Se aborta sin escribir."
}

# Las reglas por defecto de Postgres quedan intactas: local por socket y
# loopback. El bloque de la app se antepone para que coincida primero.
$newHba = $block + "`r`n" + $hba

# Última barrera antes de tocar disco: un .conf sin reglas de host no sirve.
if ($newHba -notmatch '(?m)^\s*host\s') {
    throw 'El resultado no contiene ninguna regla host. Se aborta sin escribir.'
}
Write-RawText -Path $hbaFile -Content $newHba

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
#
# OJO con las comillas, es la parte mas traicionera de este script:
#
#   - Dentro de un here-string @"..."@ NO hay procesado de escapes, asi que
#     "" NO escapa nada: llega literal y PostgreSQL lo lee como un
#     identificador de largo cero.
#   - Una comilla doble SENCILLA si es literal dentro del here-string, asi
#     que es lo que hay que usar para un identificador delimitado.
#   - Las comillas simples son literales de cadena, no identificadores:
#     CREATE ROLE 'x' es error de sintaxis.
#
# El nombre va sin escapar porque $DbUser es un parametro interno con
# valores fijos; si alguna vez acepta entrada de usuario, hay que
# duplicar las comillas dobles internas (a la PostgreSQL, no a PowerShell).
$sql = @"
DO `$`$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$safeUser') THEN
    CREATE ROLE "$safeUser" LOGIN PASSWORD '$safePass';
  ELSE
    ALTER ROLE "$safeUser" WITH LOGIN PASSWORD '$safePass';
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
$DbPassword = $null

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
