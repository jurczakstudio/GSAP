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

Jaguar II działa tylko w trybie „GCC USB”, a do tego trybu GCC ma wyłącznie 32-bitowy sterownik
jądra (`gccusd.sys`, sprawdzone w paczce 2.39-01). Dlatego na 64-bitowym Windows instalator kończy
się komunikatem „USB device not detected!”, a w 32-bitowej maszynie powinien zadziałać.

1. Pobierz paczkę sterowników GCC 2.39-01 (obsługuje JaguarII-61/101/132):
   https://support.jorlink.com/hubfs/Drivers-Firmware-Manuals/GCC%20Vinyl%20Cutters/GCC%20Vinyl%20All%20Cutter%20Driver%202.39-01.zip
   i wrzuć `Cutter_Plotter_driver_USB_V2.39-01.exe` do `C:\Ploter\sterownik`.
2. Upewnij się, że ploter jest przekazany do maszyny (menu okna maszyny *Urządzenia → USB* →
   zaznaczony ploter). Na komputerze-gospodarzu zniknie on wtedy z Menedżera urządzeń.
3. W maszynie uruchom `\\VBOXSVR\Ploter\sterownik\Cutter_Plotter_driver_USB_V2.39-01.exe`
   jako administrator i wybierz swój model Jaguar II.
4. Jeśli 32-bitowy Windows 10 odmówi załadowania sterownika, użyj 32-bitowego Windows 7.

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
| „Nie znalazłem drukarki GCC” | Uruchom `guest-plot.ps1 -ListPrinters` i podaj nazwę: `-Printer "nazwa"` |
| Brak `\\VBOXSVR\Ploter` | Zainstaluj dodatki gościa: menu *Urządzenia → Wstaw obraz płyty z dodatkami gościa* |
