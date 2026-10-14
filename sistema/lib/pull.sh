#!/usr/bin/env bash

[[ -n "${_PULL_CARGADA:-}" ]] && return 0
_PULL_CARGADA=1

PULL_HOY="${PULL_HOY:-}"

rsync_excluir() {
  jq -r '.global.pull_excluir[]?' "$CONFIG" 2>/dev/null
}

# Patrones rsync para los filtros incluir/excluir del perfil (una opción por línea).
# Se anclan a la raíz de la transferencia (/) = raíz del contenedor.
pull_filtros() {
  local p="$1" x
  local -a inc=() exc=()
  mapfile -t inc < <(lista_config "$p" incluir)
  mapfile -t exc < <(lista_config "$p" excluir)
  if [[ ${#inc[@]} -gt 0 ]]; then
    for x in "${inc[@]}"; do
      printf '%s\n' "--include=/$x/***" "--include=/$x"
    done
    printf '%s\n' '--exclude=*'
  fi
  for x in "${exc[@]}"; do
    printf '%s\n' "--exclude=/$x"
  done
}

pull_destino() {
  local p="$1" hoy="${2:-}"
  local d
  d="$(destino "$p")"
  if [[ "$(bool_config "$p" carpeta_fecha)" == "true" ]]; then
    [[ -n "$hoy" ]] || hoy="$(fecha_hoy)"
    d="$d/$hoy"
  fi
  printf '%s\n' "$d"
}

pull_orden() {
  local p="$1" d="$2" o x
  o="$(origen "$p")" || return 1
  printf 'rsync -aH --partial --numeric-ids --info=stats2'
  while IFS= read -r x; do
    [[ -n "$x" ]] && printf ' --exclude=%q' "$x"
  done < <(rsync_excluir)
  while IFS= read -r x; do
    [[ -n "$x" ]] && printf ' %q' "$x"
  done < <(pull_filtros "$p")
  printf ' -e ssh %q:%q/ %q\n' \
    "$(s14 usuario)@$(s14 host)" "$o" "$d/"
}

pull_resumen() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  printf '<pre style="font-family:monospace;font-size:12px;background:#f7f7f7;padding:8px">'
  grep -E 'Number of files:|Number of regular files transferred:|Total file size:|Total transferred file size:|Literal data:|rsync: ' "$f" \
    | sed 's/[<>&]/ /g' | sed 's/^/* /'
  printf '</pre>'
}

pull_perfil() {
  local p="$1" real="${2:-0}"
  local o d hoy
  if ! o="$(origen "$p")"; then
    aviso "$p: perfil manual, se omite el pull (no hay origen en el Servidor 14)"
    return 0
  fi
  hoy="${PULL_HOY:-$(fecha_hoy)}"
  d="$(pull_destino "$p" "$hoy")"

  printf '\n  --- pull %s (%s) ---\n' "$p" "$([[ "$real" == "1" ]] && echo REAL || echo dry-run)"
  printf '  ORIGEN  : %s@%s:%s\n' "$(s14 usuario)" "$(s14 host)" "$o"
  printf '  DESTINO : %s\n' "$d"
  printf '  ORDEN   : %s\n' "$(pull_orden "$p" "$d")"

  [[ "$real" == "1" ]] || { aviso "sin --ejecutar/--real: no se ejecutó nada"; return 0; }

  require rsync ssh
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 \
      "$(s14 usuario)@$(s14 host)" true >/dev/null 2>&1; then
    aviso "$p: sin acceso SSH a $(s14 host)"
    avisar_pull "$p" "$d" "<p><b>FALLO:</b> sin acceso SSH a $(s14 host)</p>"
    return 1
  fi

  mkdir -p "$d"
  local logf="$LOG_DIR/${p}-pull.log"
  local -a opts=(-aH --partial --numeric-ids --info=stats2 -e ssh)
  while IFS= read -r x; do
    [[ -n "$x" ]] && opts+=("--exclude=$x")
  done < <(rsync_excluir)
  while IFS= read -r x; do
    [[ -n "$x" ]] && opts+=("$x")
  done < <(pull_filtros "$p")

  if ! rsync "${opts[@]}" "$(s14 usuario)@$(s14 host):$o/" "$d/" 2>&1 | tee "$logf"; then
    aviso "$p: pull falló (ver $logf)"
    avisar_pull "$p" "$d" "<p><b>FALLO:</b> rsync terminó con error</p>$(pull_resumen "$logf")"
    return 1
  fi

  local info_txt
  info_txt="$(grep -E 'Total transferred file size:' "$logf" | sed 's/^/* /;s/$/<br>/' || true)"
  printf '      pull terminado: %s\n' "$d"
  grep -E 'Total transferred file size:|Number of regular files transferred:' "$logf" | sed 's/^/      /' || true
  avisar_pull "$p" "$d" "<p>ciclo $(ciclo)</p>$info_txt$(pull_resumen "$logf")"
}
