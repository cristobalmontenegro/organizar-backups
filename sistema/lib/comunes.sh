#!/usr/bin/env bash

[[ -n "${_COMUNES_CARGADA:-}" ]] && return 0
_COMUNES_CARGADA=1

DIR_SISTEMA="${DIR_SISTEMA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="${CONFIG:-$DIR_SISTEMA/perfiles.json}"
LOG_DIR="${LOG_DIR:-$DIR_SISTEMA/logs}"

# --- color (ANSI), activo sólo en terminal y si no hay NO_COLOR ---
C_RESET= C_NEG= C_DIM= C_ROJO= C_VERDE= C_AMAR= C_CIAN= C_MAG=
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\e[0m';  C_NEG=$'\e[1m'; C_DIM=$'\e[2m'
  C_ROJO=$'\e[31m'; C_VERDE=$'\e[32m'; C_AMAR=$'\e[33m'
  C_CIAN=$'\e[36m'; C_MAG=$'\e[35m'
fi
rojo() { printf '%s%s%s' "$C_ROJO" "$1" "$C_RESET"; }
verde() { printf '%s%s%s' "$C_VERDE" "$1" "$C_RESET"; }
amarillo() { printf '%s%s%s' "$C_AMAR" "$1" "$C_RESET"; }
cian() { printf '%s%s%s' "$C_CIAN" "$1" "$C_RESET"; }
neg() { printf '%s%s%s' "$C_NEG" "$1" "$C_RESET"; }
dim() { printf '%s%s%s' "$C_DIM" "$1" "$C_RESET"; }

log() {
  local tag="$1" col=""
  shift
  case "$tag" in
    INFO) col="$C_CIAN" ;;
    AVISO) col="$C_AMAR" ;;
    ERROR) col="$C_ROJO" ;;
  esac
  if [[ -t 1 ]]; then
    printf '%s%s%s [%s] %s%s\n' "$C_DIM" "$(date '+%Y-%m-%d %H:%M:%S')" "$C_RESET" "$col$tag$C_RESET" "$col${*}$C_RESET"
  else
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$tag" "$*"
  fi
}
info() { log INFO "$@"; }
aviso() { log AVISO "$@" >&2; }
erro() { log ERROR "$@" >&2; }
fatal() { erro "$@"; exit 1; }

require() {
  local h
  for h in "$@"; do
    command -v "$h" >/dev/null 2>&1 || fatal "falta la herramienta: $h"
  done
}

configurar() {
  [[ -f "$CONFIG" ]] || fatal "no existe la configuración: $CONFIG"
  require jq
  RAIZ="${RAIZ:-$(raiz_datos "${RESPALDO_MODO:-prod}")}"
  export RAIZ
}

g() { jq -r --arg k "$1" '.global[$k] // empty' "$CONFIG"; }
s14() { jq -r --arg k "$1" '.servidor14[$k] // empty' "$CONFIG"; }
p_get() { jq -r --arg p "$1" --arg k "$2" '.perfiles[$p][$k] // empty' "$CONFIG"; }

lista_perfiles() { jq -r '.perfiles | keys[]' "$CONFIG"; }

existe_perfil() { jq -e --arg p "$1" '.perfiles | has($p)' "$CONFIG" >/dev/null 2>&1; }

raiz_datos() {
  local modo="${1:-prod}"
  if [[ "$modo" == "pruebas" ]]; then
    jq -r '.global.raiz_pruebas' "$CONFIG"
  else
    jq -r '.global.raiz_datos' "$CONFIG"
  fi
}

destino() { printf '%s/%s' "${RAIZ}" "$1"; }

origen() {
  local rel
  rel="$(p_get "$1" origen_s14)"
  [[ -z "$rel" || "$rel" == "null" ]] && return 1
  printf '%s/%s' "$(s14 raiz)" "$rel"
}

fecha_hoy() { date +%F; }

bytes() {
  if [[ -d "$1" ]]; then
    du -sb "$1" 2>/dev/null | cut -f1
  elif [[ -f "$1" ]]; then
    stat -c %s "$1" 2>/dev/null
  else
    echo 0
  fi
}

