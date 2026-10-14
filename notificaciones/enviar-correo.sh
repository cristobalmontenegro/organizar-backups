#!/usr/bin/env bash
set -euo pipefail

enviar_correo() {
  local asunto="$1" html="$2" destino="${3:-}"
  if [[ -z "$destino" ]]; then
    echo "enviar_correo: falta el destino" >&2
    return 1
  fi
  if ! command -v msmtp >/dev/null 2>&1; then
    echo "enviar_correo: msmtp no está instalado" >&2
    return 1
  fi
  {
    echo "Subject: $asunto"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    printf "%b" "$html"
  } | msmtp "$destino"
}

es_principal() {
  [[ "${BASH_SOURCE[0]}" == "${0}" ]]
}

if es_principal; then
  asunto="${1:?uso: enviar-correo.sh ASUNTO DESTINO [< archivo.html]}"
  destino="${2:?uso: enviar-correo.sh ASUNTO DESTINO [< archivo.html]}"
  html="$(cat)"
  if [[ -z "$html" ]]; then
    echo "uso: enviar-correo.sh ASUNTO DESTINO [< archivo.html]" >&2
    exit 2
  fi
  enviar_correo "$asunto" "$html" "$destino"
  echo "Correo enviado a $destino"
fi