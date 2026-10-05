<#
.SYNOPSIS
    Uruchamiany WEWNĄTRZ 32-bitowej maszyny wirtualnej. Wyjmuje oryginalny sterownik GCC trybu
    "GCC USB" (gccusd.sys) z instalatora GCC 2.39-01 lub 2.17-01, sprawdza jego sumę SHA-256
    i instaluje go dla plotera Jaguar II (USB\VID_0F0B&PID_0002) razem z plikiem gccusd.inf.

.PARAMETER Installer
    Ścieżka do Cutter_Plotter_driver_USB_V2.39-01.exe (albo V2.17-01). Bez niej skrypt
    szuka pliku w Pobranych, na Pulpicie i w \\VBOXSVR\Ploter.
#>
param([string]$Installer)

$ErrorActionPreference = "Stop"
$Target = "C:\GCCUSD"
$SysSha256 = "015BF34BDE0AD6C62C8242407C986EA3FAE332A43C9EDA9B04BC078C68CBCBDA"
$SysSize = 16176

# Znane instalatory GCC: SHA-256 instalatora -> położenie skompresowanego gccusd.sys w pliku.
$KnownInstallers = @{
    "FB44A96A1673345ABE9761BAD33ED521CE75D3CA1B032EB462458F41B74E059D" = 8433575  # V2.39-01
    "798096EFD14363453CAD0E500BF9B0875E01AB1143FBD583929B48614EF4E0DA" = 7396688  # V2.17-01
}

function Write-Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }

if ([Environment]::Is64BitOperatingSystem) {
    throw "To jest 64-bitowy Windows. Sterownik gccusd.sys działa tylko w 32-bitowym - uruchom skrypt w maszynie wirtualnej."
}

Write-Step "Szukam instalatora GCC"
if (-not $Installer) {
    $roots = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "\\VBOXSVR\Ploter") | Where-Object { Test-Path $_ }
    $found = @(foreach ($r in $roots) {
        Get-ChildItem -Path $r -Recurse -Filter "Cutter_Plotter_driver_USB_V2.*.exe" -ErrorAction SilentlyContinue
    })
    if ($found.Count -eq 0) {
        throw "Nie znalazłem Cutter_Plotter_driver_USB_V2.39-01.exe. Rozpakuj ZIP ze sterownikami GCC albo podaj ścieżkę: -Installer C:\...\Cutter_Plotter_driver_USB_V2.39-01.exe"
    }
    $Installer = $found[0].FullName
}
Write-Host "Instalator: $Installer"

$hash = (Get-FileHash -Algorithm SHA256 -Path $Installer).Hash
if (-not $KnownInstallers.ContainsKey($hash)) {
    throw "Nieznana wersja instalatora (SHA-256 $hash). Użyj Cutter_Plotter_driver_USB_V2.39-01.exe z paczki GCC 2.39-01."
}

Write-Step "Wyjmuję gccusd.sys z instalatora"
New-Item -ItemType Directory -Force -Path $Target | Out-Null
$sysPath = Join-Path $Target "gccusd.sys"
$in = [System.IO.File]::OpenRead($Installer)
try {
    $in.Position = $KnownInstallers[$hash]
    $deflate = New-Object System.IO.Compression.DeflateStream($in, [System.IO.Compression.CompressionMode]::Decompress)
    $buffer = New-Object byte[] ($SysSize + 1024)
    $total = 0
    while ($true) {
        $n = $deflate.Read($buffer, $total, $buffer.Length - $total)
        if ($n -le 0) { break }
        $total += $n
        if ($total -ge $buffer.Length) { break }
    }
} finally {
    $in.Close()
}
if ($total -ne $SysSize) { throw "Wyjęty plik ma zły rozmiar ($total B zamiast $SysSize B)." }
$bytes = New-Object byte[] $SysSize
[Array]::Copy($buffer, $bytes, $SysSize)
[System.IO.File]::WriteAllBytes($sysPath, $bytes)
$sysHash = (Get-FileHash -Algorithm SHA256 -Path $sysPath).Hash
if ($sysHash -ne $SysSha256) {
    Remove-Item $sysPath
    throw "Suma kontrolna gccusd.sys się nie zgadza ($sysHash) - przerywam."
}
Write-Host "gccusd.sys OK (SHA-256 zgodna z oryginałem GCC)"
Copy-Item -Force (Join-Path $PSScriptRoot "gccusd.inf") $Target

Write-Step "Instaluję sterownik"
Write-Host "Jeśli Windows zapyta o niezweryfikowanego wydawcę, wybierz 'Zainstaluj oprogramowanie sterownika mimo to'."
& pnputil.exe /add-driver (Join-Path $Target "gccusd.inf") /install
Start-Sleep -Seconds 3

Write-Step "Sprawdzam ploter"
$device = Get-PnpDevice | Where-Object { $_.InstanceId -match "VID_0F0B&PID_0002" -and $_.Present } | Select-Object -First 1
if (-not $device) {
    Write-Host "Nie widzę plotera. Sprawdź w oknie maszyny: Urządzenia -> USB -> ploter zaznaczony." -ForegroundColor Yellow
    return
}
$service = (Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_Service).Data
Write-Host ("Ploter: {0}, sterownik: {1}, stan: {2}" -f $device.FriendlyName, $service, $device.Status)

if ($service -ne "gccusd") {
    Write-Host ""
    Write-Host "Windows nie podmienił sterownika sam. Zrób to ręcznie:" -ForegroundColor Yellow
    Write-Host " 1. Menedżer urządzeń -> prawy klik na ploterze ($($device.FriendlyName)) -> Aktualizuj sterownik"
    Write-Host " 2. Przeglądaj mój komputer -> Pozwól mi wybrać z listy -> Z dysku... -> Przeglądaj"
    Write-Host " 3. Wskaż $Target\gccusd.inf -> OK -> 'GCC Jaguar II (GCC USB)' -> Dalej"
    Write-Host " 4. Na ostrzeżenie o wydawcy: 'Zainstaluj mimo to'"
    Write-Host " 5. Uruchom ten skrypt ponownie, żeby sprawdzić wynik."
} elseif ($device.Status -ne "OK") {
    Write-Host "Sterownik gccusd jest przypisany, ale urządzenie nie działa (stan: $($device.Status))." -ForegroundColor Red
    Write-Host "Zrób zrzut Menedżera urządzeń -> ploter -> Właściwości -> Ogólne i wyślij go."
} else {
    Write-Host ""
    Write-Host "Sterownik działa. Test cięcia: guest-plot.ps1 -Test (wysyła prosto do \\.\EZNUS0)." -ForegroundColor Green
}
