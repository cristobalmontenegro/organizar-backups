#!/usr/bin/env bash

[[ -n "${_CONFIG_CARGADA:-}" ]] && return 0
_CONFIG_CARGADA=1

# clave|tipo|ámbito|descripción
#   ámbito = carpeta   → obligatorio en cada perfil, NO hereda de global
#   ámbito = operativo → puede faltar y hereda de global
cfg_catalogo() {
  cat <<'EOF'
comprimir|si_no|carpeta|Comprime el set; false = trocea en store (-m0, no recomprime)
empaquetar|si_no|carpeta|Crea conjuntos del perfil; false = no crea conjuntos (tal cual, o troceo por archivo si trocear_grandes=true)
trocear_grandes|si_no|carpeta|true = parte en piezas de <volumen>; con empaquetar=false trocea EN EL SITIO cada archivo mayor que <volumen> (borra el original tras verificar). false = no parte
carpeta_fecha|si_no|carpeta|Envuelve en subcarpeta AAAA-MM-DD (unidad de restauración)
por_usuario|si_no|carpeta|Un juego por usuario; nunca mezclar usuarios
borrar_papelera|si_no|carpeta|Borra carpetas de papelera (files_trashbin, .trash)
borrar_versiones|si_no|carpeta|Borra files_versions (versiones previas de Nextcloud)
borrar_duplicados|si_no|carpeta|Deduplica archivos idénticos (siempre dentro del mismo usuario)
borrar_vacios|si_no|carpeta|Borra carpetas y archivos vacíos
borrar_videos|si_no|carpeta|Borra vídeo no empresarial (.mp4 .avi .mov .mkv .wmv .mpg .flv .webm …)
borrar_musica|si_no|carpeta|Borra música (.mp3 .wma .wav .flac .aac .ogg .m4a …)
borrar_fotos|si_no|carpeta|Borra fotos (.jpg .jpeg .png .heic .webp)
borrar_instaladores|si_no|carpeta|Borra *.iso, *.msi, *.exe, *.img
borrar|lista|carpeta|Extensiones que se eliminan (glob con punto inicial)
conservar|lista|carpeta|Nunca se borran, aunque estén en "borrar"
store|lista|carpeta|Extensiones que se archivan sin comprimir (-ms)
origen_s14|texto|carpeta|Ruta relativa a /mnt/bak del Servidor 14 (vacío = manual)
incluir|lista|opcional|Filtro (opcional): si NO está vacío, SÓLO estas subcarpetas/archivos se respaldan (relativas a la carpeta que se empaqueta)
excluir|lista|opcional|Filtro (opcional): estas subcarpetas/archivos NO se respaldan, ni se descargan, ni se borran, ni se limpian
compresion|texto|operativo|Nivel de compresión -m (m0..m5) [global]
integridad|texto|operativo|Datos de recuperación -rr (rr3%) [global]
volumen|texto|operativo|Tamaño de pieza -v (98M = 98 000 000 bytes) [global]
aire_porcentaje|numero|operativo|% de aire por disco (V = (100 - aire) MB) [global]
medio|texto|operativo|Medio por defecto (BD25 / DVD / CD) [global]
correo|lista|operativo|Destinatarios del aviso por correo [global]
verificar_antes_de_borrar|si_no|operativo|Exige verificar con éxito antes de borrar la fuente [global]
empaquetador|texto|operativo|rar o 7z; vacío = automático (rar si existe) [global]
factor_salida|numero|operativo|Factor para estimar la salida en el preflight [global]
EOF
}

cfg_claves_carpeta() { cfg_catalogo | awk -F'|' '$3=="carpeta"{print $1}'; }
cfg_claves_operativas() { cfg_catalogo | awk -F'|' '$3=="operativo"{print $1}'; }

validar_config() {
  local p k faltan=0
  while IFS= read -r p; do
    while IFS= read -r k; do
      if ! jq -e --arg p "$p" --arg k "$k" '.perfiles[$p] | has($k)' "$CONFIG" >/dev/null 2>&1; then
        aviso "$p: falta el interruptor $k (obligatorio por carpeta)"
        faltan=$((faltan + 1))
      fi
    done < <(cfg_claves_carpeta)
  done < <(lista_perfiles)
  if [[ "$faltan" -gt 0 ]]; then
    erro "configuración incompleta: $faltan interruptor(es) sin definir"
    return 1
  fi
  return 0
}

