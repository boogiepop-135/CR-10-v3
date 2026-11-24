#!/bin/bash
# =====================================================================
#  gdrive-backup.sh - respaldo incremental de Google Drive a /nas
#  Uso:
#    gdrive-backup.sh                 -> las carpetas de la lista CARPETAS
#    gdrive-backup.sh pablo Brenda    -> solo esas
#    gdrive-backup.sh --listar        -> carpetas de la raiz del Drive
#    gdrive-backup.sh --todas         -> todo el Drive
#  Log: /nas/respaldos/logs/gdrive-YYYYmmdd-HHMMSS.log
#  Se excluyen node_modules y .git (miles de archivos chicos que hacen
#  el respaldo 10x mas lento contra la API de Google Drive).
# =====================================================================
EXCLUDES=(--exclude "**/node_modules/**" --exclude "**/.git/**")
set -u
REMOTE="gdrive"
DEST_BASE="/nas/respaldos/gdrive"
LOG_DIR="/nas/respaldos/logs"
LOCK="/tmp/gdrive-backup.lock"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/gdrive-$STAMP.log"

CARPETAS=(
  "pablo"
  "carpetazo"
  "Brenda"
  "FIEL_VIAL941013337_20250918104913"
  "Documentos"
  "usb verde"
  "4Geeks Academy Clases ESPAÑOL - latam-pt-44"
)

mkdir -p "$LOG_DIR"

if [ "${1:-}" = "--listar" ]; then
  rclone lsf "$REMOTE:/" --dirs-only
  exit 0
fi

if [ "${1:-}" = "--todas" ]; then
  shift
  mapfile -t CARPETAS < <(rclone lsf "$REMOTE:/" --dirs-only | sed 's#/$##')
fi

if [ "$#" -gt 0 ]; then
  CARPETAS=("$@")
fi

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "Ya hay un respaldo corriendo (lock $LOCK). Esperalo o matalo."
  exit 1
fi

echo "### respaldo iniciado $(date '+%F %T') -> $DEST_BASE"
echo "### log: $LOG"
echo "### carpetas: ${#CARPETAS[@]}"

fallidas=()
for c in "${CARPETAS[@]}"; do
  dest="$DEST_BASE/$c"
  mkdir -p "$dest"
  echo
  echo "--- $c ---"
  rclone copy "$REMOTE:$c" "$dest" \
    "${EXCLUDES[@]}" \
    --fast-list --transfers 8 --checkers 16 \
    --update --skip-links --retries 5 --low-level-retries 20 \
    --timeout 5m --contimeout 60s \
    --stats 60s --stats-one-line --progress \
    --log-file "$LOG" --log-level INFO
  if [ $? -eq 0 ]; then
    printf '%-52s %s  (%s archivos)\n' "$c" "$(du -sh "$dest" 2>/dev/null | cut -f1)" "$(find "$dest" -type f | wc -l)"
  else
    echo "FALLO: $c (ver $LOG)"
    fallidas+=("$c")
  fi
done

echo
echo "### terminado $(date '+%F %T')"
printf '### total en %s: %s\n' "$DEST_BASE" "$(du -sh "$DEST_BASE" 2>/dev/null | cut -f1)"
df -h /nas | tail -1
if [ "${#fallidas[@]}" -gt 0 ]; then
  echo "### CARPETAS CON ERROR: ${fallidas[*]}"
  exit 1
fi
echo "### todo OK"
