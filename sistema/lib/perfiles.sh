#!/usr/bin/env bash
# Gestión de perfiles (carpetas a respaldar) sin editar el JSON a mano.
#   perfil_crear     → añade una carpeta/perfil nuevo a perfiles.json
#   perfil_quitar    → quita la definición (NUNCA borra datos)
#   perfil_descubrir → lista carpetas sin perfil y (asistente) ofrece crearlos
[[ -n "${_PERFILES_CARGADA:-}" ]] && return 0
_PERFILES_CARGADA=1

# Nombre seguro = lo que acaba en nombres de fichero (RESMAIL_<fecha>_<x>).
perfil_nombre_valido() { [[ "${1:-}" =~ ^[A-Z][A-Z0-9_]*$ ]]; }

# perfil_crear <NOMBRE> [<origen_s14>] [<manual 0|1>] [<como PERFIL>] [<silencioso 0|1>]
perfil_crear() {
  local nombre="${1:-}" origen="${2:-}" manual="${3:-0}" como="${4:-}" callar="${5:-0}"
  [[ -n "$nombre" ]] || { aviso "falta el nombre del perfil"; return 1; }
  perfil_nombre_valido "$nombre" || {
    aviso "nombre inválido: usa MAYÚSCULAS, números y _ (ej. RESINVENTO)"; return 1; }
  existe_perfil "$nombre" && { aviso "ya existe el perfil: $nombre"; return 1; }

  local filtro
  if [[ -n "$como" ]]; then
    existe_perfil "$como" || { aviso "--como: perfil desconocido: $como"; return 1; }
    filtro='.perfiles[$como] as $b | .perfiles[$p] = ($b | del(.origen_s14, .fuente, .nota, .ojo))'
  else
    filtro='.plantilla as $pl | .perfiles[$p] = (reduce $claves[] as $k ({}; .[$k] = $pl[$k]))'
  fi
  local post
  post='| if $manual == 1 then .perfiles[$p].origen_s14 = null | .perfiles[$p].fuente = "manual" else .perfiles[$p].origen_s14 = $origen end'

  local claves; claves="$(cfg_claves_carpeta | jq -R . | jq -s -c .)"
  jq --arg p "$nombre" --arg origen "$origen" --argjson manual "$manual" \
     --arg como "$como" --argjson claves "$claves" \
     "$filtro $post" "$CONFIG" | cfg_aplicar || return 1

  # aviso (no bloquea): ¿existe el origen en el S14?
  if [[ "$manual" != "1" && -n "$origen" ]]; then
    if ssh -n -o BatchMode=yes -o ConnectTimeout=6 \
        "$(s14 usuario)@$(s14 host)" true >/dev/null 2>&1; then
      ssh -n -o BatchMode=yes "$(s14 usuario)@$(s14 host)" \
        "test -e '$(s14 raiz)/$origen'" >/dev/null 2>&1 \
        || aviso "$nombre: el origen $(s14 raiz)/$origen no existe todavía en el S14"
    fi
  fi
  [[ "$callar" == "1" ]] || info "perfil creado: $nombre (origen: $([[ "$manual" == "1" ]] && echo manual || echo "${origen:-?}"))"
  return 0
}

# perfil_quitar <NOMBRE> [<silencioso 0|1>]
perfil_quitar() {
  local nombre="${1:-}" callar="${2:-0}"
  [[ -n "$nombre" ]] || { aviso "falta el nombre del perfil"; return 1; }
  existe_perfil "$nombre" || { aviso "perfil desconocido: $nombre"; return 1; }
  local d o; d="$(destino "$nombre")"
  o="$(origen "$nombre" 2>/dev/null || true)"
  printf '\n  perfil     : %s\n' "$nombre"
  printf '  origen S14 : %s\n' "${o:-'(manual)'}"
  if [[ -d "$d" ]]; then
    printf '  destino    : %s  %s(¡tiene datos!)%s\n' "$d" "$C_AMAR" "$C_RESET"
  else
    printf '  destino    : %s  (sin datos)\n' "$d"
  fi
  printf '  %sSe quita sólo la definición del JSON; la carpeta de datos NO se toca.%s\n' "$C_AMAR" "$C_RESET"
  [[ "$callar" == "1" ]] || _cfg_confirmar || { aviso "cancelado"; return 0; }
  jq --arg p "$nombre" 'del(.perfiles[$p])' "$CONFIG" | cfg_aplicar || return 1
  [[ "$callar" == "1" ]] || info "perfil quitado: $nombre"
}

# Nombres que nunca son carpetas a respaldar (basura de sistema)
perfil_ignorar() {
  local n="${1:-}" x
  case "$n" in lost+found | .trash | files_trashbin | .snapshot | '@eaDir') return 0 ;; esac
  while IFS= read -r x; do [[ -n "$x" && "$x" == "$n" ]] && return 0; done \
    < <(jq -r '.global.pull_excluir[]?' "$CONFIG" 2>/dev/null)
  return 1
}

