#!/usr/bin/env pwsh
# Instala el Android SDK command-line tools y los componentes minimos
# necesarios para compilar FieldCheck en Android.
#
# Uso:  pwsh -File tool/setup_android_sdk.ps1
#
# La instalacion vive FUERA del repositorio (en el SDK dir estandar de
# Windows) para no contaminar el control de versiones.

$ErrorActionPreference = 'Stop'
# La barra de progreso de Invoke-WebRequest hace la descarga ~5x mas lenta.
$ProgressPreference = 'SilentlyContinue'

$SdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$ZipUrl  = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
$ZipPath = Join-Path $env:TEMP 'android-cmdline-tools.zip'
$Extract = Join-Path $env:TEMP 'android-cmdline-tools'

function Write-Step($msg) { Write-Host "[fieldcheck] $msg" }

Write-Step "SDK root: $SdkRoot"

# --- 1. Descargar command-line tools ---------------------------------------
if (-not (Test-Path (Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'))) {
    Write-Step 'Descargando command-line tools...'
    if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
    Expand-Archive -Path $ZipPath -DestinationPath $Extract -Force

    # El zip trae cmdline-tools/ en la raiz; hay que moverlo a cmdline-tools/latest
    $Target = Join-Path $SdkRoot 'cmdline-tools\latest'
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    Copy-Item -Path (Join-Path $Extract 'cmdline-tools\*') -Destination $Target -Recurse -Force
    Write-Step 'command-line tools instalados.'
} else {
    Write-Step 'command-line tools ya presentes.'
}

$sdkmanager = Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'

# --- 2. Aceptar licencias ---------------------------------------------------
Write-Step 'Aceptando licencias...'
$yes = 1..20 | ForEach-Object { 'y' }
$yes | & $sdkmanager --licenses | Out-Null
Write-Step 'Licencias aceptadas.'

# --- 3. Componentes requeridos ---------------------------------------------
$packages = @(
    'platform-tools'
    'platforms;android-36'
    'build-tools;36.0.0'
)

Write-Step "Instalando: $($packages -join ', ')"
& $sdkmanager $packages

if ($LASTEXITCODE -ne 0) {
    Write-Step "sdkmanager devolvio codigo $LASTEXITCODE (puede ser parcial)."
}

# --- 4. Configurar Flutter -------------------------------------------------
Write-Step 'Registrando el SDK en Flutter...'
& flutter config --android-sdk $SdkRoot | Out-Null

Write-Step 'Listo. Verifica con: flutter doctor'