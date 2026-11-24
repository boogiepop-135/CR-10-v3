@echo off
chcp 65001 >nul
title Backup Google Drive -> NAS
echo.
echo  Salvando tus carpetas de Drive al NAS (incremental, solo lo nuevo)
echo  Destino: \\192.168.100.16\nas\respaldos\gdrive
echo  Podes cancelar con Ctrl+C, la proxima vez retoma donde quedo.
echo.
"C:\Program Files\PuTTY\plink.exe" -ssh levi@192.168.100.16 "/usr/local/bin/gdrive-backup.sh"
echo.
echo  Terminado. Logs en \\192.168.100.16\nas\respaldos\logs
pause
