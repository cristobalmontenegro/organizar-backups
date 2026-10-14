#!/usr/bin/env bash

[[ -n "${_FASES_CARGADA:-}" ]] && return 0
_FASES_CARGADA=1

EMPAQUETADOR="${EMPAQUETADOR:-}"
PERFIL_ACTUAL="${PERFIL_ACTUAL:-}"

# Contadores del procesado por unidad (H.12)
UNIDADES_N="${UNIDADES_N:-0}"
CER_OK="${CER_OK:-0}"
CER_MAL="${CER_MAL:-0}"

# Claves de ámbito "carpeta" → sólo en el perfil (sin herencia de global).
# Claves de ámbito "operativo" → siguen heredando de global.
_config_ambito() {
  local a
  if declare -F cfg_catalogo >/dev/null 2>&1; then
    a="$(cfg_catalogo | awk -F'|' -v k="$1" '$1==k{print $3; exit}')"
  fi
  if [[ -z "$a" ]]; then
    # clave que no está en el catálogo: si vive en global, es operativa
    jq -e --arg k "$1" '.global | has($k)' "$CONFIG" >/dev/null 2>&1 && a="operativo"
  fi
  printf '%s' "${a:-carpeta}"
}

lista_config() {
  local p="$1" k="$2"
  if [[ "$(_config_ambito "$k")" == "operativo" ]]; then
    jq -r --arg k "$k" '(.global[$k] // []) | .[]?' "$CONFIG" 2>/dev/null
  else
    jq -r --arg p "$p" --arg k "$k" '(.perfiles[$p][$k] // []) | .[]?' "$CONFIG" 2>/dev/null
  fi
}

bool_config() {
  local p="$1" k="$2"
  if [[ "$(_config_ambito "$k")" == "operativo" ]]; then
    jq -r --arg k "$k" '(.global[$k] // false)' "$CONFIG" 2>/dev/null
  else
    jq -r --arg p "$p" --arg k "$k" \
      'if ((.perfiles[$p] // {}) | has($k)) then .perfiles[$p][$k] else false end' \
      "$CONFIG" 2>/dev/null
  fi
}

# --- Filtros de subcarpetas por perfil (opcionales) -------------------------
# incluir / excluir son listas de patrones relativos a la carpeta que se empaqueta
# (el contenedor). Vacías o ausentes = todo (comportamiento clásico). Se aplican al
# pull (rsync), al empaquetado, al borrado, a la limpieza y al troceo por archivo.
perfil_tiene_filtros() {
  local p="$1"
  [[ "$(jq -r --arg p "$p" \
      '((.perfiles[$p].incluir // []) + (.perfiles[$p].excluir // [])) | length' \
      "$CONFIG" 2>/dev/null)" -gt 0 ]]
}

