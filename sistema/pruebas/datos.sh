#!/usr/bin/env bash
set -euo pipefail

DIR_SISTEMA="${DIR_SISTEMA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DIR_SISTEMA
. "$DIR_SISTEMA/lib/comunes.sh"

configurar

RAIZ="$(raiz_datos pruebas)"
case "$RAIZ" in
  /tmp/*) ;;
  *) fatal "raiz_pruebas debe quedar bajo /tmp: $RAIZ" ;;
esac

if [[ "${1:-}" == "--limpiar" ]]; then
  rm -rf "$RAIZ"
  info "eliminado $RAIZ"
fi

FECHA="$(fecha_hoy)"
mkdir -p "$RAIZ"

crear() {
  local base="$1" n
  shift
  mkdir -p "$base"
  for n in "$@"; do
    printf 'contenido de prueba %s\n' "$n" >"$base/$n"
  done
}

crear "$RAIZ/RESDOCKER/$FECHA" docker-compose.json config.json
crear "$RAIZ/RESDOCKER/$FECHA/instancias" a.json b.json
cp "$RAIZ/RESDOCKER/$FECHA/config.json" "$RAIZ/RESDOCKER/$FECHA/config - copia.json"

crear "$RAIZ/RESCALIPSO/$FECHA" base.backup log.txt datos.zip
crear "$RAIZ/RESODOO/$FECHA" backup.backup odoo.log respaldo.zip
crear "$RAIZ/RESINTRANET/$FECHA" sitio.zip base.sql

for u in alvarez bravo castro; do
  crear "$RAIZ/RESHOME/$FECHA/$u" doc1.docx nota.txt
  cp "$RAIZ/RESHOME/$FECHA/$u/nota.txt" "$RAIZ/RESHOME/$FECHA/$u/nota.txt.bak"
done
mkdir -p "$RAIZ/RESHOME/$FECHA/alvarez/files_trashbin/abc123"
printf 'borrado\n' >"$RAIZ/RESHOME/$FECHA/alvarez/files_trashbin/abc123/doc.pdf"
printf 'repetido\n' >"$RAIZ/RESHOME/$FECHA/alvarez/dup.txt"
printf 'repetido\n' >"$RAIZ/RESHOME/$FECHA/bravo/dup.txt"

for u in persona1@ejemplo.com persona2@ejemplo.com; do
  crear "$RAIZ/RESNEXTCLOUD/$FECHA/$u/files" uno.pdf dos.odt
  mkdir -p "$RAIZ/RESNEXTCLOUD/$FECHA/$u/files_trashbin"
  mkdir -p "$RAIZ/RESNEXTCLOUD/$FECHA/$u/files_versions"
done

crear "$RAIZ/RESOTROS/$FECHA/takeout" correo.mbox drive.json
crear "$RAIZ/RESOTROS/$FECHA/pc-descargada" instalador.iso run.exe video.mp4

crear "$RAIZ/RESMAIL/$FECHA/buzon1" 1.eml 2.eml 3.eml
crear "$RAIZ/RESPUBLICO/$FECHA" foto.jpg plano.png documento.odt
crear "$RAIZ/RESPUBLICO/$FECHA/coleccion" disco.flac rola.mp3 peli.mkv

info "datos de prueba en $RAIZ"
printf '\n'
du -sh "$RAIZ"/* 2>/dev/null
