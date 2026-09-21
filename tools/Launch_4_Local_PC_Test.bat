@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Same-PC test only: launches a local ENet room, not EOS P2P.
rem Four visible game windows open automatically. Camper 1 is kept as Camper.
set "GAME=DoubleTake_Local_4PC_Test.exe"
if not exist "%GAME%" (
  echo Missing %GAME% next to this launcher.
  pause
  exit /b 1
)

set /a PORT=24000 + (%RANDOM% %% 10000)
set "ROOM=LOCAL4"
echo Starting local 4-player test on port %PORT%...
start "Double Take Local Server" /b "%GAME%" --server --port=%PORT% --code=%ROOM% --room-secret=dev --minimum-players=4 --prefer-camper=local-player-1 --shutdown-when-empty
timeout /t 1 /nobreak >nul

start "Camper 1" "%GAME%" --address=127.0.0.1 --port=%PORT% --token=dev:local-player-1:host --name="Camper 1" --color=0 --auto-ready --auto-start
start "Player 2" "%GAME%" --address=127.0.0.1 --port=%PORT% --token=dev:local-player-2:client --name="Player 2" --color=1 --auto-ready
start "Player 3" "%GAME%" --address=127.0.0.1 --port=%PORT% --token=dev:local-player-3:client --name="Player 3" --color=2 --auto-ready
start "Player 4" "%GAME%" --address=127.0.0.1 --port=%PORT% --token=dev:local-player-4:client --name="Player 4" --color=3 --auto-ready

echo Four local player windows are launching. Use the Camper 1 window to play.
echo The hidden local server exits after all four test windows close.
timeout /t 3 /nobreak >nul
