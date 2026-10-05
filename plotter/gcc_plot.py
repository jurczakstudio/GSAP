#!/usr/bin/env python3
"""
gcc_plot.py - wysyłanie HPGL do plotera GCC Jaguar II przez port szeregowy (COM)
z pominięciem sterownika GCC USB, który nie działa na 64-bitowym Windows 10/11.

Połączenie: komputer USB -> przejściówka USB/RS-232 (FTDI) -> kabel null-modem
9-pin -> 25-pin -> złącze SERIAL plotera. Kabel USB musi być WYJĘTY z plotera.

Ustawienia plotera (menu): 9600 baud, brak parzystości, 8 bitów danych, 1 bit stopu.

Przykłady:
    python gcc_plot.py ports                       # lista portów COM
    python gcc_plot.py test --port COM3            # wytnij kwadrat testowy 30x30 mm
    python gcc_plot.py send projekt.plt --port COM3
    python gcc_plot.py watch C:\\Ploter --port COM3 # wysyłaj każdy plik zapisany w folderze
    python gcc_plot.py info --port COM3            # zapytaj ploter o identyfikację/bufor
"""

import argparse
import os
import shutil
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("Brak biblioteki pyserial. Zainstaluj ją poleceniem:\n    python -m pip install pyserial")

UNITS_PER_MM = 40  # HPGL: 1 jednostka = 0,025 mm
PLOT_EXTENSIONS = {".plt", ".hpgl", ".hpg", ".hgl", ".prn"}
ESC = "\x1b"


# ---------------------------------------------------------------- połączenie

def open_port(args):
    flow = args.flow
    try:
        port = serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            rtscts=(flow == "hardware"),
            dsrdtr=(flow == "dsrdtr"),
            xonxoff=(flow == "xonxoff"),
            timeout=1,
            write_timeout=args.write_timeout,
        )
    except serial.SerialException as e:
        sys.exit(
            f"Nie mogę otworzyć portu {args.port}: {e}\n"
            "Sprawdź numer portu (python gcc_plot.py ports) i czy żaden inny program "
            "(GreatCut, sterownik GCC) go nie używa."
        )
    if flow in ("none", "xonxoff"):
        # Część kabli null-modem zapętla linie sterujące - ustawiamy je aktywne,
        # żeby ploter "widział" gotowy komputer.
        try:
            port.dtr = True
            port.rts = True
        except (OSError, serial.SerialException):
            pass
    return port


def send_data(port, data, chunk=256, verbose=True):
    """Wysyła dane w małych porcjach i czeka, aż bufor nadawczy się opróżni.
    Kontrolę przepływu (RTS/CTS lub XON/XOFF) obsługuje sterownik portu,
    więc ploter sam wstrzymuje transmisję, gdy jego bufor jest pełny."""
    raw = data.encode("ascii", errors="ignore") if isinstance(data, str) else data
    total = len(raw)
    sent = 0
    start = time.time()
    try:
        while sent < total:
            n = port.write(raw[sent:sent + chunk])
            sent += n or 0
            if verbose:
                pct = 100 * sent // total if total else 100
                print(f"\r  wysłano {sent}/{total} B ({pct}%)", end="", flush=True)
        port.flush()
    except serial.SerialTimeoutException:
        print()
        sys.exit(
            "Ploter przestał przyjmować dane (przekroczony czas zapisu).\n"
            "Możliwe przyczyny: ploter w trybie offline/pauza, zły kabel (potrzebny null-modem),\n"
            "inna kontrola przepływu niż w ploterze - spróbuj --flow xonxoff lub --flow none."
        )
    if verbose:
        print(f"\n  gotowe w {time.time() - start:.1f} s")


def query(port, command, wait=1.5):
    """Wysyła zapytanie i zwraca odpowiedź zakończoną CR (albo to, co przyszło)."""
    port.reset_input_buffer()
    port.write(command.encode("ascii"))
    port.flush()
    deadline = time.time() + wait
    buf = b""
    while time.time() < deadline:
        part = port.read(port.in_waiting or 1)
        if part:
            buf += part
            if b"\r" in buf:
                break
    return buf.decode("ascii", errors="replace").strip()


# ---------------------------------------------------------------- HPGL

def normalize_hpgl(text):
    """Porządkuje plik HPGL: usuwa śmieci binarne, dokłada inicjalizację i zakończenie."""
    text = "".join(ch for ch in text if ch in "\x1b\x03\r\n\t" or 32 <= ord(ch) < 127)
    body = text.strip()
    upper = body.upper()
    if not upper.startswith("IN"):
        body = "IN;" + body
    if not body.endswith(";"):
        body += ";"
    if "SP0" not in upper[-20:]:
        body += "PU;SP0;"
    return body + "\r\n"


def mm(v):
    return int(round(v * UNITS_PER_MM))


def test_pattern(size_mm, offset_mm, knife):
    """Kwadrat z krzyżykiem w środku - typowy test noża i nacisku."""
    o, s = mm(offset_mm), mm(size_mm)
    c = o + s // 2
    a = mm(min(5, size_mm / 4))
    return (
        f"IN;SP{knife};"
        f"PU{o},{o};PD{o + s},{o},{o + s},{o + s},{o},{o + s},{o},{o};"
        f"PU{c - a},{c};PD{c + a},{c};"
        f"PU{c},{c - a};PD{c},{c + a};"
        "PU0,0;SP0;\r\n"
    )