# ¿la ruta relativa <rel> (dentro del contenedor) se ignora? 0 = sí (filtrada).
_ruta_filtrada() {
  local p="$1" rel="${2:-}" pat
  [[ -n "$rel" && "$rel" != "." ]] || return 1
  local -a inc=() exc=()
  mapfile -t inc < <(lista_config "$p" incluir)
  mapfile -t exc < <(lista_config "$p" excluir)
  if [[ ${#inc[@]} -gt 0 ]]; then
    local hay=1
    for pat in "${inc[@]}"; do
      # shellcheck disable=SC2053
      [[ "$rel" == $pat || "$rel" == $pat/* ]] && { hay=0; break; }
    done
    [[ "$hay" == "0" ]] || return 0
  fi
  for pat in "${exc[@]}"; do
    # shellcheck disable=SC2053
    [[ "$rel" == $pat || "$rel" == $pat/* ]] && return 0
  done
  return 1
}

# ruta absoluta -> relativa al contenedor (quita $d/ y la carpeta AAAA-MM-DD)
_rel_container() {
  local p="$1" abs="$2" d rel first
  d="$(destino "$p")"
  rel="${abs#"$d"/}"
  first="${rel%%/*}"
  if [[ "$first" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then rel="${rel#"$first"/}"; fi
  printf '%s\n' "$rel"
}

# ¿la ruta absoluta <abs> cae bajo un filtro? 0 = sí (se ignora)
_abs_filtrada() { _ruta_filtrada "$1" "$(_rel_container "$1" "$2")"; }

# ítems a empaquetar de un contenedor: "." (todo) si no hay filtros —idéntico a
# antes— o los nombres de primer nivel que pasan el filtro.
_items_container() {
  local p="$1" c="$2" it
  if ! perfil_tiene_filtros "$p"; then printf '.\n'; return 0; fi
  while IFS= read -r it; do
    [[ -n "$it" ]] || continue
    [[ "$it" == "${p}_"* || "$it" == *.sha256 ]] && continue
    _ruta_filtrada "$p" "$it" && continue
    printf '%s\n' "$it"
  done < <(find "$c" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)
}

# depura un log de rutas (una por línea) descartando las filtradas
_filtrar_log() {
  local p="$1" logf="$2" tmp line
  [[ -f "$logf" ]] || return 0
  perfil_tiene_filtros "$p" || return 0
  tmp="$logf.filtrado"
  : >"$tmp"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    _abs_filtrada "$p" "$line" && continue
    printf '%s\n' "$line" >>"$tmp"
  done <"$logf"
  mv -f "$tmp" "$logf"
}

elegir_empaquetador() {
  [[ -n "$EMPAQUETADOR" ]] && return 0
  local t
  t="$(g empaquetador)"
  if [[ -n "$t" ]] && command -v "$t" >/dev/null 2>&1; then EMPAQUETADOR="$t"; return 0; fi
  if command -v rar >/dev/null 2>&1; then EMPAQUETADOR="rar"; return 0; fi
  if command -v 7z >/dev/null 2>&1; then EMPAQUETADOR="7z"; return 0; fi
  fatal "falta rar o 7z para empaquetar"
}

volumen_arg() {
  if [[ "$EMPAQUETADOR" == "rar" ]]; then g volumen; else volumen_en_bytes; fi
}

salida_estimada() {
  local p="$1" b f
  b="$(bytes "$(destino "$p")")"
  if [[ "$(bool_config "$p" empaquetar)" == "false" ]]; then
    printf '%s\n' "$b"
    return 0
  fi
  if [[ "$(bool_config "$p" comprimir)" == "false" ]]; then
    printf '%s\n' "$b"
    return 0
  fi
  f="$(g factor_salida)"
  [[ -n "$f" ]] || f=0.9
  awk -v b="$b" -v f="$f" 'BEGIN { printf "%d", b * f * 1.05 }'
}

preflight() {
  local p="$1" d b s l est col
  d="$(destino "$p")"
  if [[ ! -d "$d" ]]; then
    printf '  %-15s %9s %9s %9s  %s%s%s\n' "$p" "-" "-" "-" "$C_AMAR" "sin datos" "$C_RESET"
    return 1
  fi
  b="$(bytes "$d")"
  s="$(salida_estimada "$p")"
  l="$(espacio_libre "$d")"
  if [[ "$l" -ge "$s" ]]; then est="OK"; col="$C_VERDE"; else est="NO ALCANZA"; col="$C_ROJO"; fi
  printf '  %-15s %9s %9s %9s  %s%s%s\n' \
    "$p" "$(humano "$b")" "$(humano "$s")" "$(humano "$l")" "$col" "$est" "$C_RESET"
  [[ "$l" -ge "$s" ]]
}

_mostrar() {
  local etiqueta="$1" logf="$2" n="$3"
  printf '  %-20s %7s elementos\n' "$etiqueta" "$n"
  sed -n '1,4p' "$logf" | sed 's/^/      /'
  if [[ "$n" -gt 4 ]]; then printf '      … %s más -> %s\n' "$((n - 4))" "$logf"; fi
}

_cuenta() { wc -l <"$1" 2>/dev/null | tr -d ' '; }

aplicar_archivos() {
  local dir="$1" real="$2" etiqueta="$3"
  shift 3
  local logf n
  [[ $# -gt 0 ]] || return 0
  logf="$LOG_DIR/${PERFIL_ACTUAL}-$etiqueta.txt"
  local -a exc=() e
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    [[ "$e" == .* ]] || e=".$e"
    exc+=( ! -iname "*$e" )
  done < <(lista_config "$PERFIL_ACTUAL" conservar)
  find "$dir" -type f \( "$@" \) "${exc[@]}" -print >"$logf" 2>/dev/null || true
  _filtrar_log "$PERFIL_ACTUAL" "$logf"
  n="$(_cuenta "$logf")"
  [[ "$n" -gt 0 ]] || return 0
  _mostrar "$etiqueta" "$logf" "$n"
  if [[ "$real" == "1" ]]; then
    xargs -a "$logf" -d '\n' -r rm -f --
    printf '      borrados: %s\n' "$n"
  fi
}

aplicar_dirs() {
  local dir="$1" real="$2" etiqueta="$3"
  shift 3
  local logf n
  [[ $# -gt 0 ]] || return 0
  logf="$LOG_DIR/${PERFIL_ACTUAL}-$etiqueta.txt"
  find "$dir" -type d \( "$@" \) -print >"$logf" 2>/dev/null || true
  _filtrar_log "$PERFIL_ACTUAL" "$logf"
  n="$(_cuenta "$logf")"
  [[ "$n" -gt 0 ]] || return 0
  _mostrar "$etiqueta" "$logf" "$n"
  if [[ "$real" == "1" ]]; then
    xargs -a "$logf" -d '\n' -r rm -rf --
    printf '      borradas: %s carpetas\n' "$n"
  fi
}

aplicar_vacios() {
  local dir="$1" real="$2"
  local logf n
  logf="$LOG_DIR/${PERFIL_ACTUAL}-vacios.txt"
  find "$dir" -depth -type d -empty -print >"$logf" 2>/dev/null || true
  _filtrar_log "$PERFIL_ACTUAL" "$logf"
  n="$(_cuenta "$logf")"
  if [[ "$n" -gt 0 ]]; then
    _mostrar "carpetas vacias" "$logf" "$n"
    if [[ "$real" == "1" ]]; then
      while IFS= read -r d; do rmdir -- "$d" 2>/dev/null || true; done <"$logf"
      printf '      borradas: %s\n' "$n"
    fi
  fi
  local logf2
  logf2="$LOG_DIR/${PERFIL_ACTUAL}-vacias.txt"
  find "$dir" -type f -empty -print >"$logf2" 2>/dev/null || true
  _filtrar_log "$PERFIL_ACTUAL" "$logf2"
  n="$(_cuenta "$logf2")"
  if [[ "$n" -gt 0 ]]; then
    _mostrar "archivos vacios" "$logf2" "$n"
    if [[ "$real" == "1" ]]; then
      xargs -a "$logf2" -d '\n' -r rm -f --
      printf '      borrados: %s\n' "$n"
    fi
  fi
}

duplicados() {
  local p="$1" real="$2"
  if ! command -v fdupes >/dev/null 2>&1; then
    aviso "fdupes no disponible: no se deduplica"
    return 0
  fi
  local u logf n
  logf="$LOG_DIR/${PERFIL_ACTUAL}-duplicados.txt"
  : >"$logf"
  while IFS= read -r u; do
    [[ -d "$u" ]] || continue
    if [[ "$real" == "1" ]]; then
      fdupes -rdN "$u" >>"$logf" 2>&1 || true
    else
      fdupes -r "$u" >>"$logf" 2>&1 || true
    fi
  done < <(unidades "$p")
  n="$(_cuenta "$logf")"
  [[ "$n" -gt 0 ]] || return 0
  _mostrar "duplicados" "$logf" "$n"
}

limpiar() {
  local p="$1" real="${2:-0}"
  local d
  d="$(destino "$p")"
  [[ -d "$d" ]] || fatal "$p: no existe $d"
  PERFIL_ACTUAL="$p"
  command -v find >/dev/null 2>&1 || fatal "falta find"
  adoptar_raiz "$p" "$real"

  printf '\n  --- %s (%s) ---\n' "$p" "$([[ "$real" == "1" ]] && echo REAL || echo dry-run)"

  [[ "$(bool_config "$p" borrar_papelera)" == "true" ]] && \
    aplicar_dirs "$d" "$real" papelera -name files_trashbin -o -name .trash

  [[ "$(bool_config "$p" borrar_versiones)" == "true" ]] && \
    aplicar_dirs "$d" "$real" versiones -name files_versions

  [[ "$(bool_config "$p" borrar_duplicados)" == "true" ]] && duplicados "$p" "$real"

  local -a pred=() e
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    [[ "$e" == .* ]] || e=".$e"
    pred+=( -o -iname "*$e" )
  done < <(lista_config "$p" borrar)

  if [[ "$(bool_config "$p" borrar_fotos)" == "true" ]]; then
    pred+=( -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
            -o -iname "*.heic" -o -iname "*.webp" )
  fi
  if [[ "$(bool_config "$p" borrar_videos)" == "true" ]]; then
    pred+=( -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" \
            -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mpg" \
            -o -iname "*.mpeg" -o -iname "*.flv" -o -iname "*.webm" \
            -o -iname "*.3gp" -o -iname "*.m4v" -o -iname "*.ts" \
            -o -iname "*.m2ts" -o -iname "*.vob" -o -iname "*.ogv" )
  fi
  if [[ "$(bool_config "$p" borrar_musica)" == "true" ]]; then
    pred+=( -o -iname "*.mp3" -o -iname "*.wma" -o -iname "*.wav" \
            -o -iname "*.flac" -o -iname "*.aac" -o -iname "*.ogg" \
            -o -iname "*.m4a" -o -iname "*.opus" -o -iname "*.m4b" \
            -o -iname "*.amr" )
  fi
  if [[ "$(bool_config "$p" borrar_instaladores)" == "true" ]]; then
    pred+=( -o -iname "*.iso" -o -iname "*.msi" -o -iname "*.exe" -o -iname "*.img" )
  fi

  if [[ ${#pred[@]} -gt 0 ]]; then
    pred=( "${pred[@]:1}" )
    aplicar_archivos "$d" "$real" basura "${pred[@]}"
  fi

  [[ "$(bool_config "$p" borrar_vacios)" == "true" ]] && aplicar_vacios "$d" "$real"
  return 0
}

store_csv() {
  local p="$1" out="" e
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    [[ "$e" == .* ]] || e=".$e"
    out+="${out:+;}*${e}"
  done < <(lista_config "$p" store)
  printf '%s\n' "$out"
}

_args_empaquetado() {
  local p="$1"
  local comp integ vol store
  comp="$(p_get "$p" compresion)"
  [[ -n "$comp" ]] || comp="$(g compresion)"
  comp="${comp#m}"
  if [[ "$(bool_config "$p" comprimir)" == "false" ]]; then
    comp="0"          # store: ya viene comprimido, sólo se trocea para el disco
  fi
  integ="$(p_get "$p" integridad)"
  [[ -n "$integ" ]] || integ="$(g integridad)"
  integ="${integ#rr}"
  vol="$(volumen_arg)"
  store="$(store_csv "$p")"
  [[ "$comp" == "0" ]] && store=""
  if [[ "$(bool_config "$p" trocear_grandes)" == "false" ]]; then
    vol=""   # archivo grande va entero ("tal cual"), no se parte
  fi
  if [[ "$EMPAQUETADOR" == "rar" ]]; then
    printf '%s\n' "-m$comp" "-rr$integ" "-r"
    [[ -n "$vol" ]] && printf '%s\n' "-v$vol"
    [[ -n "$store" ]] && printf '%s\n' "-ms$store"
  else
    printf '%s\n' "-mx$comp"
    [[ -n "$vol" ]] && printf '%s\n' "-v$vol"
    [[ -n "$store" ]] && aviso "$p: 7z no admite -ms por extensión, se comprime todo"
  fi
}

_ejecutar() {
  local real="$1" cwd="$2"
  shift 2
  if [[ "$real" == "1" ]]; then
    ( cd "$cwd" && "$@" >/dev/null )
  else
    printf '      (dry-run) ( cd %q &&' "$cwd"
    printf ' %q' "$@"
    printf ' )\n'
  fi
}

numero_de_volumenes() {
  local base="$1" dir n
  dir="$(dirname "$base")"
  n="$(find "$dir" -maxdepth 1 -type f \
    \( -name "$(basename "$base").7z*" -o -name "$(basename "$base").rar*" \
       -o -name "$(basename "$base").part*.rar" -o -name "$(basename "$base").r[0-9][0-9]" \) \
    ! -name '*.sha256' 2>/dev/null | wc -l)"
  printf '%s\n' "$(tr -d ' ' <<<"$n")"
}

primer_archivo() {
  local base="$1" dir nm cand
  dir="$(dirname "$base")"
  nm="$(basename "$base")"
  cand="$(find "$dir" -maxdepth 1 -type f \
    \( -name "$nm.7z*" -o -name "$nm.rar" -o -name "$nm.part*.rar" -o -name "$nm.r[0-9][0-9]" \) \
    -printf '%f\n' 2>/dev/null | sort -V | head -1)"
  [[ -n "$cand" ]] || return 1
  printf '%s/%s\n' "$dir" "$cand"
}

_empaquetar_en() {
  local p="$1" real="$2" base="$3" cwd="$4"
  shift 4
  # Ya verificado OK (tiene .sha256) y la fuente no cambió desde esa verificación => se omite.
  if [[ -f "$base.sha256" ]] && set_existe "$base" && ! _fuente_mas_nueva "$base" "$cwd" "$@"; then
    printf '      %s: ya verificado (%s volúmenes), se omite\n' \
      "$(basename "$base")" "$(numero_de_volumenes "$base")"
    return 0
  fi
  # Set previo sin verificar (p.ej. rar interrumpido) o fuente nueva => se rehace desde cero.
  if set_existe "$base"; then
    printf '      %s: rehacer (sin verificar, rar interrumpido, o fuente nueva)\n' "$(basename "$base")"
    if [[ "$real" == "1" ]]; then
      local dir nm
      dir="$(dirname "$base")"; nm="$(basename "$base")"
      find "$dir" -maxdepth 1 -type f \
        \( -name "$nm.part*.rar" -o -name "$nm.rar" -o -name "$nm.7z*" -o -name "$nm.r[0-9][0-9]" \) \
        -exec rm -f -- {} + 2>/dev/null || true
      rm -f -- "$base.sha256" 2>/dev/null || true
    fi
  fi
  local -a args=()
  mapfile -t args < <(_args_empaquetado "$p")
  local archivo
  if [[ "$EMPAQUETADOR" == "rar" ]]; then
    archivo="$base.rar"
    _ejecutar "$real" "$cwd" rar a "${args[@]}" "$archivo" "$@"
  else
    archivo="$base.7z"
    _ejecutar "$real" "$cwd" 7z a "${args[@]}" "$archivo" "$@"
  fi
  [[ "$real" == "1" ]] || return 0
  printf '      %s -> %s volúmenes\n' "$(basename "$base")" "$(numero_de_volumenes "$base")"
}

contenedores() {
  local p="$1" d x hay=0
  d="$(destino "$p")"
  if [[ "$(bool_config "$p" carpeta_fecha)" == "true" ]]; then
    for x in "$d"/*/; do
      [[ -d "$x" ]] || continue
      printf '%s\n' "${x%/}"
      hay=1
    done
    # Datos heredados, aún sin carpeta fechada: la raíz es el contenedor.
    [[ "$hay" == "1" ]] || printf '%s\n' "$d"
  else
    printf '%s\n' "$d"
  fi
}

# fecha del contenedor: subcarpeta AAAA-MM-DD, o la de hoy si es la raíz
fecha_de() {
  local p="$1" c="$2"
  if [[ "$c" == "$(destino "$p")" ]]; then date +%F; else basename "$c"; fi
}

# archivos sueltos en la raíz del perfil (C3: nunca se quedan sin empaquetar)
archivos_raiz() {
  find "$(destino "$1")" -maxdepth 1 -type f -printf '%f\n'
}

# Normaliza: mete los archivos sueltos de la raíz en la carpeta AAAA-MM-DD de hoy.
# Idempotente: nunca toca los juegos ya empaquetados (${p}_*) ni los .sha256.
adoptar_raiz() {
  local p="$1" real="${2:-0}" quiet="${3:-0}" d fecha target n
  d="$(destino "$p")"
  [[ -d "$d" ]] || return 0
  [[ "$(bool_config "$p" carpeta_fecha)" == "true" ]] || return 0
  # Perfiles por usuario no se envuelven: los usuarios van sueltos y se empaquetan uno a uno
  [[ "$(bool_config "$p" por_usuario)" == "true" ]] && return 0
  local -a sueltos=()
  mapfile -t sueltos < <(
    find "$d" -maxdepth 1 -type f ! -name "${p}_*" ! -name '*.sha256' -printf '%f\n'
  )
  if perfil_tiene_filtros "$p" && [[ ${#sueltos[@]} -gt 0 ]]; then
    local -a s2=() sf
    for sf in "${sueltos[@]}"; do _ruta_filtrada "$p" "$sf" || s2+=("$sf"); done
    sueltos=("${s2[@]}")
  fi
  [[ ${#sueltos[@]} -gt 0 ]] || return 0
  fecha="$(date +%F)"
  target="$d/$fecha"
  n="${#sueltos[@]}"
  if [[ "$real" == "1" ]]; then
    mkdir -p "$target"
    printf '      %s: %s archivos sueltos -> %s/\n' "$p" "$n" "$fecha"
    local f
    for f in "${sueltos[@]}"; do
      mv -f -- "$d/$f" "$target/$f" 2>/dev/null || aviso "$p: no se pudo mover $f"
    done
  elif [[ "$quiet" != "1" ]]; then
    printf '      (dry-run) %s: %s archivos sueltos se moverían a %s/\n' "$p" "$n" "$fecha"
  fi
}

unidades() {
  local p="$1" c u
  while IFS= read -r c; do
    [[ -d "$c" ]] || continue
    if [[ "$(bool_config "$p" por_usuario)" == "true" ]]; then
      for u in "$c"/*/; do
        [[ -d "$u" ]] || continue
        _ruta_filtrada "$p" "$(basename "$u")" && continue
        printf '%s\n' "${u%/}"
      done
    elif perfil_tiene_filtros "$p"; then
      local it
      while IFS= read -r it; do
        [[ -n "$it" ]] || continue
        [[ "$it" == "." ]] && { printf '%s\n' "$c"; continue; }
        printf '%s\n' "$c/$it"
      done < <(_items_container "$p" "$c")
    else
      printf '%s\n' "$c"
    fi
  done < <(contenedores "$p")
}

# Modo "troceo por archivo" (empaquetar=false + trocear_grandes=true):
# NO crea un conjunto del perfil. Parte EN EL SITIO cada archivo mayor que una
# pieza (p.ej. 98 MB) en piezas de ese tamaño y, SOLO tras verificar el troceado,
# borra ESE archivo original. Los archivos <= una pieza quedan intactos.
# Nunca toca subcarpetas, juegos del perfil (${p}_*), .sha256, ni las propias piezas.
trocear_por_archivo() {
  local p="$1" real="${2:-0}"
  local d pz
  d="$(destino "$p")"
  [[ -d "$d" ]] || fatal "$p: no existe $d"
  elegir_empaquetador
  pz="$(volumen_en_bytes)"   # tamaño de pieza en bytes (98M = 98 000 000)
  if [[ ! "$pz" =~ ^[0-9]+$ || "$pz" -le 0 ]]; then
    fatal "$p: tamaño de pieza inválido (volumen=$(g volumen))"
  fi

  printf '\n  --- troceo por archivo %s (%s, piezas de %s) ---\n' \
    "$p" "$([[ "$real" == "1" ]] && echo REAL || echo dry-run)" "$(g volumen)"
  printf '      se parte todo archivo mayor que una pieza; el original se borra solo si el troceado verifica\n'

  local -a args=()
  mapfile -t args < <(_args_empaquetado "$p")

  local f dir base first res n=0 borrados=0
  while IFS= read -r -d '' f; do
    dir="$(dirname "$f")"
    base="$(basename "$f")"
    # filtros por perfil (excluir/incluir)
    _abs_filtrada "$p" "$f" && continue
    # nunca tocar piezas ya hechas, manifiestos ni los juegos del perfil
    [[ "$base" == *.part*.rar || "$base" == *.sha256 || "$base" == "${p}_"* ]] && continue
    n=$((n + 1))

    # troceado previo interrumpido (piezas + original presente): se rehace
    if set_existe "$dir/$base"; then
      printf '      %s: rehacer (troceado previo sin terminar)\n' "$base"
      if [[ "$real" == "1" ]]; then
        find "$dir" -maxdepth 1 -type f \
          \( -name "$base.part*.rar" -o -name "$base.rar" -o -name "$base.7z*" -o -name "$base.r[0-9][0-9]" \) \
          -exec rm -f -- {} + 2>/dev/null || true
      fi
    fi

    if [[ "$EMPAQUETADOR" == "rar" ]]; then
      _ejecutar "$real" "$dir" rar a "${args[@]}" "$base.rar" "$base"
    else
      _ejecutar "$real" "$dir" 7z a "${args[@]}" "$base.7z" "$base"
    fi
    [[ "$real" == "1" ]] || continue

    # verificar el troceado ANTES de borrar el original
    res=0
    if first="$(primer_archivo "$dir/$base")"; then
      if [[ "$EMPAQUETADOR" == "rar" ]]; then
        ( cd "$dir" && rar t "$(basename "$first")" >/dev/null 2>&1 ) && res=1 || res=0
      else
        ( cd "$dir" && 7z t "$(basename "$first")" >/dev/null 2>&1 ) && res=1 || res=0
      fi
    fi
    if [[ "$res" == "1" ]]; then
      rm -f -- "$f"
      borrados=$((borrados + 1))
      printf '      OK    %s -> %s piezas (original borrado)\n' \
        "$base" "$(numero_de_volumenes "$dir/$base")"
    else
      printf '      %sFALLA%s %s: el troceado no verifica; se borran las piezas y SE CONSERVA el original\n' \
        "$C_ROJO" "$C_RESET" "$base"
      find "$dir" -maxdepth 1 -type f \
        \( -name "$base.part*.rar" -o -name "$base.rar" -o -name "$base.7z*" -o -name "$base.r[0-9][0-9]" \) \
        -exec rm -f -- {} + 2>/dev/null || true
    fi
  done < <(find "$d" -type f -size +"${pz}"c \
             ! -name '*.part*.rar' ! -name '*.sha256' ! -name "${p}_*" -print0 2>/dev/null)

  if [[ "$n" -eq 0 ]]; then
    printf '      nada que trocear: no hay archivos mayores que %s\n' "$(g volumen)"
  elif [[ "$real" == "1" ]]; then
    printf '      archivos troceados: %s (originales borrados: %s)\n' "$n" "$borrados"
  else
    printf '      (dry-run) se trocearían %s archivo(s)\n' "$n"
  fi
}

# --- H.12: procesado por unidad --------------------------------------------
# Recorre las unidades empaquetables de un perfil y ejecuta, por cada una:
#   <fn> <perfil> <real> <base> <cwd> <item...>
# <base> = ruta-base del set (sin extensión); <cwd> = directorio de trabajo;
# <item...> = lo que se empaqueta, relativo a <cwd> (`.` = el propio <cwd>).
# Deja en UNIDADES_N el número de unidades recorridas. Es la enumeración que
# antes vivía dentro de empaquetar(), extraída para reutilizarla tal cual.
_por_unidad() {
  local p="$1" fn="$2" real="$3"
  local d x c fecha un u hayfecha=0
  local -a conts=()
  d="$(destino "$p")"
  mapfile -t conts < <(contenedores "$p")
  for x in "${conts[@]}"; do
    [[ "$(basename "$x")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && hayfecha=1
  done

  if [[ "$(bool_config "$p" por_usuario)" == "true" && "$hayfecha" == "0" ]]; then
    # Legado: usuarios al tope (RESHOME/alvarez, RESNEXTCLOUD/usuario@dominio).
    # Se respeta el nombre de cada usuario: <PERFIL>_<fecha>_<usuario>
    fecha="$(date +%F)"
    local -a usuarios=()
    if [[ ${#conts[@]} -eq 1 && "${conts[0]}" == "$d" ]]; then
      for u in "$d"/*/; do [[ -d "$u" ]] && usuarios+=( "$(basename "$u")" ); done
    else
      for x in "${conts[@]}"; do usuarios+=( "$(basename "$x")" ); done
    fi
    local -a sl=() f
    for un in "${usuarios[@]}"; do
      [[ -d "$d/$un" ]] || continue
      _ruta_filtrada "$p" "$un" && continue
      UNIDADES_N=$((UNIDADES_N + 1))
      "$fn" "$p" "$real" "${d}/${p}_${fecha}_${un}" "$d" "$un"
    done
    local -a sueltos=()
    mapfile -t sueltos < <(
      find "$d" -maxdepth 1 -type f ! -name "${p}_*" ! -name '*.sha256' -printf '%f\n'
    )
    for f in "${sueltos[@]}"; do _ruta_filtrada "$p" "$f" || sl+=("$f"); done
    if [[ ${#sl[@]} -gt 0 ]]; then
      UNIDADES_N=$((UNIDADES_N + 1))
      "$fn" "$p" "$real" "${d}/${p}_${fecha}_RAIZ" "$d" "${sl[@]}"
    fi
    return 0
  fi

  while IFS= read -r c; do
    [[ -d "$c" ]] || continue
    fecha="$(fecha_de "$p" "$c")"

    # La raíz como contenedor (sin filtros): sólo si quedan archivos que no son
    # juegos ya hechos; se empaqueta entera como antes.
    if [[ "$c" == "$d" ]] && ! perfil_tiene_filtros "$p"; then
      local -a resto=()
      mapfile -t resto < <(
        find "$d" -maxdepth 1 -type f ! -name "${p}_*" ! -name '*.sha256' -printf '%f\n'
      )
      [[ ${#resto[@]} -gt 0 ]] || continue
      UNIDADES_N=$((UNIDADES_N + 1))
      "$fn" "$p" "$real" "${d}/${p}_${fecha}" "$d" .
      continue
    fi

    if [[ "$(bool_config "$p" por_usuario)" == "true" ]]; then
      for u in "$c"/*/; do
        [[ -d "$u" ]] || continue
        un="$(basename "$u")"
        _ruta_filtrada "$p" "$un" && continue
        UNIDADES_N=$((UNIDADES_N + 1))
        "$fn" "$p" "$real" "${d}/${p}_${fecha}_${un}" "$c" "$un"
      done
      local -a raizfiles=() rf=() f
      mapfile -t raizfiles < <(find "$c" -maxdepth 1 -type f -printf '%f\n')
      for f in "${raizfiles[@]}"; do _ruta_filtrada "$p" "$f" || rf+=("$f"); done
      if [[ ${#rf[@]} -gt 0 ]]; then
        UNIDADES_N=$((UNIDADES_N + 1))
        "$fn" "$p" "$real" "${d}/${p}_${fecha}_RAIZ" "$c" "${rf[@]}"
      fi
    else
      local -a items=()
      mapfile -t items < <(_items_container "$p" "$c")
      [[ ${#items[@]} -gt 0 ]] || continue
      UNIDADES_N=$((UNIDADES_N + 1))
      "$fn" "$p" "$real" "${d}/${p}_${fecha}" "$c" "${items[@]}"
    fi
  done < <(contenedores "$p")
}

# ¿el set parece completo (troceado terminado) aunque no tenga .sha256? rar cierra
# con un volumen parcial; si la última pieza mide EXACTAMENTE un volumen se
# sospecha truncado. Un único .rar/.7z sin trocear no se puede juzgar por tamaño:
# se deja verificar (lo decidirá rar t).
_set_parece_completo() {
  local base="$1" dir nm last pz sz
  dir="$(dirname "$base")"; nm="$(basename "$base")"
  pz="$(volumen_en_bytes)"
  last="$(find "$dir" -maxdepth 1 -type f \
      \( -name "$nm.part*.rar" -o -name "$nm.7z*" -o -name "$nm.r[0-9][0-9]" -o -name "$nm.rar" \) \
      -printf '%f\n' 2>/dev/null | sort -V | tail -1)"
  [[ -n "$last" ]] || return 1
  case "$last" in
    *.part*.rar) ;;
    *) return 0 ;;
  esac
  sz="$(stat -c %s "$dir/$last" 2>/dev/null || echo 0)"
  [[ "$sz" =~ ^[0-9]+$ && "$pz" =~ ^[0-9]+$ && "$sz" -lt "$pz" ]]
}

# pieza más reciente del set (referencia temporal de "cuándo se terminó de empaquetar")
_piezas_ref() {
  local base="$1" dir nm
  dir="$(dirname "$base")"; nm="$(basename "$base")"
  find "$dir" -maxdepth 1 -type f \
    \( -name "$nm.part*.rar" -o -name "$nm.7z*" -o -name "$nm.r[0-9][0-9]" -o -name "$nm.rar" \) \
    -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-
}

# ¿hay fuente más nueva que <ref>? (para no reutilizar un set que quedó obsoleto)
_fuente_mas_nueva_que() {
  local ref="$1" cwd="$2" it
  shift 2
  [[ -n "$ref" && -e "$ref" ]] || return 0
  for it in "$@"; do
    [[ -e "$cwd/$it" ]] || continue
    find "$cwd/$it" -type f -newer "$ref" -print -quit 2>/dev/null | grep -q . && return 0
  done
  return 1
}

# Borra la fuente de UNA unidad ya verificada. <items...> son rutas relativas a
# <cwd> ("." = el propio <cwd>). Nunca toca juegos (${p}_*) ni .sha256, nunca sale
# del perfil y nunca borra la raíz entera (guarda los juegos ya hechos).
_borrar_unidad() {
  local p="$1" cwd="$2"
  shift 2
  local d it t
  d="$(destino "$p")"
  for it in "$@"; do
    [[ -n "$it" ]] || continue
    if [[ "$it" == "." ]]; then t="$cwd"; else t="$cwd/$it"; fi
    if [[ "$t" != "$d" && "$t" != "$d/"* ]]; then
      aviso "$p: se rechaza borrar fuera del perfil: $t"
      continue
    fi
    if [[ "$t" == "$d" ]]; then
      find "$d" -maxdepth 1 -mindepth 1 \
        ! -name "${p}_*" ! -name '*.sha256' -exec rm -rf -- {} + 2>/dev/null || true
    elif [[ -d "$t" ]]; then
      rm -rf -- "$t"
    elif [[ -e "$t" ]]; then
      rm -f -- "$t"
    fi
  done
}

# Verifica UN set (rar t / 7z t). Si pasa, escribe su .sha256 y lo registra en el
# manifiesto; si falla, borra el .sha256. Devuelve 0=OK, 1=falla.
_verificar_set() {
  local p="$1" base="$2"
  local archivo res
  if archivo="$(primer_archivo "$base")"; then
    if [[ "$EMPAQUETADOR" == "rar" ]]; then
      ( cd "$(dirname "$archivo")" && rar t "$(basename "$archivo")" >/dev/null 2>&1 ) && res=1 || res=0
    else
      ( cd "$(dirname "$archivo")" && 7z t "$(basename "$archivo")" >/dev/null 2>&1 ) && res=1 || res=0
    fi
  else
    res=0
  fi
  if [[ "$res" == "1" ]]; then
    printf '  OK    %s (%s volúmenes)\n' "$(basename "$base")" "$(numero_de_volumenes "$base")"
    manifiesto_sha "$base"
    manifiesto_registrar "$p" "$base" \
      "$(numero_de_volumenes "$base")" "$(bytes_set "$base")" \
      "$(sha_set "$base.sha256")" OK >/dev/null
    return 0
  fi
  printf '  FALLA %s\n' "$(basename "$base")"
  rm -f -- "$base.sha256" 2>/dev/null || true
  manifiesto_registrar "$p" "$base" 0 0 "-" FALLA >/dev/null
  return 1
}

# Cierra UNA unidad en el flujo por unidad (H.12): empaqueta (o reutiliza el set
# completo si quedó sin verificar), verifica ESE set y, sólo si pasa, borra la
# fuente de ESA unidad. Si el set ya estaba verificado (.sha256 y fuente sin
# cambios) se confía en él y se borra la fuente SIN re-verificar.
_unidad_procesar() {
  local p="$1" real="$2" base="$3" cwd="$4"
  shift 4
  local nm; nm="$(basename "$base")"

  # 1) ya verificado y fuente sin cambios desde entonces: no se re-verifica
  if [[ -f "$base.sha256" ]] && set_existe "$base" && ! _fuente_mas_nueva "$base" "$cwd" "$@"; then
    printf '      %s: ya verificado (%s volúmenes), se omite; se borra su fuente\n' \
      "$nm" "$(numero_de_volumenes "$base")"
    if [[ "$real" == "1" ]]; then
      _borrar_unidad "$p" "$cwd" "$@"
      CER_OK=$((CER_OK + 1))
    else
      printf '      %s: (dry-run) no se toca nada\n' "$nm"
    fi
    return 0
  fi

  # 2) set presente y aparentemente completo, sin verificar y sin fuente más nueva
  #    (p.ej. rar terminó y se interrumpió durante la verificación): se verifica
  #    tal cual, sin re-empaquetar (ahorra la compresión entera).
  local reusar=0 ref
  if [[ ! -f "$base.sha256" ]] && set_existe "$base" && _set_parece_completo "$base"; then
    ref="$(_piezas_ref "$base")"
    _fuente_mas_nueva_que "$ref" "$cwd" "$@" || reusar=1
    [[ "$reusar" == "1" ]] && \
      printf '      %s: set presente sin verificar -> se verifica (no se re-empaqueta)\n' "$nm"
  fi

  if [[ "$reusar" != "1" ]]; then
    _empaquetar_en "$p" "$real" "$base" "$cwd" "$@" || true
  fi

  if [[ "$real" != "1" ]]; then
    printf '      %s: (dry-run) se verificaría y, si pasa, se borraría su fuente\n' "$nm"
    return 0
  fi

  # 3) verificar; si un set reusado no verifica, se rehace una vez y se reintenta
  if _verificar_set "$p" "$base"; then
    _borrar_unidad "$p" "$cwd" "$@"
    CER_OK=$((CER_OK + 1))
    return 0
  fi
  if [[ "$reusar" == "1" ]]; then
    printf '      %s: el set reusado no verifica; se rehace desde cero\n' "$nm"
    _empaquetar_en "$p" "$real" "$base" "$cwd" "$@" || true
    if _verificar_set "$p" "$base"; then
      _borrar_unidad "$p" "$cwd" "$@"
      CER_OK=$((CER_OK + 1))
      return 0
    fi
  fi
  printf '  %sFALLA%s %s: NO se borra su fuente\n' "$C_ROJO" "$C_RESET" "$nm"
  CER_MAL=$((CER_MAL + 1))
  return 0
}

# H.12: procesa un perfil unidad a unidad, cerrando (verificar + borrar fuente)
# cada una antes de pasar a la siguiente. Libera disco buzón a buzón y no
# re-verifica los sets que ya tienen .sha256. Devuelve 0 si ninguna unidad falló.
procesar_unidades() {
  local p="$1" d
  d="$(destino "$p")"
  PERFIL_ACTUAL="$p"
  elegir_empaquetador
  adoptar_raiz "$p" 1 1
  printf '\n  --- procesado por unidad %s (REAL, %s) ---\n' "$p" "$EMPAQUETADOR"
  [[ "$(bool_config "$p" comprimir)" == "false" ]] \
    && printf '      sin comprimir (store): sólo se trocea para el disco\n'
  printf '      cada unidad se verifica y su fuente se borra antes de pasar a la siguiente\n'

  UNIDADES_N=0 CER_OK=0 CER_MAL=0
  _por_unidad "$p" _unidad_procesar 1

  # contenedores/carpetas que quedaron vacíos al borrar la fuente
  aplicar_vacios "$d" 1 || true

  if [[ "$UNIDADES_N" -eq 0 ]]; then
    printf '      nada que procesar: %s ya está procesado\n' "$p"
  fi
  printf '      unidades: %s cerradas ok / %s con falla\n' "$CER_OK" "$CER_MAL"
  [[ "$CER_MAL" -eq 0 ]]
}

empaquetar() {
  local p="$1" real="${2:-0}"
  local d
  d="$(destino "$p")"
  [[ -d "$d" ]] || fatal "$p: no existe $d"
  if [[ "$(bool_config "$p" empaquetar)" == "false" ]]; then
    if [[ "$(bool_config "$p" trocear_grandes)" == "true" ]]; then
      trocear_por_archivo "$p" "$real"
    else
      printf '\n  --- %s: se quema tal cual (empaquetar=false) ---\n' "$p"
    fi
    return 0
  fi
  PERFIL_ACTUAL="$p"
  elegir_empaquetador
  adoptar_raiz "$p" "$real" 1

  printf '\n  --- empaquetado %s (%s, %s) ---\n' \
    "$p" "$([[ "$real" == "1" ]] && echo REAL || echo dry-run)" "$EMPAQUETADOR"

  [[ "$(bool_config "$p" comprimir)" == "false" ]] \
    && printf '      sin comprimir (store): sólo se trocea para el disco\n'

  UNIDADES_N=0
  _por_unidad "$p" _empaquetar_en "$real"
  [[ "$UNIDADES_N" -gt 0 ]] || printf '      nada que empaquetar: %s ya está procesado\n' "$p"
}

sets_de() {
  local d="$1" pref="$2"
  find "$d" -maxdepth 1 -type f \( \
      -name "${pref}*.part*.rar" -o -name "${pref}*.rar" \
      -o -name "${pref}*.7z*" \) -printf '%p\n' 2>/dev/null \
  | while IFS= read -r f; do
      case "$f" in
        *.7z*)       printf '%s\n' "${f%%.7z*}" ;;
        *.part*.rar) printf '%s\n' "${f%.part*.rar}" ;;
        *.rar)       printf '%s\n' "${f%.rar}" ;;
      esac
    done | sort -u
}

# ¿existe algún volumen/archivo del set (esté completo o no)?
set_existe() {
  local base="$1" dir nm
  dir="$(dirname "$base")"
  nm="$(basename "$base")"
  find "$dir" -maxdepth 1 -type f \
    \( -name "$nm.part*.rar" -o -name "$nm.rar" -o -name "$nm.7z*" -o -name "$nm.r[0-9][0-9]" \) \
    -print -quit 2>/dev/null | grep -q .
}

# ¿hay fuente que empaquetar más nueva que la última verificación (.sha256)? si sí, el set quedó obsoleto.
_fuente_mas_nueva() {
  local base="$1" cwd="$2" it
  shift 2
  [[ -f "$base.sha256" ]] || return 0
  for it in "$@"; do
    [[ -e "$cwd/$it" ]] || continue
    # sólo cuentan los archivos: los cambios de mtime de carpetas no implican fuente nueva
    find "$cwd/$it" -type f -newer "$base.sha256" -print -quit 2>/dev/null | grep -q . && return 0
  done
  return 1
}

# Perfil "al día": sin fuente suelta y todos sus sets ya verificados (.sha256 presente).
procesado_completo() {
  local p="$1" d
  d="$(destino "$p")"
  [[ -d "$d" ]] || return 1
  # modo "troceo por archivo": está al día cuando NO queda ningún archivo mayor que una pieza
  if [[ "$(bool_config "$p" empaquetar)" == "false" \
        && "$(bool_config "$p" trocear_grandes)" == "true" ]]; then
    local pz f
    pz="$(volumen_en_bytes)"
    [[ "$pz" =~ ^[0-9]+$ && "$pz" -gt 0 ]] || return 1
    while IFS= read -r f; do
      _abs_filtrada "$p" "$f" && continue
      return 1
    done < <(find "$d" -type f -size +"${pz}"c \
               ! -name '*.part*.rar' ! -name '*.sha256' ! -name "${p}_*" 2>/dev/null)
    return 0
  fi
  # tal-cual (empaquetar=false, trocear_grandes=false) no deja sets: nunca se marca "ya procesado"
  [[ "$(bool_config "$p" empaquetar)" == "false" ]] && return 1
  # ¿queda fuente suelta (todo lo que no es set ni .sha256) que no esté filtrada?
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    _abs_filtrada "$p" "$f" && continue
    return 1
  done < <(find "$d" -mindepth 1 \( -name "${p}_*" -o -name '*.sha256' \) -prune -o -print 2>/dev/null)
  local uno=0 b
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    # un set sin verificar (rar a medias, interrumpido) impide marcar "procesado": toca rehacer
    [[ -f "$b.sha256" ]] || return 1
    uno=1
  done < <(sets_de "$d" "${p}_")
  [[ "$uno" == "1" ]]
}

manifiesto_sha() {
  local base="$1" dir name
  dir="$(dirname "$base")"
  name="$(basename "$base")"
  (
    cd "$dir" || exit 1
    find . -maxdepth 1 -type f \
      \( -name "$name.7z*" -o -name "$name.rar*" -o -name "$name.part*.rar" -o -name "$name.r[0-9][0-9]" \) \
      ! -name '*.sha256' -print0 | xargs -0 -r sha256sum >"$name.sha256"
  )
}

verificar() {
  local p="$1"
  local d ok=0 mal=0 base
  d="$(destino "$p")"
  PERFIL_ACTUAL="$p"
  elegir_empaquetador

  printf '\n  --- verificación %s ---\n' "$p"

  while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    if _verificar_set "$p" "$base"; then ok=$((ok + 1)); else mal=$((mal + 1)); fi
  done < <(sets_de "$d" "${p}_")

  VER_OK="$ok"
  VER_MAL="$mal"
  printf '  verificados: %s ok / %s fallas\n' "$ok" "$mal"
  [[ "$mal" -eq 0 && "$ok" -gt 0 ]]
}

# LEGADO (H.12 ya no la usa): borrado global de la fuente al final. Se conserva por
# si algo externo la invoca; el flujo real ahora cierra unidad a unidad (_borrar_unidad).
borrar_fuente() {
  local p="$1"
  local d c
  d="$(destino "$p")"
  PERFIL_ACTUAL="$p"
  if [[ "$(bool_config "$p" verificar_antes_de_borrar)" == "true" ]]; then
    verificar "$p" || { aviso "$p: verificación falló, NO se borra la fuente"; return 1; }
  fi
  printf '\n  --- borrado de la fuente %s ---\n' "$p"
  while IFS= read -r c; do
    [[ -d "$c" ]] || continue
    if [[ "$c" == "$d" ]]; then
      # la raíz es el contenedor: NO se borra entera (guardaría los juegos)
      printf '      %s (raíz: se conservan los juegos ya empaquetados)\n' "$c"
      find "$d" -maxdepth 1 -mindepth 1 \
        ! -name "${p}_*" ! -name '*.sha256' -exec rm -rf -- {} + 2>/dev/null || true
    else
      printf '      %s\n' "$c"
      rm -rf -- "$c"
    fi
  done < <(contenedores "$p")
  # archivos sueltos de la raíz (ya empaquetados en _RAIZ): nunca toca juegos ni .sha256
  find "$d" -maxdepth 1 -type f ! -name "${p}_*" ! -name '*.sha256' \
    -exec rm -f -- {} + 2>/dev/null || true
}

procesar() {
  local p="$1" real="${2:-0}"
  if [[ ! -d "$(destino "$p")" ]]; then
    aviso "$p: sin datos para procesar"
    return 1
  fi
  if procesado_completo "$p"; then
    aviso "$p: ya procesado (todo empaquetado, listo para quemar), se omite. 'verificar $p' para re-chequear."
    prog_fase fin
    return 0
  fi
  prog_fase preflight
  preflight "$p" || { aviso "$p: espacio insuficiente, se salta"; prog_fase fallo; return 1; }
  prog_fase limpiar
  limpiar "$p" "$real"

  # empaquetar=false: tal cual, o troceo por archivo (H.11). No crea sets del perfil.
  if [[ "$(bool_config "$p" empaquetar)" == "false" ]]; then
    prog_fase empaquetar
    empaquetar "$p" "$real"
    if [[ "$(bool_config "$p" trocear_grandes)" == "true" ]]; then
      printf '  %s troceado por archivo: listo para quemar (originales troceados y borrados)\n' "$p"
    else
      printf '  %s listo para quemar tal cual (la fuente no se toca)\n' "$p"
    fi
    if [[ "$real" == "1" ]]; then
      VER_OK=1 VER_MAL=0
      avisar_listo "$p"
    fi
    prog_fase fin
    return 0
  fi

  # dry-run: sólo se lista lo que haría (empaquetar)
  if [[ "$real" != "1" ]]; then
    prog_fase empaquetar
    empaquetar "$p" "$real"
    prog_fase fin
    return 0
  fi

  # REAL: procesado por unidad (H.12). Cada unidad se empaqueta, se verifica y su
  # fuente se borra antes de pasar a la siguiente; los sets ya verificados (.sha256)
  # no se re-verifican. Así se libera disco buzón a buzón.
  prog_fase empaquetar
  if procesar_unidades "$p"; then
    prog_fase verificar
    VER_OK="${CER_OK:-0}" VER_MAL="${CER_MAL:-0}"
    avisar_listo "$p"
    prog_fase fin
    return 0
  fi
  avisar_fallo "$p" "alguna unidad no verificó; su fuente NO se borró"
  prog_fase fallo
  return 1
}
