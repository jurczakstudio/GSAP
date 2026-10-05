# Ploter GCC Jaguar II przez USB, bez zakupów (VirtualBox)

Oryginalny sterownik GCC USB działa tylko na 32-bitowym Windows. Zamiast zmieniać system,
uruchamiamy 32-bitowy Windows w maszynie wirtualnej (darmowy VirtualBox) i przekazujemy do niej
ploter przez USB. Na Twoim komputerze nic się nie zmienia.

Potrzebujesz: kabla USB 2.0 A–B (tego, który już działa z ploterem), około 35 GB wolnego miejsca
na dysku i obrazu ISO 32-bitowego Windows 10.

## Krok 1: obraz ISO Windows 10 32-bit

Pobierz *Media Creation Tool* ze strony Microsoft (pobieranie Windows 10) → *Utwórz nośnik
instalacyjny* → odznacz *Użyj zalecanych opcji* → **Architektura: 32-bitowa (x86)** → *Plik ISO*.
Masz płytę lub ISO 32-bitowego Windows 7? Też się nada.

Windows w maszynie nie musi być aktywowany: klucz produktu można pominąć, a ploter i tak działa.

## Krok 2: utworzenie maszyny (na Twoim komputerze)

1. Podłącz i włącz ploter (kabel USB).
2. Uruchom **`setup-vm.bat`** i postępuj zgodnie z komunikatami. Skrypt:
   - zainstaluje VirtualBox, jeśli go brakuje,
   - wykryje ploter (jeśli nie rozpozna go po nazwie, poprosi o odłączenie i podłączenie kabla),
   - utworzy maszynę `Ploter-GCC` i ustawi automatyczne przekazywanie do niej plotera,
   - utworzy folder `C:\Ploter`, wspólny dla komputera i maszyny,
   - uruchomi instalację Windows (zwykle automatyczną; login `ploter`, hasło `ploter`).

## Krok 3: sterownik GCC (w maszynie)

Jaguar II w trybie „GCC USB” przedstawia się jako urządzenie bez klasy (`USB\Class_00`).
Instalatory GCC 2.17 i 2.39 wykrywają po USB tylko ploter w trybie „Common USB” (jako drukarkę USB),
więc kończą się komunikatem „USB device not detected!”, także w 32-bitowym Windows.
Sterownik „Obsługa drukowania USB” daje kod 10.

Obie paczki zawierają jednak oryginalny sterownik trybu „GCC USB”: `gccusd.sys` (32-bit, 2009,
podpisany przez GCC), tylko bez pliku `.inf`. Folder `gccusd` uzupełnia brakujący plik:

- `gccusd.inf` przypisuje `gccusd.sys` do `USB\VID_0F0B&PID_0002` (tylko 32-bitowy Windows),
- `zainstaluj-sterownik.ps1` wyjmuje `gccusd.sys` z instalatora GCC 2.39-01 lub 2.17-01,
  sprawdza jego SHA-256 i instaluje sterownik.

Sterownik po zainstalowaniu udostępnia urządzenie `\\.\EZNUS0`. Każdy zapis do niego to transfer
bulk USB do plotera, bez dodatkowej wymiany poleceń. `guest-plot.ps1` wysyła tam HPGL bezpośrednio.

1. Pobierz paczkę sterowników GCC 2.39-01:
   https://support.jorlink.com/hubfs/Drivers-Firmware-Manuals/GCC%20Vinyl%20Cutters/GCC%20Vinyl%20All%20Cutter%20Driver%202.39-01.zip,
   rozpakuj ją i wrzuć `Cutter_Plotter_driver_USB_V2.39-01.exe` do `C:\Ploter\sterownik`.
2. Skopiuj folder `plotter\vm\gccusd` oraz pliki `guest-plot.ps1` i `guest-plot.bat` do `C:\Ploter`
   (robi to też `setup-vm.bat`).
3. Upewnij się, że ploter jest przekazany do maszyny (menu okna maszyny *Urządzenia → USB* →
   zaznaczony ploter).
4. W maszynie otwórz **PowerShell jako administrator** i uruchom:
   `powershell -ExecutionPolicy Bypass -File \\VBOXSVR\Ploter\gccusd\zainstaluj-sterownik.ps1`
   Na ostrzeżenie o niezweryfikowanym wydawcy wybierz *Zainstaluj mimo to*. Jeśli skrypt poprosi
   o ręczną podmianę sterownika w Menedżerze urządzeń, zrób to i uruchom go ponownie.
5. Jeśli 32-bitowy Windows 10 nie uruchomi sterownika (kod 10, 39 lub 52), użyj 32-bitowego Windows 7.

## Krok 4: cięcie

W maszynie uruchom `\\VBOXSVR\Ploter\guest-plot.bat`:

- **1**: kwadrat testowy 30×30 mm, który sprawdza, czy wszystko działa,
- **2**: wysłanie jednego pliku `.plt`/`.hpgl`,
- **3**: tryb folderu: plik zapisany (np. wyeksportowany z CorelDRAW lub Inkscape) **na Twoim
  komputerze** do `C:\Ploter` zostaje sam wysłany do plotera.

Możesz też zainstalować GreatCut lub SignCut w maszynie i ciąć bezpośrednio z niego.

## Problemy

| Objaw | Co zrobić |
|---|---|
| VirtualBox nie startuje maszyny / błąd VT-x | Włącz wirtualizację (VT-x/AMD-V, SVM) w BIOS/UEFI |
| Maszyna działa bardzo wolno | Wyłącz Hyper-V/„Platformę maszyny wirtualnej” w funkcjach Windows albo przydziel więcej RAM |
| Ploter nie widoczny w maszynie | Menu *Urządzenia → USB*; sprawdź, czy kabel jest podłączony przed startem maszyny |
| „Nie znalazłem ani sterownika gccusd…” | Uruchom ponownie `gccusd\zainstaluj-sterownik.ps1` i sprawdź, czy ploter ma sterownik `gccusd` |
| Brak `\\VBOXSVR\Ploter` | Zainstaluj dodatki gościa: menu *Urządzenia → Wstaw obraz płyty z dodatkami gościa* |
