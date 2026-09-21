@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem PC + phone LAN test. Both devices must use the same Wi-Fi network.
set "GAME=DoubleTake_PC_Phone_LAN_Test.exe"
if not exist "%GAME%" (
  echo Missing %GAME% next to this launcher.
  pause
  exit /b 1
)

echo Your Wi-Fi IPv4 address is the one to enter on the phone APK:
ipconfig | findstr /R /C:"IPv4"
echo.
echo If Windows Firewall asks, allow Double Take on Private networks.
start "Double Take LAN Server" /b "%GAME%" --server --port=7200 --code=LAN4PC --room-secret=dev --minimum-players=2 --prefer-camper=pc-camper-1 --shutdown-when-empty
timeout /t 1 /nobreak >nul
start "PC Camper" "%GAME%" --address=127.0.0.1 --port=7200 --token=dev:pc-camper-1:host --name="PC Camper" --color=0 --auto-ready --auto-start
echo.
echo On the phone: open the LAN test APK, type this PC's Wi-Fi IPv4 above,
echo then tap JOIN PC LAN and READY. The match starts automatically.
pause
