<#
.SYNOPSIS
    Tworzy maszynę wirtualną VirtualBox z 32-bitowym Windows, do której przekazywany
    jest ploter GCC Jaguar II przez USB. W środku działa oryginalny sterownik GCC,
    który nie działa na 64-bitowym Windows 10/11.

.DESCRIPTION
    Uruchamiaj na swoim (64-bitowym) Windowsie, najlepiej przez setup-vm.bat.
    Skrypt:
      1. instaluje VirtualBox (winget), jeśli go brakuje,
      2. wykrywa ploter na liście urządzeń USB,
      3. tworzy maszynę "Ploter-GCC" (32-bit, 2 GB RAM, dysk 32 GB),
      4. ustawia filtr USB, żeby ploter zawsze trafiał do maszyny,
      5. udostępnia maszynie folder C:\Ploter (w środku: \\VBOXSVR\Ploter),
      6. uruchamia instalację Windows z podanego obrazu ISO (automatycznie, jeśli się da).

.PARAMETER Iso
    Ścieżka do obrazu ISO 32-bitowego Windows 10 (lub 7).
#>
param(
    [string]$Iso,
    [string]$VmName = "Ploter-GCC",
    [string]$SharedFolder = "C:\Ploter",
    [int]$MemoryMB = 2048,
    [int]$DiskGB = 32,
    [string]$VmUser = "ploter",
    [string]$VmPassword = "ploter",
    [switch]$ManualInstall
)

$ErrorActionPreference = "Stop"

function Write-Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }

function Find-VBoxManage {
    $candidates = @()
    if ($env:VBOX_MSI_INSTALL_PATH) { $candidates += (Join-Path $env:VBOX_MSI_INSTALL_PATH "VBoxManage.exe") }
    if ($env:VBOX_INSTALL_PATH) { $candidates += (Join-Path $env:VBOX_INSTALL_PATH "VBoxManage.exe") }
    $candidates += (Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe")
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Invoke-VBox {
    $out = & $script:VBoxManage @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "VBoxManage $($args -join ' ') zakończył się błędem:`n$($out -join "`n")"
    }
    return $out
}

function Get-UsbHostDevices {
    # Parsuje wynik "VBoxManage list usbhost" na listę obiektów.
    $text = (Invoke-VBox list usbhost) -join "`n"
    $devices = @()
    foreach ($block in ($text -split "(?:\r?\n){2,}")) {
        if ($block -notmatch "VendorId") { continue }
        $d = [ordered]@{ VendorId = ""; ProductId = ""; Manufacturer = ""; Product = ""; State = "" }
        foreach ($line in ($block -split "\r?\n")) {
            if ($line -match "^\s*VendorId:\s*0x([0-9a-fA-F]{4})") { $d.VendorId = $Matches[1].ToLower() }
            elseif ($line -match "^\s*ProductId:\s*0x([0-9a-fA-F]{4})") { $d.ProductId = $Matches[1].ToLower() }
            elseif ($line -match "^\s*Manufacturer:\s*(.*)$") { $d.Manufacturer = $Matches[1].Trim() }
            elseif ($line -match "^\s*Product:\s*(.*)$") { $d.Product = $Matches[1].Trim() }
            elseif ($line -match "^\s*Current State:\s*(.*)$") { $d.State = $Matches[1].Trim() }
        }
        if ($d.VendorId) { $devices += [pscustomobject]$d }
    }
    return $devices
}

function Format-Device($d) {
    $name = ("$($d.Manufacturer) $($d.Product)").Trim()
    if (-not $name) { $name = "(bez nazwy)" }
    return "$name  [VID $($d.VendorId), PID $($d.ProductId)]"
}

function Select-Plotter {
    $all = @(Get-UsbHostDevices)
    $match = @($all | Where-Object { "$($_.Manufacturer) $($_.Product)" -match "GCC|Jaguar|Cutter|Plotter" })
    if ($match.Count -eq 1) {
        Write-Host "Znaleziono: $(Format-Device $match[0])"
        $ok = Read-Host "Czy to ploter? [T/n]"
        if ($ok -notmatch "^[nN]") { return $match[0] }
    }

    # Pewna metoda: porównanie listy urządzeń przed podłączeniem plotera i po nim.
    Write-Host ""
    Write-Host "Wykryjemy ploter, porównując listę urządzeń USB."
    Read-Host "Wyjmij kabel USB z plotera (albo wyłącz ploter) i naciśnij Enter"
    $before = @(Get-UsbHostDevices | ForEach-Object { "$($_.VendorId):$($_.ProductId)" })
    Read-Host "Podłącz ploter kablem USB, włącz go, odczekaj 10 sekund i naciśnij Enter"
    $after = @(Get-UsbHostDevices)
    $new = @($after | Where-Object { $before -notcontains "$($_.VendorId):$($_.ProductId)" })
    if ($new.Count -eq 1) {
        Write-Host "Nowe urządzenie: $(Format-Device $new[0])"
        return $new[0]
    }

    # Ostatnia deska ratunku: wybór z listy.
    Write-Host ""
    Write-Host "Nie udało się jednoznacznie wykryć plotera. Wybierz go z listy:"
    for ($i = 0; $i -lt $after.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), (Format-Device $after[$i])) }
    $n = [int](Read-Host "Numer urządzenia")
    if ($n -lt 1 -or $n -gt $after.Count) { throw "Nieprawidłowy numer." }
    return $after[$n - 1]
}