cfg_informar_validacion() {
  if validar_config; then
    printf '  %s✓%s todos los perfiles tienen sus interruptores de carpeta definidos\n' "$C_VERDE" "$C_RESET"
  else
    printf '  %s✗%s hay perfiles incompletos (usa «Completar desde plantilla»)\n' \
      "$C_ROJO" "$C_RESET"
    return 1
  fi
}

cfg_valor_json() {
  jq -c --arg p "${1:-}" --arg k "$2" \
    '. as $r | if (($r.perfiles[$p] // {}) | has($k)) then $r.perfiles[$p][$k] else $r.global[$k] end' \
    "$CONFIG"
}

cfg_origen() {
  jq -r --arg p "${1:-}" --arg k "$2" \
    'if ((.perfiles[$p] // {}) | has($k)) then "perfil" else "global" end' "$CONFIG"
}

_cfg_texto() {
  local tipo="$1" val="$2"
  case "$tipo" in
    si_no)
      case "$val" in
        true) printf 'sí' ;;
        false) printf 'no' ;;
        *) printf '—' ;;
      esac
      ;;
    lista)
      if [[ "$val" == "null" || -z "$val" ]]; then printf '0'
      else printf '%s' "$(jq -r 'length' <<<"$val" 2>/dev/null || echo 0)"; fi
      ;;
    *)
      if [[ "$val" == "null" || -z "$val" ]]; then
        printf '—'
      elif [[ "$val" == \"*\" ]]; then
        jq -r '.' <<<"$val" 2>/dev/null || printf '%s' "$val"
      else
        printf '%s' "$val"
      fi
      ;;
  esac
}

cfg_ver() {
  local p="${1:-}" k tipo amb desc pv gv org olet ocol grup=""
  printf '\n  %s%-20s %-10s %-10s  %s  %s%s\n' \
    "$C_NEG" "INTERRUPTOR" "PERFIL" "GLOBAL" "O" "DESCRIPCIÓN" "$C_RESET"
  printf '  %s\n' "-------------------------------------------------------------------------------------------------------"
  while IFS='|' read -r k tipo amb desc; do
    if [[ ( "$grup" == "carpeta" || "$grup" == "opcional" ) && "$amb" == "operativo" ]]; then
      printf '  %s--- parámetros operativos (heredan de global) ---%s\n' "$C_DIM" "$C_RESET"
    fi
    grup="$amb"
    pv="$(cfg_valor_json "$p" "$k")"
    org="$(cfg_origen "$p" "$k")"
    if [[ "$amb" == "operativo" ]]; then
      gv="$(jq -c --arg k "$k" '.global[$k] // null' "$CONFIG")"
    elif [[ "$amb" == "opcional" ]]; then
      gv="—"
      [[ "$org" == "perfil" ]] || org="OPC"
    else
      gv="—"
      [[ "$org" == "perfil" ]] || org="FALTA"
    fi
    case "$org" in
      perfil) olet="P"; ocol="$C_CIAN" ;;
      global) olet="G"; ocol="$C_VERDE" ;;
      OPC) olet="—"; ocol="$C_DIM" ;;
      *) olet="!"; ocol="$C_ROJO" ;;
    esac
    printf '  %-20s %-10s %-10s  %s%-1s%s  %s\n' \
      "$k" "$(_cfg_texto "$tipo" "$pv")" "$(_cfg_texto "$tipo" "$gv")" \
      "$ocol" "$olet" "$C_RESET" "$desc"
  done < <(cfg_catalogo)
  printf '\n  %sP%s = lo define el perfil   %sG%s = hereda de global   %s!%s = falta   %s—%s = opcional (vacío)\n' \
    "$C_CIAN" "$C_RESET" "$C_VERDE" "$C_RESET" "$C_ROJO" "$C_RESET" "$C_DIM" "$C_RESET"
}

cfg_aplicar() {
  local tmp="$CONFIG.tmp"
  if ! jq '.' >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    fatal "el JSON nuevo no es válido: no se tocó $CONFIG"
  fi
  cp -f "$CONFIG" "$CONFIG.bak"
  mv -f "$tmp" "$CONFIG"
  info "configuración guardada (copia previa en $CONFIG.bak)"
}

_cfg_confirmar() {
  local r
  read -rp '  ¿Aplicar el cambio? [s/N] ' r
  [[ "$r" == "s" || "$r" == "S" || "$r" == "si" || "$r" == "sí" ]]
}

CFG_CLAVE=""

