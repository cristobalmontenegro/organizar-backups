#!/bin/bash
carpeta="/mnt/DATOS/quemar/usuario-d/"
#echo $fdd
cd "$carpeta"
#ls -l
echo borrando files_trashbin
find . -type d -name "files_trashbin" -exec rm -rf {} +
echo borrando duplicados
for folder in */; do fdupes -rdN "$folder"; done

##find . -type f \( -name \*jpg -o -name \*png \) -delete
echo borrando archivos no deseados
find . -type f \( -name \*.gif -o -name \*.pst -o -name \.msi -o -name \.dbx -o -name \.tmp -o -name \.iso -o -name \.img -o -name \.exe -o -name \.mpg -o -name \.mp3 -o -name \.wma -o -name \.wmv -o -name \.mp4 -o -name \.avi -o -name \.mov \) -delete
echo borrando vacios
find . -empty -type f -delete
find . -empty -type d -delete
echo rar a carpetas
for folder in */; do rar a -m5 -v694M -df -R "${folder%/}.rar" "$folder"; done
echo borrado de carpetas vacias
find . -empty -type d -delete