# perfil_descubrir [listar]  → carpetas sin perfil (S14 + local); en modo
# interactivo pregunta y crea (asistente). 'listar' = sólo mostrar.
perfil_descubrir() {
  local modo="${1:-}"
  local s14user s14host s14raiz
  s14user="$(s14 usuario)"; s14host="$(s14 host)"; s14raiz="$(s14 raiz)"

  # --- qué ya está declarado ---
  local -a decl_ori=() x
  while IFS= read -r x; do
    x="$(p_get "$x" origen_s14)"
    [[ -n "$x" && "$x" != "null" ]] && decl_ori+=("${x%%/*}")
  done < <(lista_perfiles)

  local -a cand=() tipo=() ruta=()
  local i n ya

  # --- candidatos del Servidor 14 (una llamada) ---
  if ssh -n -o BatchMode=yes -o ConnectTimeout=6 "$s14user@$s14host" true >/dev/null 2>&1; then
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      perfil_ignorar "$n" && continue
      ya=0; for i in "${decl_ori[@]}"; do [[ "$i" == "$n" ]] && ya=1; done
      [[ "$ya" == 1 ]] && continue
      cand+=("$n"); tipo+=("S14"); ruta+=("$s14raiz/$n")
    done < <(ssh -n -o BatchMode=yes "$s14user@$s14host" "ls -1d '$s14raiz'/*/ 2>/dev/null" \
             | sed 's:/$::' | xargs -r -n1 basename 2>/dev/null | grep -v '^$')
  else
    aviso "sin acceso SSH al Servidor 14: no se listan candidatos remotos"
  fi

  # --- candidatos locales (carpetas en RAIZ sin perfil) ---
  if [[ -d "$RAIZ" ]]; then
    for x in "$RAIZ"/*/; do
      [[ -d "$x" ]] || continue
      n="$(basename "$x")"
      existe_perfil "$n" && continue
      perfil_ignorar "$n" && continue
      cand+=("$n"); tipo+=("LOCAL"); ruta+=("${x%/}")
    done
  fi

  if [[ ${#cand[@]} -eq 0 ]]; then
    printf '  No hay carpetas nuevas sin perfil.\n'
    return 0
  fi

  printf '\n  %sCarpetas sin perfil:%s\n' "$C_NEG" "$C_RESET"
  for i in "${!cand[@]}"; do
    printf '   %2d) [%s] %-16s %s\n' "$((i + 1))" "${tipo[$i]}" "${cand[$i]}" "${ruta[$i]}"
  done
  [[ "$modo" == "listar" ]] && return 0
  if [[ ! -t 0 ]]; then
    aviso "sin terminal: sólo se lista. Usa 'descubrir' desde la consola para el asistente."
    return 0
  fi

  printf '\n  %sAsistente%s: Enter o "n" en "¿Crear perfil?" = no añadir\n' "$C_NEG" "$C_RESET"
  local r nombre como origen
  for i in "${!cand[@]}"; do
    printf '\n  [%s] %s\n' "${tipo[$i]}" "${ruta[$i]}"
    read -rp '    ¿Crear perfil? [s/N] ' r
    case "$r" in s | S | si | sí | SI | y | Y) ;; *) continue ;; esac

    nombre="${cand[$i]}"
    read -rp "    nombre del perfil [$nombre]: " r; [[ -n "$r" ]] && nombre="$r"
    if ! perfil_nombre_valido "$nombre"; then
      aviso "nombre inválido (MAYÚSCULAS, números, _): se omite"; continue
    fi
    read -rp '    ¿copiar interruptores de otro perfil? (nombre o Enter=plantilla): ' como

    if [[ "${tipo[$i]}" == "S14" ]]; then
      origen="${cand[$i]}"
      read -rp "    origen en el S14 [$origen]: " r; [[ -n "$r" ]] && origen="$r"
      perfil_crear "$nombre" "$origen" 0 "$como"
    else
      read -rp '    ¿enlazarlo a un origen del S14? (ruta o Enter=manual): ' r
      if [[ -n "$r" ]]; then perfil_crear "$nombre" "$r" 0 "$como"
      else perfil_crear "$nombre" "" 1 "$como"; fi
    fi
  done
  printf '\n'
}

# Submenú interactivo
cmd_carpetas() {
  [[ -t 0 ]] || { perfil_descubrir listar; return 0; }
  local op n
  while true; do
    printf '\n%s=== CARPETAS A RESPALDAR ===%s\n' "$C_NEG" "$C_RESET"
    printf '  perfiles definidos: %s\n' "$(lista_perfiles | wc -l)"
    PS3="$(cian '  Opción (X = volver): ')"
    select op in \
      "Listar perfiles" \
      "Añadir una carpeta (perfil nuevo)" \
      "Quitar un perfil" \
      "Descubrir carpetas sin perfil (asistente)" \
      "Volver"
    do
      case "$REPLY" in
        1) cmd_listar ;;
        2)
          read -rp '  Nombre del perfil (MAYÚSCULAS, ej. RESINVENTO): ' n
          [[ -n "$n" ]] || { aviso "cancelado"; break; }
          local origen
          read -rp '  Ruta en el S14 relativa a /mnt/bak (Enter = manual, sin pull): ' origen
          if [[ -n "$origen" ]]; then perfil_crear "$n" "$origen" 0 ""
          else perfil_crear "$n" "" 1 ""; fi
          ;;
        3)
          _elegir_perfil 'Quitar ¿qué perfil?' && perfil_quitar "$ELEGIDO"
          ;;
        4) perfil_descubrir ;;
        5 | x | X | q | Q | salir) return 0 ;;
        *) printf '  ? opción no válida\n' ;;
      esac
      break
    done
    esperar_enter
  done
}