humano() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B --format='%.1f' "${1:-0}"
  else
    echo "${1:-0}B"
  fi
}

libre_bytes() { df -B1 --output=avail "$1" 2>/dev/null | tail -1 | tr -d ' '; }

espacio_libre() {
  local d="${1:-$RAIZ}"
  local raiz="${d%/}"
  raiz="$(dirname "$raiz")"
  while [[ ! -d "$raiz" && "$raiz" != "/" ]]; do raiz="$(dirname "$raiz")"; done
  libre_bytes "$raiz"
}

volumen_en_bytes() {
  local v num suf
  v="$(g volumen)"
  num="${v%%[kKmMgG]}"
  if [[ "$num" == "$v" ]]; then suf=""; else suf="${v: -1}"; fi
  case "$suf" in
    k | K) num="${num}000" ;;
    m | M) num="${num}000000" ;;
    g | G) num="${num}000000000" ;;
    *) num="${num}000" ;;
  esac
  printf '%s\n' "$num"
}

volumen_bytes() { volumen_en_bytes; }

ciclo() { cat "$DIR_SISTEMA/estado/ciclo" 2>/dev/null || fecha_hoy; }

asegurar_estado() {
  mkdir -p "$DIR_SISTEMA/estado" "$DIR_SISTEMA/logs"
  [[ -f "$DIR_SISTEMA/estado/modo" ]] || printf 'seco\n' > "$DIR_SISTEMA/estado/modo"
  [[ -f "$DIR_SISTEMA/estado/plano" ]] || printf 'frente\n' > "$DIR_SISTEMA/estado/plano"
}

# enganche de progreso para segundo plano (la versión funcional vive en background.sh)
prog_fase() { :; }

esperar_enter() {
  printf '\n  %sPulsa <Enter> para volver al menú…%s ' "$C_DIM" "$C_RESET"
  read -r _ 2>/dev/null || true
  printf '\n'
}

modo_actual() { cat "$DIR_SISTEMA/estado/modo" 2>/dev/null || printf 'seco\n'; }

# plano de ejecución: frente = espera en consola; fondo = segundo plano.
plano_actual() { cat "$DIR_SISTEMA/estado/plano" 2>/dev/null || printf 'frente\n'; }

plano_etiqueta() {
  if [[ "$(plano_actual)" == "fondo" ]]; then
    printf '%s%sFONDO (segundo plano)%s' "$C_AMAR" "$C_NEG" "$C_RESET"
  else
    printf '%sFRENTE (espera en consola)%s' "$C_CIAN" "$C_RESET"
  fi
}

plano_cambiar() {
  if [[ "$(plano_actual)" == "fondo" ]]; then
    printf 'frente\n' > "$DIR_SISTEMA/estado/plano"
    info "plano FRENTE activado (pull y procesar esperan en consola)"
  else
    printf 'fondo\n' > "$DIR_SISTEMA/estado/plano"
    info "plano FONDO activado (pull y procesar se van a segundo plano)"
  fi
}

modo_etiqueta() {
  if [[ "$(modo_actual)" == "real" ]]; then
    printf '%s%sREAL (¡EJECUTA DE VERDAD!)%s' "$C_ROJO" "$C_NEG" "$C_RESET"
  else
    printf '%sSECO (dry-run, no toca nada)%s' "$C_VERDE" "$C_RESET"
  fi
}

modo_cambiar() {
  if [[ "$(modo_actual)" == "real" ]]; then
    printf 'seco\n' > "$DIR_SISTEMA/estado/modo"
    info "modo SECO activado (dry-run, no toca nada)"
  else
    local r
    printf '\n  %s%s¡CUIDADO!%s%s En modo REAL, procesar, pull y el fondo EJECUTAN de verdad\n' \
      "$C_ROJO" "$C_NEG" "$C_RESET"
    printf '  y borran la fuente al terminar. Es para usarlo conscientemente.\n'
    read -rp '  Para activarlo escribe la palabra "real": ' r
    if [[ "$r" == "real" ]]; then
      printf 'real\n' > "$DIR_SISTEMA/estado/modo"
      info "modo REAL activado"
    else
      aviso "no confirmado: se queda en SECO"
    fi
  fi
}
