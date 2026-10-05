<#
.SYNOPSIS
    Uruchamiany WEWNĄTRZ maszyny wirtualnej z 32-bitowym Windows. Wysyła HPGL do plotera
    GCC Jaguar II przez zainstalowany tam oryginalny sterownik GCC (drukarka Windows,
    dane typu RAW, czyli bez przetwarzania przez sterownik).

.EXAMPLE
    guest-plot.ps1 -Test                      # kwadrat testowy 30x30 mm
    guest-plot.ps1 -File C:\projekt.plt       # wyślij plik
    guest-plot.ps1 -Watch                     # wysyłaj pliki zapisywane w \\VBOXSVR\Ploter
    guest-plot.ps1 -ListPrinters              # pokaż drukarki
#>
param(
    [switch]$Test,
    [string]$File,
    [switch]$Watch,
    [switch]$ListPrinters,
    [string]$Printer,
    [string]$Folder = "\\VBOXSVR\Ploter",
    [double]$SizeMm = 30
)

# Zgodne z PowerShell 2.0 (Windows 7) i nowszymi.
$ErrorActionPreference = "Stop"
$PlotExtensions = @(".plt", ".hpgl", ".hpg", ".hgl", ".prn")

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class RawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOCINFO {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr handle);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int StartDocPrinter(IntPtr handle, int level, [In] DOCINFO doc);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndDocPrinter(IntPtr handle);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr handle);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr handle);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr handle, byte[] data, int count, out int written);

    public static void Send(string printer, string docName, byte[] data) {
        IntPtr h;
        if (!OpenPrinter(printer, out h, IntPtr.Zero))
            throw new Exception("Nie mogę otworzyć drukarki '" + printer + "' (błąd " + Marshal.GetLastWin32Error() + ")");
        try {
            DOCINFO doc = new DOCINFO();
            doc.pDocName = docName;
            doc.pDataType = "RAW";
            if (StartDocPrinter(h, 1, doc) == 0)
                throw new Exception("StartDocPrinter: błąd " + Marshal.GetLastWin32Error());
            try {
                StartPagePrinter(h);
                int written;
                if (!WritePrinter(h, data, data.Length, out written) || written != data.Length)
                    throw new Exception("WritePrinter: błąd " + Marshal.GetLastWin32Error());
                EndPagePrinter(h);
            } finally {
                EndDocPrinter(h);
            }
        } finally {
            ClosePrinter(h);
        }
    }
}
"@

function Get-PrinterNames {
    @(Get-WmiObject Win32_Printer | ForEach-Object { $_.Name })
}

function Resolve-Plotter {
    if ($Printer) { return $Printer }
    $names = Get-PrinterNames
    $match = @($names | Where-Object { $_ -match "GCC|Jaguar" })
    if ($match.Count -ge 1) { return $match[0] }
    Write-Host "Nie znalazłem drukarki GCC. Zainstalowane drukarki:" -ForegroundColor Yellow
    $names | ForEach-Object { Write-Host "  $_" }
    throw "Zainstaluj sterownik GCC albo podaj nazwę: -Printer `"nazwa drukarki`""
}

function ConvertTo-Hpgl([string]$text) {
    # Usuwa znaki spoza ASCII, dokłada inicjalizację i odłożenie narzędzia na końcu.
    $clean = [regex]::Replace($text, "[^\x1b\x03\r\n\t\x20-\x7e]", "").Trim()
    if (-not $clean.ToUpper().StartsWith("IN")) { $clean = "IN;" + $clean }
    if (-not $clean.EndsWith(";")) { $clean += ";" }
    $tail = $clean.ToUpper()
    if ($tail.Length -gt 20) { $tail = $tail.Substring($tail.Length - 20) }
    if (-not $tail.Contains("SP0")) { $clean += "PU;SP0;" }
    return $clean + "`r`n"
}

function Send-Hpgl([string]$printerName, [string]$name, [string]$hpgl) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($hpgl)
    [RawPrinter]::Send($printerName, $name, $bytes)
    Write-Host ("  wysłano {0} B do '{1}'" -f $bytes.Length, $printerName)
}

function Read-PlotFile([string]$path) {
    $raw = [System.IO.File]::ReadAllBytes($path)
    return ConvertTo-Hpgl ([System.Text.Encoding]::GetEncoding(28591).GetString($raw))
}

function Get-TestPattern([double]$size) {
    $u = 40   # jednostek HPGL na milimetr
    $o = 10 * $u
    $s = [int]($size * $u)
    $c = $o + [int]($s / 2)
    $a = [int]([Math]::Min(5, $size / 4) * $u)
    return "IN;SP1;PU$o,$o;PD$($o+$s),$o,$($o+$s),$($o+$s),$o,$($o+$s),$o,$o;" +
           "PU$($c-$a),$c;PD$($c+$a),$c;PU$c,$($c-$a);PD$c,$($c+$a);PU0,0;SP0;`r`n"
}

if ($ListPrinters) {
    Get-PrinterNames | ForEach-Object { Write-Host $_ }
    return
}

$plotter = Resolve-Plotter
Write-Host "Ploter: $plotter"

if ($Test) {
    Write-Host "Wysyłam kwadrat testowy $SizeMm mm..."
    Send-Hpgl $plotter "Test plotera" (Get-TestPattern $SizeMm)
    Write-Host "Jeśli ploter wyciął kwadrat - wszystko działa."
}

if ($File) {
    Write-Host "Wysyłam $File..."
    Send-Hpgl $plotter (Split-Path $File -Leaf) (Read-PlotFile $File)
}

if ($Watch) {
    if (-not (Test-Path $Folder)) {
        throw "Brak folderu $Folder. Czy dodatki gościa VirtualBox są zainstalowane, a folder Ploter udostępniony?"
    }
    $done = Join-Path $Folder "wyslane"
    if (-not (Test-Path $done)) { New-Item -ItemType Directory -Path $done | Out-Null }
    Write-Host "Obserwuję $Folder - zapisane tam pliki $($PlotExtensions -join ', ') trafią do plotera."
    Write-Host "Na swoim komputerze zapisuj je do C:\Ploter. Ctrl+C kończy."
    $sizes = @{}
    while ($true) {
        foreach ($item in @(Get-ChildItem -Path $Folder | Where-Object { -not $_.PSIsContainer })) {
            if ($PlotExtensions -notcontains $item.Extension.ToLower()) { continue }
            # wysyłamy dopiero, gdy rozmiar przestał się zmieniać (zapis zakończony)
            if ($sizes[$item.FullName] -ne $item.Length) { $sizes[$item.FullName] = $item.Length; continue }
            Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $item.Name)
            try {
                Send-Hpgl $plotter $item.Name (Read-PlotFile $item.FullName)
                $target = Join-Path $done ((Get-Date -Format "yyyyMMdd-HHmmss-") + $item.Name)
                Move-Item -Path $item.FullName -Destination $target
            } catch {
                Write-Host "  błąd: $($_.Exception.Message)" -ForegroundColor Red
            }
            $sizes.Remove($item.FullName)
        }
        Start-Sleep -Seconds 1
    }
}

if (-not ($Test -or $File -or $Watch)) {
    Write-Host "Podaj -Test, -File <plik> albo -Watch (szczegóły: Get-Help $PSCommandPath)."
}
