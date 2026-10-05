<#
.SYNOPSIS
    Uruchamiany WEWNĄTRZ maszyny wirtualnej z 32-bitowym Windows. Wysyła HPGL do plotera
    GCC Jaguar II:
      - prosto do sterownika trybu "GCC USB" (\\.\EZNUS0, instaluje go gccusd\zainstaluj-sterownik.ps1),
      - albo przez drukarkę GCC w Windows (dane typu RAW), jeśli jest zainstalowana.
    Domyślnie używa sterownika gccusd, gdy jest dostępny.

.EXAMPLE
    guest-plot.ps1 -Test                      # kwadrat testowy 30x30 mm
    guest-plot.ps1 -File C:\projekt.plt       # wyślij plik
    guest-plot.ps1 -Watch                     # wysyłaj pliki zapisywane w \\VBOXSVR\Ploter
    guest-plot.ps1 -ListPrinters              # pokaż drukarki
    guest-plot.ps1 -Test -Device \\.\EZNUS0    # wymuś wysyłanie prosto do sterownika gccusd
#>
param(
    [switch]$Test,
    [string]$File,
    [switch]$Watch,
    [switch]$ListPrinters,
    [string]$Printer,
    [string]$Device,
    [string]$Folder = "\\VBOXSVR\Ploter",
    [double]$SizeMm = 30
)

# Zgodne z PowerShell 2.0 (Windows 7) i nowszymi.
$ErrorActionPreference = "Stop"
$PlotExtensions = @(".plt", ".hpgl", ".hpg", ".hgl", ".prn")

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class RawDevice {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr security,
                                    uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(IntPtr handle, byte[] data, int count, out int written, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    const uint GENERIC_WRITE = 0x40000000;
    const uint SHARE_READ_WRITE = 3;
    const uint OPEN_EXISTING = 3;
    static readonly IntPtr INVALID = new IntPtr(-1);

    public static bool Exists(string path) {
        IntPtr h = CreateFile(path, GENERIC_WRITE, SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == INVALID) return false;
        CloseHandle(h);
        return true;
    }

    // Sterownik gccusd.sys zamienia WriteFile na transfer bulk USB do plotera.
    public static void Send(string path, byte[] data) {
        IntPtr h = CreateFile(path, GENERIC_WRITE, SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == INVALID)
            throw new Exception("Nie mogę otworzyć " + path + " (błąd " + Marshal.GetLastWin32Error() + ")");
        try {
            int offset = 0;
            while (offset < data.Length) {
                int count = Math.Min(4096, data.Length - offset);
                byte[] chunk = new byte[count];
                Array.Copy(data, offset, chunk, 0, count);
                int written;
                if (!WriteFile(h, chunk, count, out written, IntPtr.Zero))
                    throw new Exception("WriteFile: błąd " + Marshal.GetLastWin32Error());
                if (written <= 0)
                    throw new Exception("Ploter nie przyjął danych");
                offset += written;
            }
        } finally {
            CloseHandle(h);
        }
    }
}

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
    if ($Device) { return $Device }
    if ($Printer) { return $Printer }
    foreach ($i in 0..3) {
        $path = "\\.\EZNUS$i"
        if ([RawDevice]::Exists($path)) { return $path }
    }
    $names = Get-PrinterNames
    $match = @($names | Where-Object { $_ -match "GCC|Jaguar" })
    if ($match.Count -ge 1) { return $match[0] }
    Write-Host "Nie znalazłem drukarki GCC. Zainstalowane drukarki:" -ForegroundColor Yellow
    $names | ForEach-Object { Write-Host "  $_" }
    throw "Nie znalazłem ani sterownika gccusd (uruchom gccusd\zainstaluj-sterownik.ps1), ani drukarki GCC (-Printer `"nazwa`")"
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
    if ($printerName.StartsWith("\\.\")) {
        [RawDevice]::Send($printerName, $bytes)
    } else {
        [RawPrinter]::Send($printerName, $name, $bytes)
    }
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
