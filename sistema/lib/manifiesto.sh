#!/usr/bin/env bash

[[ -n "${_MANIFIESTO_CARGADA:-}" ]] && return 0
_MANIFIESTO_CARGADA=1

VER_OK="${VER_OK:-0}"
VER_MAL="${VER_MAL:-0}"

dir_quemados() { printf '%s/quemados/%s\n' "$(dirname "$RAIZ")" "$(ciclo)"; }
ruta_manifiesto() { printf '%s/MANIFIESTO.csv\n' "$(dir_quemados)"; }

manifiesto_cabecera() {
  local f
  f="$(ruta_manifiesto)"
  mkdir -p "$(dirname "$f")"
  if [[ ! -f "$f" ]]; then
    printf 'ciclo,fecha,perfil,juego,volumenes,bytes,sha256,estado\n' >"$f"
  fi
}

sha_set() {
  local f="$1"
  [[ -f "$f" ]] || { printf '-\n'; return 0; }
  sha256sum "$f" | cut -d' ' -f1
}

bytes_set() {
  local base="$1" dir name n
  dir="$(dirname "$base")"
  name="$(basename "$base")"
  n="$(find "$dir" -maxdepth 1 -type f \
    \( -name "$name.7z*" -o -name "$name.rar*" -o -name "$name.part*.rar" -o -name "$name.r[0-9][0-9]" \) \
    ! -name '*.sha256' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')"
  printf '%s\n' "$n"
}

manifiesto_registrar() {
  local p="$1" juego="$2" vol="$3" bytes="$4" sha="$5" estado="${6:-OK}"
  local f linea
  manifiesto_cabecera
  f="$(ruta_manifiesto)"
  linea="$(printf '%s,%s,%s,%s,%s,%s,%s,%s' \
    "$(ciclo)" "$(fecha_hoy)" "$p" "$(basename "$juego")" "$vol" "$bytes" "$sha" "$estado")"
  if ! grep -qxF "$linea" "$f" 2>/dev/null; then
    printf '%s\n' "$linea" >>"$f"
  fi
  printf '%s\n' "$linea"
}

manifiesto_leer() {
  local p="${1:-}" f
  f="$(ruta_manifiesto)"
  [[ -f "$f" ]] || { printf '(sin manifiesto)\n'; return 0; }
  if [[ -n "$p" ]]; then
    awk -F, -v p="$p" 'NR==1 || $3==p' "$f"
  else
    cat "$f"
  fi
}

manifiesto_total() {
  local p="${1:-}" f
  f="$(ruta_manifiesto)"
  [[ -f "$f" ]] || { printf '0 0 0\n'; return 0; }
  awk -F, -v p="$p" '
    NR>1 && (p=="" || $3==p) && $8=="OK" {n++; v+=$5; b+=$6}
    END {printf "%d %d %d\n", n+0, v+0, b+0}' "$f"
}
