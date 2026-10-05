@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 1 - wytnij kwadrat testowy
echo 2 - wyslij plik PLT/HPGL
echo 3 - obserwuj folder \\VBOXSVR\Ploter i wysylaj zapisane tam pliki
set /p WYBOR=Wybierz 1, 2 lub 3: 
set PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0guest-plot.ps1"
if "%WYBOR%"=="1" %PS% -Test
if "%WYBOR%"=="2" (
  set /p PLIK=Przeciagnij tu plik i nacisnij Enter: 
  call %%PS%% -File %%PLIK%%
)
if "%WYBOR%"=="3" %PS% -Watch
pause
