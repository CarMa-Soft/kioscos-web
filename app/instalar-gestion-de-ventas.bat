@echo off
chcp 65001 >nul
title Instalar Gestion de ventas
powershell -NoProfile -ExecutionPolicy Bypass -Command "$l = Get-Content -LiteralPath '%~f0' -Encoding UTF8; $i = [array]::IndexOf($l, '#POWERSHELL'); Invoke-Expression (($l | Select-Object -Skip ($i + 1)) -join [Environment]::NewLine)"
echo.
pause
exit /b
#POWERSHELL
# Instalador de Gestión de ventas para Windows (lo descarga la app: menú → Instalar la app, o Ajustes → Impresión).
# Crea el acceso directo "Gestión de ventas" en el Escritorio y en el menú Inicio: abre la app en su propia ventana de
# Chrome (o Edge), con un perfil aparte (así la opción vale aunque haya otro Chrome abierto) y --kiosk-printing, que
# imprime los tickets directo en la impresora predeterminada de Windows, sin la ventana de impresión.
# No instala programas ni toca la configuración de Windows. Para desinstalar: borrar los accesos directos y la carpeta
# %LOCALAPPDATA%\GestionVentas.
$ErrorActionPreference = 'Stop'
try {
  $url = 'https://carma-soft.github.io/kioscos-web/'
  $base = Join-Path $env:LOCALAPPDATA 'GestionVentas'
  $perfil = Join-Path $base 'Chrome'
  New-Item -ItemType Directory -Force -Path $base | Out-Null

  $navegadores = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
  )
  $nav = $navegadores | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $nav) { throw 'No se encontró Google Chrome ni Microsoft Edge. Instalá Google Chrome y volvé a ejecutar el instalador.' }

  # el ícono de la app (si no se puede bajar, queda el del navegador)
  $icono = Join-Path $base 'icono.ico'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri ($url + 'img/icono.ico') -OutFile $icono
  } catch { $icono = "$nav,0" }

  $shell = New-Object -ComObject WScript.Shell
  $accesos = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gestión de ventas.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Gestión de ventas.lnk')
  )
  foreach ($a in $accesos) {
    $lnk = $shell.CreateShortcut($a)
    $lnk.TargetPath = $nav
    $lnk.Arguments = "--kiosk-printing --user-data-dir=`"$perfil`" --no-first-run --no-default-browser-check --app=${url}?pc=1"
    $lnk.WorkingDirectory = $base
    $lnk.IconLocation = $icono
    $lnk.Description = 'Gestión de ventas'
    $lnk.Save()
  }

  $pred = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object Default | Select-Object -First 1
  $impresora = if ($pred) { $pred.Name } else { '(ninguna)' }
  Write-Host ''
  Write-Host ' Listo: Gestión de ventas quedó instalada.' -ForegroundColor Green
  Write-Host ' Abrila siempre con el acceso directo "Gestión de ventas" del Escritorio o del menú Inicio.'
  Write-Host ' La primera vez hay que entrar con la cuenta del negocio (después la recuerda).'
  Write-Host ''
  Write-Host (' Los tickets salen directo en la impresora predeterminada de Windows: ' + $impresora) -ForegroundColor Yellow
  Write-Host ' Si no es la de tickets: Configuración de Windows > Impresoras, desactivá "Permitir que Windows administre'
  Write-Host ' mi impresora predeterminada" y poné la de tickets como predeterminada.'
  # el mismo aviso en una ventana, para que no pase desapercibido
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show("Gestión de ventas quedó instalada: abrila siempre con el ícono `"Gestión de ventas`" del Escritorio o del menú Inicio (la primera vez, con la cuenta del negocio).`n`nLos tickets van a salir directo en la impresora predeterminada de Windows:`n`n      $impresora`n`nSi no es la de tickets: Configuración de Windows > Impresoras, desactivá `"Permitir que Windows administre mi impresora predeterminada`" y poné la de tickets como predeterminada.", 'Gestión de ventas', 'OK', 'Information')
} catch {
  Write-Host ''
  Write-Host (' No se pudo instalar: ' + $_.Exception.Message) -ForegroundColor Red
  try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('No se pudo instalar: ' + $_.Exception.Message, 'Gestión de ventas', 'OK', 'Error') } catch { }
}
