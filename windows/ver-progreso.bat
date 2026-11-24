@echo off
chcp 65001 >nul
title Estado del respaldo de Drive
"C:\Program Files\PuTTY\plink.exe" -ssh levi@192.168.100.16 "/usr/local/bin/gdrive-status.sh"
echo.
pause
