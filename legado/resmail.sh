#!/bin/bash
carpeta="/mnt/DATOS/quemar/2026/RESMAIL/"
#echo $fdd
cd "$carpeta"
#ls -l
echo rar a carpetas
for folder in */; do rar a -m5 -v666M -df -R "${folder%/}.rar" "$folder"; done
echo borrado de carpetas vacias
find . -empty -type d -delete
