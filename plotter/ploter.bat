@echo off
chcp 65001 >nul
cd /d "%~dp0"
python -c "import serial" 2>nul || (
  echo Instaluje biblioteke pyserial...
  python -m pip install pyserial || (echo Nie znaleziono Pythona - zainstaluj go z python.org & pause & exit /b 1)
)
python gcc_plot.py ports
echo.
set /p PORT=Podaj port przejsciowki (np. COM3): 
echo.
echo 1 - wytnij kwadrat testowy
echo 2 - wyslij plik PLT/HPGL
echo 3 - obserwuj folder C:\Ploter i wysylaj zapisane tam pliki
set /p WYBOR=Wybierz 1, 2 lub 3: 
if "%WYBOR%"=="1" python gcc_plot.py test --port %PORT%
if "%WYBOR%"=="2" (
  set /p PLIK=Przeciagnij tu plik i nacisnij Enter: 
  call python gcc_plot.py send %%PLIK%% --port %PORT%
)
if "%WYBOR%"=="3" python gcc_plot.py watch C:\Ploter --port %PORT%
pause
