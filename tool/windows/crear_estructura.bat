@echo off
REM =====================================================================
REM Crea la estructura de la base local (esquema) y prepara el entorno
REM Python que usa tool/server.py.
REM =====================================================================
REM Ejecutar en la carpeta del repo, en la PC servidor:
REM   crear_estructura.bat
REM
REM Idempotente: se puede volver a ejecutar.

setlocal
cd /d "%~dp0..\.."

echo.
echo [1/3] Preparando entorno Python para tool/server.py...
if not exist "tool\venv\Scripts\python.exe" (
    echo       Creando virtualenv...
    python -m venv tool\venv
    if errorlevel 1 (
        echo ERROR: no se pudo crear el virtualenv. Verifica que Python este instalado.
        exit /b 1
    )
) else (
    echo       El virtualenv ya existe.
)

echo       Instalando psycopg...
call tool\venv\Scripts\python.exe -m pip install --quiet --upgrade pip
call tool\venv\Scripts\python.exe -m pip install --quiet "psycopg[binary]"
if errorlevel 1 (
    echo ERROR: fallo la instalacion de psycopg.
    exit /b 1
)

echo.
echo [2/3] Definiendo credenciales en .env.local...
if not exist ".env.local" (
    if exist ".env.local.example" (
        copy ".env.local.example" ".env.local" >nul
        echo       Creado desde .env.local.example.
    ) else (
        type nul > ".env.local"
        echo       Creado vacio.
    )
)
echo       Editalo y reemplaza CAMBIAR_ESTA_CONTRASENA por la que usaste
echo       en configurar_postgres.ps1 -DbPassword. Deberia quedar:
echo         DATABASE_URL=postgresql://control_app:TU_CONTRASENA^@localhost:5432/control_entradas?sslmode=disable
echo.

echo [3/3] Creando las tablas en la base local...
REM `set /p` escribe en pantalla lo que se tipea, asi que el prompt va en
REM PowerShell con -AsSecureString: la contrasena no queda visible ni en
REM pantalla ni en el historial del shell.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Read-Host '  Contrasena del superusuario postgres' -AsSecureString; $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }; & 'tool\venv\Scripts\python.exe' 'tool\windows\crear_estructura.py'; exit $LASTEXITCODE"
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
    echo.
    echo ERROR: fallo la creacion de la estructura ^(codigo %RC%^).
    echo   - Si el error es de sintaxis, schema.sql debe ejecutarse ANTES
    echo     que schema_activos.sql (este ultimo usa set_pos_updated_at^).
    echo   - Verifica tambien que la base 'control_entradas' exista.
    exit /b %RC%
)

echo.
echo Listo. Siguiente paso: iniciar_todo.bat
endlocal
