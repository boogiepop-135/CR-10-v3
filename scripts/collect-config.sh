#!/bin/bash
# collect-config.sh - vuelve a tomar la configuracion viva del server, commitea y empuja.
# Uso:  bash /nas/respaldos/configs/collect-config.sh      (o desde el repo: scripts/collect-config.sh)
#       git pull en el server y push desde aqui; los .bat de Windows se copian a mano a windows/
set -e
R="${REPO:-$HOME/CR-10-v3}"
[ -d "$R/.git" ] || { echo "no hay repo en $R"; exit 1; }
cd "$R"

mkdir -p printer/config/historial printer/firmware nas systemd scripts windows

# --- impresora ---
cp ~/printer_data/config/printer.cfg            printer/config/
cp ~/printer_data/config/adxl.cfg               printer/config/ 2>/dev/null || true
cp ~/printer_data/config/moonraker.conf         printer/config/
cp ~/printer_data/config/mainsail.cfg           printer/config/ 2>/dev/null || true
cp ~/mainsail-config/mainsail.cfg               printer/config/mainsail-ui.cfg 2>/dev/null || true
cp ~/printer_data/config/orcaslicer-klipper.txt printer/config/ 2>/dev/null || true
cp ~/klipper-SKR2-F407-8MHz.bin                 printer/firmware/ 2>/dev/null || true
ls -t ~/printer_data/config/printer-2*.cfg 2>/dev/null | head -3 | while read -r f; do
  cp "$f" printer/config/historial/; done

# --- NAS / sistema ---
cp /etc/samba/smb.conf              nas/smb.conf
cp /etc/fstab                       nas/fstab
cp /etc/udev/rules.d/99-nas-ssd.rules nas/ 2>/dev/null || true
cp /etc/systemd/logind.conf         nas/logind.conf
[ -f /etc/nginx/sites-enabled/mainsail ] && cp /etc/nginx/sites-enabled/mainsail nas/nginx-mainsail
for u in klipper moonraker; do
  [ -f /etc/systemd/system/$u.service ] && cp /etc/systemd/system/$u.service systemd/; done
[ -f /etc/systemd/system/wsdd.service ] && cp /etc/systemd/system/wsdd.service systemd/
for s in gdrive-backup gdrive-status; do
  [ -f /usr/local/bin/$s.sh ] && cp /usr/local/bin/$s.sh scripts/; done

# --- versiones ---
{
  echo "# Versiones detectadas $(date '+%F')"
  echo '```'
  grep -E '^(NAME|VERSION)=' /etc/os-release
  uname -sr
  echo "klipper:    $(grep -m1 -oE 'v0\.[0-9.]+[a-z0-9.-]*' ~/printer_data/logs/klippy.log 2>/dev/null | head -1)"
  echo "moonraker:  $(cd ~/moonraker && git rev-parse --short HEAD 2>/dev/null)"
  ~/klippy-env/bin/python --version 2>&1 | sed 's/^/python: /'
  echo "samba:      $(smbd -V | head -1)"
  echo "rclone:     $(rclone version 2>/dev/null | head -1)"
  nginx -v 2>&1
  echo "MCU:        SKR2 stm32f407xx $(ls /dev/serial/by-id/ 2>/dev/null | head -1)"
  echo "host:       $(hostname) / $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
  echo '```'
} > VERSIONES.md

# --- control de secretos: busca VALORES, no palabras sueltas ---
bad=""
for f in rclone.conf passdb.tdb shadow db.json id_ed25519 id_rsa; do
  hits=$(find . -name "$f" -not -path './.git/*' 2>/dev/null)
  [ -n "$hits" ] && bad="$bad\n  archivo prohibido: $hits"
done
vals=$(grep -rnE 'ya29\.[A-Za-z0-9_/-]{25,}|"refresh_token"[[:space:]]*:[[:space:]]*"1/|BEGIN [A-Z ]*PRIVATE KEY|api_key[[:space:]]*[:=][[:space:]]*[A-Fa-f0-9]{16,}|password[[:space:]]*=[[:space:]]*[^ #%]{4,}' . --exclude-dir=.git 2>/dev/null | head -5)
if [ -n "$bad" ] || [ -n "$vals" ]; then
  echo "ALTO: hay secretos reales, no commiteo:"
  printf "%b\n" "$bad"; printf '%s\n' "$vals"
  exit 2
fi

git add -A
if git diff --cached --quiet; then
  echo "sin cambios desde el ultimo commit"
else
  git commit -m "config: snapshot automatico $(date '+%F %H:%M')" -q
  echo "commit creado"
  git push origin HEAD 2>&1 | tail -3 || echo "ojo: no se pudo empujar (falta remote/clave?)"
fi
git log --oneline | head -3
