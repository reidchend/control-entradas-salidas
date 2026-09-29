# =====================================================================
# Abre los puertos de la app en el firewall de Windows
# =====================================================================
# Ejecutar como Administrador (PowerShell):
#   powershell -ExecutionPolicy Bypass -File configurar_firewall.ps1
#
# Por que hace falta esto ademas del 5432
# -------------------------------------------
# Windows bloquea por defecto todo el trafico entrante. PostgreSQL alcanza
# porque configurar_postgres.ps1 abre el 5432, pero los puertos web (8501 y
# 8502) no tienen ninguna regla, asi que hoy la app web es inalcanzable
# desde cualquier equipo, ni siquiera desde la red local.
#
# POR QUE LAS REGLAS ESTAN RESTRINGIDAS A TAILSCALE Y NO A LA RED LOCAL
# ---------------------------------------------------------------------
# `tool/server.py` expone `/proxy-sql`, que ejecuta SQL arbitrario con las
# credenciales del servidor y NO pide autenticacion. Quien alcance el puerto
# 8501 o 8502 puede correr `DROP TABLE productos` desde un navegador sin
# tener ninguna clave.
#
# Por eso estas reglas solo aceptan trafico de 100.64.0.0/10 (Tailscale):
# unicamente los equipos con la app instalada ylogueados a tu tailnet.
#
# Si genuinamente necesitas que el POS se use desde un navegador de la red
# local, NO abras el puerto a la LAN sin resolver antes la autenticacion de
# /proxy-sql. Ver la seccion de abajo.

param(
    [string]$TrustedSubnet = '100.64.0.0/10',
    [int[]]$AppPorts = 8501, 8502
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

Write-Host "Abriendo puertos $($AppPorts -join ', ') desde $TrustedSubnet" -ForegroundColor Cyan
Write-Host ""

foreach ($puerto in $AppPorts) {
    $ruleName = "Lycoris App $puerto (Tailscale)"

    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $puerto `
        -RemoteAddress $TrustedSubnet `
        -Profile Any | Out-Null

    Write-Host "  [OK] $ruleName -> TCP $puerto desde $TrustedSubnet" -ForegroundColor Green
}

Write-Host ""
Write-Host "Reglas de firewall:" -ForegroundColor Gray
Get-NetFirewallRule -DisplayName 'Lycoris*' |
    Select-Object DisplayName, Enabled, Direction, Action |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host "Como llegar a la app web desde un equipo con Tailscale:" -ForegroundColor Cyan
Write-Host "  http://<IP-TAILSCALE-DE-ESTA-PC>:8501   (inventario)" -ForegroundColor Gray
Write-Host "  http://<IP-TAILSCALE-DE-ESTA-PC>:8502   (POS)" -ForegroundColor Gray
Write-Host ""
Write-Host "La IP la imprime: tailscale ip -4" -ForegroundColor Gray

Write-Host ""
Write-Host "Sobre abrirlo a la red local" -ForegroundColor Yellow
Write-Host "  /proxy-sql no tiene autenticacion. Exponer 8501/8502 a la LAN" -ForegroundColor Yellow
Write-Host "  permitiria ejecutar SQL arbitrario a cualquiera de la red." -ForegroundColor Yellow
Write-Host "  Antes de hacerlo, hay que agregar un token compartido al proxy." -ForegroundColor Yellow