# ---------------------------------------------------------------- 1. VirtualBox

Write-Step "Sprawdzam VirtualBox"
$script:VBoxManage = Find-VBoxManage
if (-not $script:VBoxManage) {
    Write-Host "VirtualBox nie jest zainstalowany - instaluję przez winget (zatwierdź okno administratora)..."
    winget install --id Oracle.VirtualBox -e --accept-package-agreements --accept-source-agreements
    $script:VBoxManage = Find-VBoxManage
    if (-not $script:VBoxManage) {
        throw "Nie znaleziono VirtualBoxa po instalacji. Zainstaluj go ręcznie z virtualbox.org i uruchom skrypt ponownie."
    }
}
Write-Host "VirtualBox: $(Invoke-VBox --version)"

# ---------------------------------------------------------------- 2. ISO

if (-not $Iso) {
    Write-Host ""
    Write-Host "Potrzebny jest obraz ISO 32-bitowego Windows 10 (najlepiej) albo Windows 7."
    Write-Host "Windows 10: narzędzie Media Creation Tool -> 'Utwórz nośnik instalacyjny' ->"
    Write-Host "odznacz 'Użyj zalecanych opcji' -> Architektura: 32-bitowa (x86) -> Plik ISO."
    $Iso = (Read-Host "Podaj ścieżkę do pliku ISO (możesz przeciągnąć plik do okna)").Trim('"', ' ')
}
if (-not (Test-Path $Iso)) { throw "Nie ma pliku: $Iso" }

# ---------------------------------------------------------------- 3. ploter

Write-Step "Szukam plotera na USB"
$plotter = Select-Plotter

# ---------------------------------------------------------------- 4. folder wspólny

Write-Step "Przygotowuję folder wspólny $SharedFolder"
New-Item -ItemType Directory -Force -Path $SharedFolder | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $SharedFolder "sterownik") | Out-Null
foreach ($f in @("guest-plot.ps1", "guest-plot.bat")) {
    Copy-Item -Force (Join-Path $PSScriptRoot $f) $SharedFolder
}
Write-Host "Wrzuć sterownik GCC do $SharedFolder\sterownik - w maszynie zobaczysz go jako \\VBOXSVR\Ploter\sterownik."

# ---------------------------------------------------------------- 5. maszyna