_cfg_pedir_clave() {
  local p="$1" i=0 k tipo amb desc sel
  while IFS='|' read -r k tipo amb desc; do
    i=$((i + 1))
    printf '  %2d) %-22s %-6s %-5s %s\n' \
      "$i" "$k" "$(_cfg_texto "$tipo" "$(cfg_valor_json "$p" "$k")")" "$amb" "$desc"
  done < <(cfg_catalogo)
  printf '  clave (número o nombre, vacío / X = cancelar): '
  read -r sel
  case "$sel" in
    "" | 0 | x | X | q | Q | salir | volver) aviso "cancelado"; return 1 ;;
  esac
  if [[ "$sel" =~ ^[0-9]+$ ]]; then
    sel="$(cfg_catalogo | sed -n "${sel}p" | cut -d'|' -f1)"
  fi
  [[ -n "$sel" ]] || { aviso "clave no válida"; return 1; }
  cfg_catalogo | cut -d'|' -f1 | grep -qxF "$sel" \
    || { aviso "clave no válida: $sel"; return 1; }
  CFG_CLAVE="$sel"
}

cfg_editar() {
  local p="$1"
  local k tipo amb desc val nuevo
  if [[ -z "$p" ]]; then p="_global_"; fi
  _cfg_pedir_clave "$p" || return 0
  k="$CFG_CLAVE"
  IFS='|' read -r k tipo amb desc < <(cfg_catalogo | grep -m1 "^${k}|")

  if [[ "$p" == "_global_" && "$amb" == "carpeta" ]]; then
    aviso "$k es interruptor de carpeta: no existe en global, edítalo en cada perfil"
    return 1
  fi
  val="$(cfg_valor_json "$p" "$k")"

  printf '\n  clave      : %s\n' "$k"
  printf '  ámbito     : %s\n' "$amb"
  printf '  valor actual: %s\n' "$(_cfg_texto "$tipo" "$val")"
  printf '  qué hace   : %s\n' "$desc"

  case "$tipo" in
    si_no)
      nuevo="$([[ "$val" == "true" ]] && echo false || echo true)"
      printf '  nuevo valor: %s\n' "$(_cfg_texto "$tipo" "$nuevo")"
      ;;
    numero | texto)
      printf '  nuevo valor: '
      read -r nuevo
      [[ -n "$nuevo" ]] || { aviso "valor vacío"; return 1; }
      ;;
    lista)
      printf '  elementos actuales:\n'
      jq -r '.[]?' <<<"$val" 2>/dev/null | sed 's/^/      - /' || true
      printf '  nueva lista (separada por coma, vacío = quitar todo): '
      read -r nuevo
      ;;
    *) aviso "tipo desconocido: $tipo"; return 1 ;;
  esac

  local json
  case "$tipo" in
    si_no | numero) json="$nuevo" ;;
    texto) json="$(jq -Rn --arg v "$nuevo" '$v')" ;;
    lista)
      json="$(jq -Rn --arg v "$nuevo" '[$v | split(",")[] | gsub("^ +| +$";"") | select(length>0)]')"
      ;;
  esac

  printf '  cambio     : %s -> %s\n' \
    "$(_cfg_texto "$tipo" "$val")" \
    "$(_cfg_texto "$tipo" "$json")"
  _cfg_confirmar || { aviso "cancelado"; return 0; }

  if [[ "$p" == "_global_" ]]; then
    jq --arg k "$k" --argjson v "$json" '.global[$k] = $v' "$CONFIG" | cfg_aplicar
  else
    jq --arg p "$p" --arg k "$k" --argjson v "$json" '.perfiles[$p][$k] = $v' "$CONFIG" | cfg_aplicar
  fi
}

cfg_quitar() {
  local p="$1" k tipo amb desc val
  [[ -n "$p" ]] || { aviso "falta el perfil"; return 1; }
  existe_perfil "$p" || { aviso "perfil desconocido: $p"; return 1; }
  _cfg_pedir_clave "$p" || return 0
  k="$CFG_CLAVE"
  IFS='|' read -r k tipo amb desc < <(cfg_catalogo | grep -m1 "^${k}|")
  if [[ "$amb" == "carpeta" ]]; then
    aviso "$k es interruptor de carpeta: es obligatorio en el perfil, no se puede quitar"
    aviso "  (sí puedes apagarlo o cambiarle el valor con «Editar un interruptor»)"
    return 1
  fi
  val="$(cfg_valor_json "$p" "$k")"
  if [[ "$(cfg_origen "$p" "$k")" == "global" ]]; then
    aviso "$p no define $k: ya hereda de global"
    return 0
  fi
  printf '\n  clave      : %s\n  actual     : %s (en %s)\n  hereda     : %s (global)\n  qué hace   : %s\n' \
    "$k" "$(_cfg_texto "$tipo" "$val")" "$p" \
    "$(_cfg_texto "$tipo" "$(jq -c --arg k "$k" '.global[$k] // null' "$CONFIG")")" "$desc"
  _cfg_confirmar || { aviso "cancelado"; return 0; }
  jq --arg p "$p" --arg k "$k" 'del(.perfiles[$p][$k])' "$CONFIG" | cfg_aplicar
}

