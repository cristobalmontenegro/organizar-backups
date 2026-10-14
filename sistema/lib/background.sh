#!/usr/bin/env bash

[[ -n "${_BACKGROUND_CARGADA:-}" ]] && return 0
_BACKGROUND_CARGADA=1

# Dos trabajos de fondo independientes, con lock y estado propios:
#   procesar → estado/bg-procesar.lock , estado/bg-procesar.json , logs/bg-procesar.log
#   pull     → estado/bg-pull.lock     , estado/bg-pull.json     , logs/bg-pull.log
# Locks separados: un pull de un perfil puede correr mientras se procesa otro.
BG_TIPOS=(procesar pull)
BG_VIOLETA=5   # segundos entre actualizaciones de %

bg_lock_de() { printf '%s/estado/bg-%s.lock\n' "$DIR_SISTEMA" "$1"; }
bg_json_de() { printf '%s/estado/bg-%s.json\n' "$DIR_SISTEMA" "$1"; }
bg_log_de()  { printf '%s/logs/bg-%s.log\n'  "$DIR_SISTEMA" "$1"; }

# valores por defecto (para que prog_fase no falle bajo set -u)
BG_TIPO="${BG_TIPO:-procesar}"
BG_LOCK="$(bg_lock_de procesar)"
BG_JSON="$(bg_json_de procesar)"
BG_LOG="$(bg_log_de procesar)"

bg_pid() { jq -r '.pid // 0' "$(bg_json_de "${1:-procesar}")" 2>/dev/null; }

# bg_ocupado <tipo> → 0 (cierto) si hay un trabajo de ese tipo en ejecución.
bg_ocupado() {
  local l
  l="$(bg_lock_de "${1:-$BG_TIPO}")"
  flock -n "$l" true 2>/dev/null && return 1 || return 0
}

bg_escribir() {
  local json="$1"
  printf '%s\n' "$json" >"$BG_JSON.tmp" && mv "$BG_JSON.tmp" "$BG_JSON"
}

# enganche: las fases de procesar() se reflejan en el json del trabajo en curso
prog_fase() {
  local fase="$1" pct
  [[ -f "$BG_JSON" ]] || return 0
  case "$fase" in
    preflight) pct=1 ;;
    limpiar)   pct=3 ;;
    empaquetar) pct=5 ;;
    verificar) pct=93 ;;
    borrado)   pct=97 ;;
    fin)       pct=100 ;;
    fallo)     pct=100 ;; # el monitor verá el log
    *)         return 0 ;;
  esac
  jq --arg f "$fase" --argjson p "$pct" '.fase=$f | .porcentaje=$p' "$BG_JSON" \
    >"$BG_JSON.tmp" && mv "$BG_JSON.tmp" "$BG_JSON"
}

objetivo_para() {
  # bytes de salida esperados para la cola completa
  local p tot=0
  for p in "$@"; do tot=$((tot + $(salida_estimada "$p"))); done
  printf '%d\n' "$tot"
}

producido_de() {
  # bytes ya generados como sets del perfil en su destino
  local d
  d="$(destino "$1")"
  [[ -d "$d" ]] || { printf '0\n'; return 0; }
  find "$d" -maxdepth 1 -type f -name "${1}_*" -printf '%s\n' 2>/dev/null \
    | awk '{s+=$1} END{print s+0}'
}

actualizar_porcentaje() {
  local prod obj pct fase
  read -r obj < <(jq -r '.objetivo // 0' "$BG_JSON")
  read -r fase < <(jq -r '.fase // "empaquetar"' "$BG_JSON")
  prod=0
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && prod=$((prod + $(producido_de "$p")))
  done < <(jq -r '.cola[]' "$BG_JSON")
  case "$fase" in
    empaquetar)
      if [[ "$obj" -gt 0 ]]; then
        pct=5
        [[ "$prod" -gt 0 ]] && pct=$((5 + 88 * prod / obj))
        [[ "$pct" -gt 90 ]] && pct=90
      else
        pct=50
      fi
      ;;
    fin)   pct=100 ;;
    fallo) pct=100 ;;
    *)     read -r pct < <(jq -r '.porcentaje // 0' "$BG_JSON") ;;
  esac
  jq --argjson p "$pct" --argjson pp "$prod" \
    '.porcentaje=$p | .producido=$pp' "$BG_JSON" >"$BG_JSON.tmp" \
    && mv "$BG_JSON.tmp" "$BG_JSON"
}

