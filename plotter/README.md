# GCC Jaguar II przez port COM, bez sterownika GCC USB

> **Nie chcesz kupować przejściówki?** Użyj wariantu z maszyną wirtualną: [vm/README.md](vm/README.md).

Sterownik GCC USB do Jaguara II nie działa na 64-bitowym Windows 10/11: ploter nie
wykonuje poleceń wysyłanych po USB. Ten program omija sterownik i wysyła zwykły
HPGL przez złącze **SERIAL**, które działa niezależnie od wersji Windows.

## Sprzęt

1. Przejściówka **USB → RS-232 na chipie FTDI** (30–50 zł). Sterownik: ftdichip.com → *VCP Drivers*
   (Windows 10/11 zwykle instaluje go sam).
2. Kabel szeregowy **null-modem 9-pin → 25-pin**.
3. **Wyjmij kabel USB z plotera.**
4. W menu plotera ustaw: **9600 baud, parzystość: none, 8 bitów, 1 bit stopu**.

## Instalacja

1. Zainstaluj Pythona z python.org (zaznacz *Add python.exe to PATH*).
2. W tym folderze uruchom: `python -m pip install pyserial`

## Użycie

Najprościej uruchomić `ploter.bat`, który poprowadzi krok po kroku. Ręcznie:

```
python gcc_plot.py ports                         # znajdź port przejściówki, np. COM3
python gcc_plot.py test --port COM3              # wytnie kwadrat 30x30 mm z krzyżykiem
python gcc_plot.py send projekt.plt --port COM3  # wyśle plik HPGL/PLT
python gcc_plot.py watch C:\Ploter --port COM3   # "drukarka-folder"
python gcc_plot.py info --port COM3              # zapytanie o identyfikację plotera
```

**Tryb `watch`**: każdy plik `.plt`/`.hpgl` zapisany do wskazanego folderu (np. przez
eksport z CorelDRAW, Inkscape czy Illustratora) jest automatycznie wysyłany do plotera
i przenoszony do podfolderu `wyslane`.

GreatCut i SignCut mogą też wysyłać dane bezpośrednio: ustaw w nich ten sam port COM,
9600 baud, zamiast USB. Nie uruchamiaj ich równocześnie z tym programem, bo port COM
może mieć otwarty tylko jeden program naraz.

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| Brak portu COM na liście | Podłącz przejściówkę, doinstaluj sterownik FTDI, sprawdź Menedżer urządzeń → *Porty (COM i LPT)* |
| „Ploter przestał przyjmować dane” | Ploter jest offline/w pauzie, kabel nie jest null-modemem albo inna kontrola przepływu: dodaj `--flow xonxoff`, potem spróbuj `--flow none` |
| Ploter tnie krzaczki/przypadkowe linie | Prędkość w ploterze różni się od `--baud` (domyślnie 9600) |
| Ploter nic nie robi, brak błędu | Spróbuj `--flow none`; sprawdź, czy ploter jest w trybie HP-GL i online |
| Wymiary są złe | Ploter oczekuje 40 jednostek/mm (standard HPGL); sprawdź ustawienie skali w programie eksportującym |
