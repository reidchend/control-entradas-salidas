# =====================================================================
# Diagnostico: por que PostgreSQL no puede cargar pg_hba.conf
# =====================================================================
# PowerShell como Administrador:
#   powershell -ExecutionPolicy Bypass -File tool\windows\diagnosticar_pg_hba.ps1
#
# NO modifica nada. Solo mira y muestra evidencia.

param([string]$PgVersion = '18')

$pgRoot = "C:\Program Files\PostgreSQL\$PgVersion"
$hbaFile = Join-Path $pgRoot 'data\pg_hba.conf'
$confFile = Join-Path $pgRoot 'data\postgresql.conf'
$psql = Join-Path $pgRoot 'bin\psql.exe'
$logDir = Join-Path $pgRoot 'data\log'

Write-Host "=== 1. Primeros bytes de pg_hba.conf ===" -ForegroundColor Cyan
$bytes = [System.IO.File]::ReadAllBytes($hbaFile)
Write-Host "  Tamano: $($bytes.Length) bytes"
Write-Host "  Primeros 8 bytes: $((($bytes[0..7] | ForEach-Object { $_.ToString('X2') }) -join ' '))"
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "  >>> TIENE BOM UTF-8 al inicio. PostgreSQL lo rechaza." -ForegroundColor Red
} else {
    Write-Host "  Sin BOM. OK." -ForegroundColor Green
}

# Valida como UTF-8 estricto. Un byte suelto (0xE1 de un acento en
# Windows-1252) hace fallar el decode, y ese es el sospechoso principal.
try {
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    $null = $strict.GetString($bytes)
    Write-Host "  UTF-8 valido: SI" -ForegroundColor Green
} catch {
    Write-Host "  >>> NO es UTF-8 valido: $($_.Exception.Message)" -ForegroundColor Red
    $bad = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -ge 0x80) {
            $bad++
            if ($bad -le 5) {
                Write-Host "      byte no-ASCII en offset ${i}: 0x$($bytes[$i].ToString('X2'))" -ForegroundColor Yellow
            }
        }
    }
    Write-Host "      Total de bytes no-ASCII: $bad" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 2. Las primeras lineas de pg_hba.conf ===" -ForegroundColor Cyan
Get-Content $hbaFile -TotalCount 12 -Encoding UTF8 | ForEach-Object {
    Write-Host "  | $_" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== 3. Encoding de la base ===" -ForegroundColor Cyan
$env:PGPASSWORD = Read-Host '  Contraseña de postgres' -AsSecureString | ForEach-Object {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($_)
    $v = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    $v
}
& $psql -U postgres -d postgres -tAc "SELECT datname, pg_encoding_to_char(encoding) FROM pg_database;" 2>&1 |
    ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
$env:PGPASSWORD = $null

Write-Host ""
Write-Host "=== 4. Ultimas lineas del log de PostgreSQL ===" -ForegroundColor Cyan
$log = Get-ChildItem "$logDir\*.log" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime | Select-Object -Last 1
if ($log) {
    Write-Host "  $($log.FullName)" -ForegroundColor Gray
    Get-Content $log.FullName -Tail 12 | ForEach-Object { Write-Host "  | $_" -ForegroundColor Gray }
} else {
    Write-Host "  No se encontro log. Revisar 'C:\Program Files\PostgreSQL\$PgVersion\data\log'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 5. Respaldo disponible ===" -ForegroundColor Cyan
if (Test-Path "$hbaFile.bak") {
    Write-Host "  pg_hba.conf.bak existe, $( (Get-Item "$hbaFile.bak").Length ) bytes" -ForegroundColor Green
} else {
    Write-Host "  >>> NO hay respaldo. Habria que reconfigurar a mano." -ForegroundColor Red
}