bg_vigilante() {
  local objetivo
  while :; do
    if [[ ! -f "$BG_JSON" ]]; then return 0; fi
    if [[ "$(jq -r '.fase' "$BG_JSON" 2>/dev/null)" == "fin" ]]; then return 0; fi
    actualizar_porcentaje
    sleep "$BG_VIOLETA"
  done
}

# _fondo_ejecutar <procesar|pull> <PERFIL|all> [--real]
_fondo_ejecutar() {
  local tipo="$1"; shift
  local p real=0 fin
  if _es_real "$@"; then real=1; fi
  p="$(_perfil_de "$@")"
  [[ -n "$p" ]] || fatal "falta el perfil"
  validar_config || fatal "configuración incompleta"

  BG_TIPO="$tipo"
  BG_LOCK="$(bg_lock_de "$tipo")"
  BG_JSON="$(bg_json_de "$tipo")"
  BG_LOG="$(bg_log_de "$tipo")"

  exec 9>"$BG_LOCK" || return 1
  flock -n 9 || { aviso "ya hay un $tipo en segundo plano activo"; return 1; }

  local inicio
  inicio="$(date '+%F %T')"
  local -a cola=()

  if [[ "$tipo" == "pull" ]]; then
    if [[ "$p" == "ALL" ]]; then
      local x
      while IFS= read -r x; do
        if ! origen "$x" >/dev/null 2>&1; then
          aviso "$x: manual, sin origen en el S14, se omite"
          continue
        fi
        cola+=("$x")
      done < <(lista_perfiles)
    else
      existe_perfil "$p" || fatal "perfil desconocido: $p"
      origen "$p" >/dev/null 2>&1 \
        || { aviso "$p: perfil manual, no hay origen en el S14"; return 1; }
      cola=("$p")
    fi
    if [[ ${#cola[@]} -eq 0 ]]; then
      aviso "nada pendiente de pull"
      return 1
    fi
    local colajson
    colajson="$(printf '%s\n' "${cola[@]}" | jq -R . | jq -s -c .)"
    bg_escribir "{\"pid\":$$,\"inicio\":\"$inicio\",\"real\":$real,\"modo\":\"$([[ "$real" == "1" ]] && echo real || echo dry-run)\",\"cola\":$colajson,\"perfil\":\"${cola[0]}\",\"fase\":\"pull\",\"porcentaje\":0,\"producido\":0,\"objetivo\":0,\"indeterminado\":true}"

    local x rc=0
    for x in "${cola[@]}"; do
      printf '\n=== %s ===\n' "$x"
      jq --arg x "$x" '.perfil=$x' "$BG_JSON" >"$BG_JSON.tmp" && mv "$BG_JSON.tmp" "$BG_JSON"
      pull_perfil "$x" "$real" || rc=1
    done
    prog_fase fin
    jq --argjson rc "$rc" '.codigo=$rc' "$BG_JSON" >"$BG_JSON.tmp" && mv "$BG_JSON.tmp" "$BG_JSON"
    return "$rc"
  fi

  # --- procesar (cola ordenada por tamaño de salida) ---
  if [[ "$p" == "ALL" ]]; then
    local x b
    while IFS= read -r x; do
      if [[ ! -d "$(destino "$x")" ]]; then
        aviso "$x: sin datos, se omite"
        continue
      fi
      if procesado_completo "$x"; then
        aviso "$x: ya procesado (listo para quemar), se omite"
        continue
      fi
      b="$(salida_estimada "$x")"
      printf '%s %s\n' "$b" "$x"
    done < <(lista_perfiles) | sort -n | cut -d' ' -f2- >"$DIR_SISTEMA/estado/cola.txt"
    while IFS= read -r x; do cola+=("$x"); done <"$DIR_SISTEMA/estado/cola.txt"
    rm -f "$DIR_SISTEMA/estado/cola.txt"
  else
    existe_perfil "$p" || fatal "perfil desconocido: $p"
    [[ -d "$(destino "$p")" ]] || { aviso "$p: sin datos para procesar"; return 1; }
    if procesado_completo "$p"; then
      aviso "$p: ya procesado (listo para quemar), se omite"
      return 1
    fi
    cola=("$p")
  fi

  if [[ ${#cola[@]} -eq 0 ]]; then
    aviso "nada pendiente de procesar"
    return 1
  fi

  local colajson
  colajson="$(printf '%s\n' "${cola[@]}" | jq -R . | jq -s -c .)"
  bg_escribir "{\"pid\":$$,\"inicio\":\"$inicio\",\"real\":$real,\"modo\":\"$([[ "$real" == "1" ]] && echo real || echo dry-run)\",\"cola\":$colajson,\"perfil\":\"${cola[0]}\",\"fase\":\"arranque\",\"porcentaje\":0,\"producido\":0,\"objetivo\":$(objetivo_para "${cola[@]}")}"

  local vig=0
  bg_vigilante & vig=$!
  trap 'kill "${vig:-0}" 2>/dev/null' EXIT

  local x rc=0
  for x in "${cola[@]}"; do
    printf '\n=== %s ===\n' "$x"
    jq --arg x "$x" '.perfil=$x' "$BG_JSON" >"$BG_JSON.tmp" && mv "$BG_JSON.tmp" "$BG_JSON"
    procesar "$x" "$real" || rc=1
    actualizar_porcentaje
  done
  prog_fase fin
  jq --argjson rc "$rc" '.codigo=$rc' "$BG_JSON" >"$BG_JSON.tmp" && mv "$BG_JSON.tmp" "$BG_JSON"
  return "$rc"
}

# workers (los invoca fondo-iniciar con setsid)
cmd_fondo()      { _fondo_ejecutar procesar "$@"; }
cmd_fondo_pull() { _fondo_ejecutar pull "$@"; }

# cmd_fondo_iniciar [--pull] <PERFIL|all> [--real]
cmd_fondo_iniciar() {
  local tipo="procesar" p real=0 a
  local -a args=()
  for a in "$@"; do
    case "$a" in
      --pull) tipo="pull" ;;
      --fondo | --frente) ;;   # se aceptan y se ignoran (ya estamos en el lanzador)
      *) args+=("$a") ;;
    esac
  done
  p="${args[0]:-ALL}"
  if _es_real "${args[@]}"; then real=1; fi

  if bg_ocupado "$tipo"; then
    aviso "ya hay un $tipo en segundo plano activo; usa 'avance' para verlo"
    return 1
  fi
  validar_config || fatal "configuración incompleta"
  asegurar_estado
  local bjson; bjson="$(bg_json_de "$tipo")"
  rm -f "$bjson"   # el worker reescribe el estado al arrancar
  local modoarg=""
  [[ "$real" == "1" ]] && modoarg="--real"
  local sub="fondo"
  [[ "$tipo" == "pull" ]] && sub="fondo-pull"
  setsid -f bash "$DIR_SISTEMA/backup.sh" "$sub" "$p" $modoarg \
    >>"$(bg_log_de "$tipo")" 2>&1 < /dev/null
  local i
  for i in {1..120}; do
    [[ -f "$bjson" ]] && break
    sleep 0.5
  done
  if [[ -f "$bjson" ]]; then
    printf '  lanzado en segundo plano: %s (%s, pid %s, modo %s)\n' \
      "$p" "$tipo" "$(jq -r '.pid' "$bjson")" "$([[ "$real" == "1" ]] && echo real || echo dry-run)"
    local cola
    cola="$(jq -r '.cola[]' "$bjson" 2>/dev/null | paste -sd, -)"
    [[ -n "$cola" ]] && printf '  cola: %s\n' "$cola"
    printf '  seguimiento:  ./backup.sh avance\n'
  elif bg_ocupado "$tipo"; then
    aviso "arrancó; el estado todavía se está escribiendo (cola grande). 'avance' en unos segundos."
    return 0
  else
    aviso "no arrancó (revisa $(bg_log_de "$tipo"))"
    tail -5 "$(bg_log_de "$tipo")" 2>/dev/null
    return 1
  fi
}

barra() {
  local pct="$1" ancho=24 n i
  n=$((pct * ancho / 100))
  [[ "$n" -lt 0 ]] && n=0
  [[ "$n" -gt "$ancho" ]] && n=$ancho
  printf '['
  for ((i=0; i<n; i++)); do printf '#'; done
  for ((i=n; i<ancho; i++)); do printf '.'; done
  printf ']'
}

# Progreso del troceo por archivo (H.15.1): "completados total piezas bytes_pendientes".
# Devuelve 1 si el perfil no es de troceo por archivo (empaquetar=false + trocear_grandes).
_troceo_progreso() {
  local p="$1"
  [[ "$(bool_config "$p" empaquetar)" == "false" ]] || return 1
  [[ "$(bool_config "$p" trocear_grandes)" == "true" ]] || return 1
  local d pz
  d="$(destino "$p")"
  [[ -d "$d" ]] || return 1
  pz="$(volumen_en_bytes)"
  [[ "$pz" =~ ^[0-9]+$ && "$pz" -gt 0 ]] || return 1
  local -A stems=()
  local f dir base stem pend=0 pendbytes=0 piezas=0 sz
  # grandes con el original aún presente → pendientes de trocear
  while IFS= read -r -d '' f; do
    pend=$((pend + 1))
    sz="$(stat -c %s -- "$f" 2>/dev/null || echo 0)"
    pendbytes=$((pendbytes + sz))
  done < <(find "$d" -type f -size +"${pz}"c \
    ! -name '*.part*.rar' ! -name '*.sha256' ! -name "${p}_*" -print0 2>/dev/null)
  # piezas → stems distintos cuyo original ya no está = archivos ya troceados
  while IFS= read -r -d '' f; do
    piezas=$((piezas + 1))
    base="${f##*/}"
    dir="${f%/*}"
    stem="${base%.part*.rar}"
    [[ -e "$dir/$stem" ]] || stems["$dir/$stem"]=1
  done < <(find "$d" -type f -name '*.part*.rar' ! -name "${p}_*" -print0 2>/dev/null)
  local done=${#stems[@]}
  [[ "$((done + pend))" -gt 0 ]] || return 1
  printf '%s %s %s %s\n' "$done" "$((done + pend))" "$piezas" "$pendbytes"
}

# _avance_uno <tipo> → 0 si había estado que mostrar
_avance_uno() {
  local tipo="$1" json pid inicio modo perfil fase pct prod obj cod estado ind _td _tt _tp _tb
  json="$(bg_json_de "$tipo")"
  [[ -f "$json" ]] || return 1
  pid="$(jq -r '.pid // "-"' "$json")"
  inicio="$(jq -r '.inicio' "$json")"
  modo="$(jq -r '.modo' "$json")"
  perfil="$(jq -r '.perfil' "$json")"
  fase="$(jq -r '.fase' "$json")"
  pct="$(jq -r '.porcentaje // 0' "$json")"
  prod="$(jq -r '.producido // 0' "$json")"
  obj="$(jq -r '.objetivo // 0' "$json")"
  cod="$(jq -r '.codigo // "-"' "$json")"
  ind="$(jq -r '.indeterminado // false' "$json")"
  if [[ "$fase" == "fin" ]]; then
    estado="terminado${cod:+ (código $cod)}"
  elif bg_ocupado "$tipo"; then
    estado="en ejecución"
  else
    estado="detenido"
  fi
  printf '\n  %s--- %s ---%s  %s\n' "$C_NEG" "$tipo" "$C_RESET" "$estado"
  printf '  pid      : %s   inicio: %s   modo: %s\n' "$pid" "$inicio" "$modo"
  printf '  perfil   : %s (fase: %s)\n' "$perfil" "$fase"
  if [[ "$ind" == "true" ]]; then
    printf '  transfiriendo…  (sin %%: el pull no produce sets)\n'
  elif [[ "$tipo" == "procesar" && "$fase" == "empaquetar" ]] \
    && read -r _td _tt _tp _tb < <(_troceo_progreso "$perfil"); then
    # troceo por archivo: la barra de sets no avanza; mostramos archivos grandes
    local pctt=5
    [[ "$_tt" -gt 0 ]] && pctt=$((5 + 88 * _td / _tt))
    [[ "$pctt" -gt 93 ]] && pctt=93
    barra "$pctt"; printf ' %3s%% (troceo)\n' "$pctt"
    printf '  troceando: %s de %s archivos grandes  (%s piezas · %s pendientes)\n' \
      "$_td" "$_tt" "$_tp" "$(humano "$_tb")"
  else
    barra "$pct"; printf ' %3s%%\n' "$pct"
    printf '  producido: %s  de  %s\n' "$(humano "$prod")" "$(humano "$obj")"
  fi
  if bg_ocupado "$tipo"; then
    printf '  log:\n'
    tail -6 "$(bg_log_de "$tipo")" | sed 's/^/    /'
  fi
  return 0
}

cmd_avance() {
  local tipo alguno=0
  for tipo in "${BG_TIPOS[@]}"; do
    _avance_uno "$tipo" && alguno=1
  done
  [[ "$alguno" == 1 ]] || printf '  (sin antecedentes de segundo plano)\n'
}

cmd_cron() {
  local linea
  linea="30 3 * * 2-6 usuario cd \$HOME/sistema && ./backup.sh fondo all --real"
  printf '  cron (segundo plano diario de madrugada, martes a sábado):\n'
  printf '\n    %s\n\n' "$linea"
  printf '  Para instalarlo:  crontab -e   y pegar esa línea.\n'
  printf '  (No la instalo automáticamente: quemar es manual y un fondo prolongado puede competir con disco.)\n'
}
