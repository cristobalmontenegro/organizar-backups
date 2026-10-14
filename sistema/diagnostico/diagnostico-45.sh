#!/usr/bin/env bash
# diagnostico-45.sh — SONDEO DE SOLO LECTURA
# No graba, no borra, no monta nada. Solo consulta el hardware, el disco
# en blanco y el entorno, y guarda un informe para enviar.
#
#   Uso:   bash diagnostico-45.sh
#   Salida: en pantalla y en ~/diagnostico-45.txt

INFORME="$HOME/diagnostico-45.txt"
exec > >(tee "$INFORME") 2>&1

hr() { printf '\n========== %s ==========\n' "$1"; }
cmd() { printf '$ %s\n' "$*"; "$@" 2>&1 || echo "   (falló, se ignora)"; }

echo "================================================================"
echo "  DIAGNÓSTICO SERVIDOR 45  —  $(date '+%F %T')"
echo "  host: $(hostname)   usuario: $(whoami)"
echo "=============================================================="

echo
echo "############## 0. SISTEMA Y KERNEL ##############"
uname -a
[ -f /etc/os-release ] && . /etc/os-release && echo "OS: $PRETTY_NAME"
echo "bash: $BASH_VERSION"

echo
echo "########## 1. GRABADORAS Y DISCOS ÓPTICOS ##########"
echo "--- lsblk (bloques):"
lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT 2>&1 | grep -Ei 'sr[0-9]|rom|NAME|loop|disk' || lsblk 2>&1
echo
echo "--- dispositivos /dev/sr*:"
ls -l /dev/sr* /dev/cdrom /dev/dvd* 2>&1
echo
echo "--- blockdev --getsize64 (tamaño en bytes del lector):"
for d in /dev/sr*; do [ -e "$d" ] && printf '%s -> ' "$d" && blockdev --getsize64 "$d" 2>&1; done
echo
echo "--- capacidades de la unidad (/proc/sys/dev/cdrom/info):"
cat /proc/sys/dev/cdrom/info 2>&1
echo
echo "--- unidades que ve xorriso:"
xorriso -devices 2>&1 | head -20

echo
echo "############################################################"
echo "#  LO MÁS IMPORTANTE: CAPACIDAD DEL BLURAY EN BLANCO        #"
echo "############################################################"
for d in /dev/sr0 /dev/sr1; do
  [ -e "$d" ] || continue
  echo
  echo "=================== dvd+rw-mediainfo $d ==================="
  dvd+rw-mediainfo "$d" 2>&1
  echo
  echo "=================== xorriso -indev $d -tell_media_space ==="
  xorriso -indev "$d" -tell_media_space 2>&1 | tail -8
  echo
  echo "=================== xorriso -outdev $d -tell_media_space =="
  xorriso -outdev "$d" -tell_media_space 2>&1 | tail -8
  echo
  echo "=================== cdrecord -media-info dev=$d ==========="
  cdrecord -media-info dev="$d" 2>&1 | head -50
  echo
  echo "=================== cdrecord -toc dev=$d =================="
  cdrecord -toc dev="$d" 2>&1 | head -20
done

echo
echo "=== RESUMEN: busca estas líneas clave ==="
echo "  dvd+rw-mediainfo:  'READ CAPACITY: N*2048=...'  ->  N*2048 = bytes escribibles"
echo "                     'Mounted Media: ...'          ->  tipo de disco (BD-R?)"
echo "                     'Current Write Speed: ...'    ->  velocidad"
echo "                     'READ FORMAT CAPACITIES: ...' ->  formatos y tamaños"
echo "  xorriso:           'Media space' / 'Media current: is blank' / 'is not blank'"

echo
echo "=== HERRAMIENTAS ==="
for t in rar unrar 7z 7za xorriso dvd+rw-mediainfo cdrecord cdrskin wodim growisofs genisoimage mkisofs fdupes jdupes tmux screen flock msmtp jq python3 rsync; do
  printf '%-18s ' "$t"; command -v "$t" || echo "NO"
done
echo
echo "--- versión de xorriso:"
xorriso -version 2>&1 | head -3
echo "--- versión de rar:"
(rar 2>&1 | head -3) || echo "rar NO"
echo "--- versión de msmtp:"
(msmtp --version 2>&1 | head -2) || echo "msmtp NO"

echo
echo "=== DATOS (si existen en esta máquina) ==="
ls -la /mnt/DATOS/ 2>&1
[ -d /mnt/DATOS/quemar ] && { echo "--- subcarpetas de quemar:"; ls -la /mnt/DATOS/quemar/; } || echo "NO existe /mnt/DATOS/quemar aquí"
echo
echo "--- espacio en disco:"
df -h 2>&1 | grep -Ev 'tmpfs|udev|loop'
echo "--- bloque/tamaño del fs de /mnt/DATOS:"
stat -f -c 'tipo=%T bloque=%s' /mnt/DATOS 2>&1 || true

echo
echo "=== RED / SERVIDOR 14 ==="
hostname -I 2>&1
ip route 2>&1 | head -5
ls -la ~/.ssh/ 2>&1 | head
grep -rA2 -iE 's14|servidor.?14|nfs|smb|cifs' /etc/fstab ~/.ssh/config 2>/dev/null || echo "nada en fstab/ssh"

echo
echo "=== FIN DEL INFORME ==="