def read_plot_file(path):
    with open(path, "rb") as f:
        raw = f.read()
    return normalize_hpgl(raw.decode("latin-1"))


# ---------------------------------------------------------------- komendy

def cmd_ports(args):
    ports = list(list_ports.comports())
    if not ports:
        print("Nie znaleziono żadnego portu COM. Podłącz przejściówkę USB/RS-232 "
              "i zainstaluj sterownik FTDI (ftdichip.com -> VCP Drivers).")
        return
    print("Dostępne porty:")
    for p in ports:
        hint = ""
        if "FTDI" in (p.manufacturer or "") or (p.vid == 0x0403):
            hint = "  <- przejściówka FTDI, prawdopodobnie ta"
        print(f"  {p.device:8} {p.description}{hint}")


def cmd_info(args):
    with open_port(args) as port:
        print(f"Port {args.port}, {args.baud} 8N1, kontrola przepływu: {args.flow}")
        ident = query(port, "OI;")
        print(f"  Identyfikacja (OI): {ident or '(brak odpowiedzi)'}")
        buf = query(port, ESC + ".B")
        print(f"  Wolny bufor (ESC.B): {buf or '(brak odpowiedzi)'}")
        status = query(port, ESC + ".O")
        print(f"  Status (ESC.O): {status or '(brak odpowiedzi)'}")
        if not (ident or buf or status):
            print("\nPloter nie odpowiada na zapytania. To nie musi oznaczać błędu - wiele "
                  "ploterów tnących tylko przyjmuje dane. Uruchom 'test', żeby sprawdzić cięcie.")


def cmd_test(args):
    data = test_pattern(args.size, args.offset, args.knife)
    print(f"Wysyłam kwadrat testowy {args.size} mm na {args.port}...")
    with open_port(args) as port:
        send_data(port, data)
    print("Jeśli ploter wyciął kwadrat - połączenie działa. Ustaw ten sam port w GreatCut/SignCut\n"
          "albo używaj komend 'send' / 'watch'.")


def cmd_send(args):
    with open_port(args) as port:
        for path in args.files:
            print(f"Wysyłam {path}...")
            send_data(port, read_plot_file(path))


def cmd_watch(args):
    folder = os.path.abspath(args.folder)
    done = os.path.join(folder, "wyslane")
    os.makedirs(done, exist_ok=True)
    print(f"Obserwuję folder {folder}\n"
          f"Zapisuj/eksportuj tam pliki {', '.join(sorted(PLOT_EXTENSIONS))} - zostaną wysłane do "
          f"plotera i przeniesione do 'wyslane'. Ctrl+C kończy.")
    sizes = {}
    with open_port(args) as port:
        try:
            while True:
                for name in sorted(os.listdir(folder)):
                    path = os.path.join(folder, name)
                    if not os.path.isfile(path) or os.path.splitext(name)[1].lower() not in PLOT_EXTENSIONS:
                        continue
                    size = os.path.getsize(path)
                    # wysyłamy dopiero, gdy rozmiar pliku przestał się zmieniać (zapis zakończony)
                    if sizes.get(path) != size:
                        sizes[path] = size
                        continue
                    print(f"[{time.strftime('%H:%M:%S')}] {name}")
                    send_data(port, read_plot_file(path))
                    target = os.path.join(done, time.strftime("%Y%m%d-%H%M%S-") + name)
                    shutil.move(path, target)
                    sizes.pop(path, None)
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nKoniec.")


def main():
    parser = argparse.ArgumentParser(
        description="Wysyłanie HPGL do plotera GCC Jaguar II przez port COM (bez sterownika GCC USB).")
    sub = parser.add_subparsers(dest="command", required=True)

    def add_port_options(p):
        p.add_argument("--port", required=True, help="port COM, np. COM3 (lista: 'ports')")
        p.add_argument("--baud", type=int, default=9600, help="prędkość - jak w menu plotera (domyślnie 9600)")
        p.add_argument("--flow", choices=["hardware", "xonxoff", "dsrdtr", "none"], default="hardware",
                       help="kontrola przepływu (domyślnie hardware = RTS/CTS)")
        p.add_argument("--write-timeout", type=float, default=60,
                       help="ile sekund czekać, gdy ploter wstrzyma transmisję (domyślnie 60)")

    sub.add_parser("ports", help="pokaż dostępne porty COM").set_defaults(func=cmd_ports)

    p = sub.add_parser("info", help="zapytaj ploter o identyfikację i stan bufora")
    add_port_options(p)
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("test", help="wytnij kwadrat testowy")
    add_port_options(p)
    p.add_argument("--size", type=float, default=30, help="bok kwadratu w mm (domyślnie 30)")
    p.add_argument("--offset", type=float, default=10, help="odsunięcie od punktu startu w mm (domyślnie 10)")
    p.add_argument("--knife", type=int, default=1, help="numer narzędzia SP (domyślnie 1)")
    p.set_defaults(func=cmd_test)

    p = sub.add_parser("send", help="wyślij plik(i) HPGL/PLT")
    add_port_options(p)
    p.add_argument("files", nargs="+", help="pliki .plt/.hpgl")
    p.set_defaults(func=cmd_send)

    p = sub.add_parser("watch", help="automatycznie wysyłaj pliki zapisywane w folderze")
    add_port_options(p)
    p.add_argument("folder", help="folder do obserwowania")
    p.set_defaults(func=cmd_watch)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
