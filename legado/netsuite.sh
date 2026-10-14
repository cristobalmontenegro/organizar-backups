#!/bin/bash
carpeta="/mnt/DATOS/quemar/2026/RESNETSUITE/"
#echo $fdd
cd "$carpeta"
#ls -l
echo borrando duplicados
for folder in */; do fdupes -rdN "$folder"; done

##find . -type f \( -name \*jpg -o -name \*png \) -delete
echo borrando archivos no deseados
find . -type f \( -name \*.gif -o -name \.msi -o -name \.exe -o -name \.mpg -o -name \.mp3 -o -name \.mp4 -o -name \.avi -o -name \.mov \) -delete
echo borrando vacios
find . -empty -type f -delete
find . -empty -type d -delete
echo rar a carpetas
for folder in */; do rar a -m5 -v688M -df -R "${folder%/}.rar" "$folder"; done
echo borrado de carpetas vacias
find . -empty -type d -delete