cfg_completar() {
  local p="$1" n=0 k
  [[ -n "$p" ]] || { aviso "falta el perfil"; return 1; }
  existe_perfil "$p" || { aviso "perfil desconocido: $p"; return 1; }
  printf '  faltantes en %s:\n' "$p"
  while IFS= read -r k; do
    if ! jq -e --arg p "$p" --arg k "$k" '.perfiles[$p] | has($k)' "$CONFIG" >/dev/null 2>&1; then
      printf '      - %s = %s\n' "$k" "$(jq -c --arg k "$k" '.plantilla[$k] // null' "$CONFIG")"
      n=$((n + 1))
    fi
  done < <(cfg_claves_carpeta)
  if [[ "$n" -eq 0 ]]; then
    printf '      (ninguno, perfil completo)\n'
    return 0
  fi
  _cfg_confirmar || { aviso "cancelado"; return 0; }
  local claves
  claves="$(cfg_claves_carpeta | jq -R . | jq -s -c .)"
  jq --arg p "$p" --argjson claves "$claves" '
    reduce $claves[] as $k (.;
      if (.perfiles[$p] | has($k)) then . else .perfiles[$p][$k] = .plantilla[$k] end)
  ' "$CONFIG" | cfg_aplicar
  info "$p completado desde plantilla ($n clave(s))"
}

cmd_configurar() {
  local sub="${1:-}" p
  case "$sub" in
    ver)
      p="${2:-}"
      [[ -n "$p" ]] || { aviso "uso: backup.sh configurar ver <PERFIL>"; return 1; }
      existe_perfil "$p" || fatal "perfil desconocido: $p"
      cfg_ver "$p"
      return 0
      ;;
    validar)
      cfg_informar_validacion
      return $?
      ;;
    "" ) ;;
    *) aviso "subcomando desconocido: $sub"; cmd_ayuda; return 1 ;;
  esac

  while true; do
    printf '\n%s=== CONFIGURAR (%s) ===%s\n' "$C_NEG" "$MODO" "$C_RESET"
    printf '  Interruptores de política: definidos en cada carpeta (sin herencia)\n'
    printf '  Parámetros operativos   : pueden faltar y heredan de global\n'
    cfg_informar_validacion || true
    PS3="$(cian '  Opción (X = volver): ')"
    select op in \
      "Ver la configuración de un perfil" \
      "Editar un interruptor de un perfil" \
      "Editar la configuración operativa global" \
      "Completar perfil desde la plantilla (sólo lo que falta)" \
      "Comprobar que todos los perfiles están completos" \
      "Quitar un interruptor operativo (vuelve a heredar de global)" \
      "Volver"
    do
      case "$REPLY" in
        1)
          _elegir_perfil 'Ver la configuración ¿de qué perfil?' '' 'global' \
            && cfg_ver "$([[ "$ELEGIDO" == "_global_" ]] && echo "" || echo "$ELEGIDO")"
          ;;
        2)
          _elegir_perfil 'Editar interruptores ¿de qué perfil?' '' 'global' && cfg_editar "$ELEGIDO"
          ;;
        3) cfg_editar "_global_" ;;
        4)
          _elegir_perfil 'Completar las claves que falten ¿de qué perfil?' && cfg_completar "$ELEGIDO"
          ;;
        5) cfg_informar_validacion || true ;;
        6)
          _elegir_perfil 'Hacer que un interruptor vuelva a heredar de global (¿de qué perfil?)' \
            && cfg_quitar "$ELEGIDO"
          ;;
        7 | x | X | q | Q | salir) return 0 ;;
        *) printf '  ? opción no válida\n' ;;
      esac
      break
    done
    esperar_enter
  done
}
