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

1. Pobierz sterownik USB dla Jaguar II ze strony GCC (sekcja Support/Download) i wrzuć go
   na swoim komputerze do `C:\Ploter\sterownik`.
2. W maszynie otwórz `\\VBOXSVR\Ploter\sterownik` i zainstaluj sterownik.
3. Jeśli Windows w maszynie nie widzi plotera, w oknie maszyny wybierz menu *Urządzenia → USB*
   i zaznacz ploter.

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
