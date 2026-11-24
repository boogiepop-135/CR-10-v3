#!/bin/bash
# gdrive-status.sh - estado detallado del respaldo de Google Drive al NAS
OUT=/nas/respaldos/logs/run-actual.out
TSV=/nas/respaldos/gdrive-esperado.tsv
DEST=/nas/respaldos/gdrive
LOG=$(ls -t /nas/respaldos/logs/gdrive-*.log 2>/dev/null | head -1)
RP=$(pgrep -f '[r]clone copy' | head -1)
CUR=$(grep '^--- ' "$OUT" 2>/dev/null | tail -1 | sed 's/^--- //; s/ ---$//')
[ -f "$OUT" ] || { echo "todavia no corro ningun gdrive-backup.sh"; exit 1; }

echo "==================================================================="
echo " RESPALDO GOOGLE DRIVE -> NAS        $(date '+%F %T')"
echo "==================================================================="
if [ -n "$RP" ]; then
  echo "Estado            : CORRIENDO  (pid $RP, activo hace $(ps -o etime= -p "$RP" | tr -d ' '))"
else
  echo "Estado            : sin proceso de descarga (termino o esta entre carpetas)"
fi
echo "Carpeta actual    : $( [ -n "$RP" ] && echo "${CUR:-ninguna}" || echo "ninguna (finalizado)" )"
echo "Cola del script   :"
nl -ba <(cut -f1 "$TSV") | sed 's/^/                    /'
echo
echo "----------------------- VELOCIDAD (medida en el disco) ------------"
A=$(du -sb "$DEST" 2>/dev/null | cut -f1); sleep 6
B=$(du -sb "$DEST" 2>/dev/null | cut -f1)
if [ -n "$RP" ] && [ "$B" -gt "$A" ]; then
  SPDB=$(( (B-A)/6 ))
  echo "  $(awk -v s="$SPDB" 'BEGIN{printf "%.2f MiB/s", s/1048576}')  (${A} -> ${B} bytes en 6s)"
else
  SPDB=0
  echo "  sin transferencia en este momento"
fi
echo
echo "----------------------- ARCHIVOS EN VUELO -------------------------"
if [ -n "$RP" ]; then
  for fd in /proc/"$RP"/fd/*; do
    t=$(readlink "$fd" 2>/dev/null)
    case "$t" in
      "$DEST"/*) printf '  %9s  %s\n' "$(numfmt --to=iec "$(stat -c %s "$t" 2>/dev/null || echo 0)")" "${t#"$DEST"/}" ;;
    esac
  done | sort -u | head -12
else
  echo "  (nada en vuelo)"
fi
echo
echo "----------------------- ULTIMOS TERMINADOS ------------------------"
grep -E ': Copied' "$LOG" 2>/dev/null | tail -5 | sed 's/^[0-9-]* [0-9:]* *INFO *: /  /' || echo "  (sin log)"
echo
echo "----------------------- PROGRESO POR CARPETA ----------------------"
printf '  %-40s %5s %9s %9s %-11s %s\n' CARPETA % DESCARG ESPERADO 'ARCHIVOS' ESTADO
while IFS=$'\t' read -r name bytes objs; do
  got=$(du -sb "$DEST/$name" 2>/dev/null | cut -f1); got=${got:-0}
  gf=$(find "$DEST/$name" -type f 2>/dev/null | wc -l)
  pct=$(awk -v a="$got" -v b="$bytes" 'BEGIN{if(b>0){p=a*100/b; if(p>100)p=100; printf "%.0f",p} else printf "0"}')
  st=pendiente
  if [ "$name" = "$CUR" ] && [ -n "$RP" ]; then st='EN CURSO'
  elif [ "$bytes" -gt 0 ] && [ "$got" -ge $((bytes*98/100)) ]; then st=listo
  elif [ "$got" -gt 0 ]; then st=parcial
  fi
  printf '  %-40s %4s%% %9s %9s %5s/%-6s %s\n' "${name:0:40}" "$pct" \
    "$(numfmt --to=iec "$got")" "$(numfmt --to=iec "$bytes")" "$gf" "$objs" "$st"
done < "$TSV"
echo
echo "----------------------- TOTAL Y TIEMPO ----------------------------"
TOT_B=$(awk -F'\t' '{b+=$2} END{print b}' "$TSV")
TOT_G=$(du -sb "$DEST" 2>/dev/null | cut -f1); TOT_G=${TOT_G:-0}
REM=$((TOT_B - TOT_G)); [ "$REM" -lt 0 ] && REM=0
GB=$(awk -v a="$TOT_G" -v b="$TOT_B" 'BEGIN{printf "%.2f/%.2f", a/1073741824, b/1073741824}')
GP=$(awk -v a="$TOT_G" -v b="$TOT_B" 'BEGIN{if(b>0) printf "%.1f", a*100/b; else printf "0"}')
echo "  global            : ${GB} GB   (${GP}%)"
echo "  falta por bajar   : $(numfmt --to=iec "$REM")B"
SPD=$(grep -oE '[0-9][0-9.]* [KMGT]iB/s' "$OUT" | tail -1)
SPDB=$(awk -v s="$SPD" 'BEGIN{
  n=s; u="B"; split(s,p," "); n=p[1]; u=p[2];
  m["KiB/s"]=1024; m["MiB/s"]=1048576; m["GiB/s"]=1073741824; m["BiB/s"]=1; m["B"]=1;
  if(u in m) printf "%d", n*m[u]; else printf "0"}')
if [ "$SPDB" -gt 0 ] && [ "$REM" -gt 0 ]; then
  echo "  tiempo restante   : $(awk -v r="$REM" -v s="$SPDB" 'BEGIN{t=r/s; printf "%dh %02dm", t/3600, (t%3600)/60}')"
elif [ "$REM" -le 0 ]; then
  echo "  tiempo restante   : 0 (todo descargado)"
else
  echo "  tiempo restante   : sin datos"
fi
echo
echo "----------------------- ESPACIO -----------------------------------"
df -B1 --output=target,size,used,avail /nas / 2>/dev/null | while read -r t s u a; do
  case "$t" in
    /nas)   echo "  NAS externo (/nas)   : total $(numfmt --to=iec "$s")  usado $(numfmt --to=iec "$u")  LIBRE $(numfmt --to=iec "$a")" ;;
    /)      echo "  Disco del sistema    : total $(numfmt --to=iec "$s")  usado $(numfmt --to=iec "$u")  LIBRE $(numfmt --to=iec "$a")" ;;
  esac
done
MARGEN=$(awk -v a="$(df -B1 --output=avail /nas | tail -1)" -v r="$REM" 'BEGIN{printf "%d", a-r}')
echo "  margen despues       : $(numfmt --to=iec "$MARGEN")B  (libre del NAS menos lo que falta)"
[ "$MARGEN" -lt 0 ] && echo "  !! NO CABE: hay que agrandar o excluir mas cosas" || echo "  OK: entra completo"
echo