Write-Step "Tworzę maszynę $VmName"
$existing = (Invoke-VBox list vms) -join "`n"
if ($existing -match [regex]::Escape("`"$VmName`"")) {
    throw "Maszyna $VmName już istnieje. Usuń ją w VirtualBoxie albo podaj inną nazwę: -VmName Ploter-GCC2"
}

$osType = "Windows10"
if ((Split-Path $Iso -Leaf) -match "win(dows)?[ _-]?7") { $osType = "Windows7" }

Invoke-VBox createvm --name $VmName --ostype $osType --register | Out-Null
Invoke-VBox modifyvm $VmName --memory $MemoryMB --vram 64 --cpus 2 --ioapic on `
    --graphicscontroller vboxsvga --audio none --clipboard bidirectional --usbohci on | Out-Null

$vmFolder = Split-Path ((Invoke-VBox showvminfo $VmName --machinereadable |
    Where-Object { $_ -match '^CfgFile=' }) -replace '^CfgFile="(.*)"$', '$1')
$disk = Join-Path $vmFolder "$VmName.vdi"
Invoke-VBox createmedium disk --filename $disk --size ($DiskGB * 1024) --format VDI | Out-Null
Invoke-VBox storagectl $VmName --name SATA --add sata --controller IntelAhci --portcount 2 | Out-Null
Invoke-VBox storageattach $VmName --storagectl SATA --port 0 --device 0 --type hdd --medium $disk | Out-Null

Write-Step "Ustawiam przekazywanie plotera do maszyny"
Invoke-VBox usbfilter add 0 --target $VmName --name "GCC Jaguar II" `
    --vendorid $plotter.VendorId --productid $plotter.ProductId | Out-Null
Write-Host "Filtr USB: VID $($plotter.VendorId), PID $($plotter.ProductId)"

Invoke-VBox sharedfolder add $VmName --name Ploter --hostpath $SharedFolder --automount | Out-Null

# ---------------------------------------------------------------- 6. instalacja Windows

Write-Step "Uruchamiam instalację Windows"
$unattendedOk = $false
if (-not $ManualInstall) {
    try {
        Invoke-VBox unattended install $VmName --iso="$Iso" --user=$VmUser --password=$VmPassword `
            --full-user-name=Ploter --install-additions --locale=pl_PL --country=PL --start-vm=gui | Out-Null
        $unattendedOk = $true
    } catch {
        Write-Host "Automatyczna instalacja się nie udała - przechodzę na ręczną." -ForegroundColor Yellow
        Write-Host $_.Exception.Message
    }
}
if (-not $unattendedOk) {
    Invoke-VBox storageattach $VmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$Iso" | Out-Null
    Invoke-VBox startvm $VmName --type gui | Out-Null
}

Write-Host ""
Write-Host "Gotowe. Co dalej:" -ForegroundColor Green
if ($unattendedOk) {
    Write-Host " 1. Poczekaj, aż Windows w maszynie zainstaluje się sam (kilkadziesiąt minut, kilka restartów)."
    Write-Host "    Login: $VmUser, hasło: $VmPassword"
} else {
    Write-Host " 1. Zainstaluj Windows w oknie maszyny (klucz produktu możesz pominąć)."
    Write-Host "    Potem w menu okna maszyny: Urządzenia -> Wstaw obraz płyty z dodatkami gościa"
    Write-Host "    i zainstaluj VBoxWindowsAdditions z płyty, a następnie zrestartuj maszynę."
}
Write-Host " 2. W maszynie zainstaluj sterownik GCC z \\VBOXSVR\Ploter\sterownik (tak jak na Windows 7)."
Write-Host "    Ploter (kabel USB podłączony) zostanie przekazany do maszyny automatycznie."
Write-Host " 3. W maszynie uruchom \\VBOXSVR\Ploter\guest-plot.bat i wybierz test."
Write-Host " 4. Potem możesz ciąć z GreatCut zainstalowanego w maszynie albo zapisywać pliki .plt"
Write-Host "    na swoim komputerze do $SharedFolder - maszyna wyśle je do plotera."
