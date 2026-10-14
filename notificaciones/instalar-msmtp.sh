#!/usr/bin/env bash
set -euo pipefail

AQUI="$(dirname "$(readlink -f "$0")")"
PLANTILLA="${AQUI}/msmtprc.template"
DESTINO="${HOME}/.msmtprc"

if ! command -v msmtp >/dev/null 2>&1; then
  if command -v apt >/dev/null 2>&1; then
    echo "Instalando msmtp + msmtp-mta + ca-certificates..."
    sudo apt update
    sudo apt install -y msmtp msmtp-mta ca-certificates
  else
    echo "msmtp no está instalado y el gestor no es apt." >&2
    echo "Instala 'msmtp', 'msmtp-mta' y 'ca-certificates' y vuelve a correr." >&2
    exit 1
  fi
fi

if [[ -e "$DESTINO" ]]; then
  echo "Ya existe $DESTINO — no lo toco (bórralo si quieres regenerarlo)."
else
  read -rp "Cuenta de envío [admin@ejemplo.com]: " cuenta
  cuenta="${cuenta:-admin@ejemplo.com}"
  read -rsp "App Password de Gmail (16 letras): " apppass
  echo
  if [[ -z "$apppass" ]]; then
    echo "Sin App Password no se puede configurar." >&2
    exit 1
  fi
  sed -e "s|CAMBIAR@ejemplo.com|${cuenta}|g" \
      -e "s|CAMBIAR_APP_PASSWORD|${apppass}|g" \
      "$PLANTILLA" > "$DESTINO"
  chmod 600 "$DESTINO"
  echo "Config creada: $DESTINO (permisos 600)."
fi

echo "Probando conexión con el servidor SMTP..."
msmtp --serverinfo >/dev/null

read -rp "Correo de prueba a: " prueba
if [[ -n "$prueba" ]]; then
  printf 'Subject: prueba msmtp (%s)\n\nCorreo de prueba enviado desde %s.\n' \
    "$(date '+%F %T')" "$(hostname)" | msmtp "$prueba"
  echo "Enviado. Revisa la bandeja de $prueba."
fi