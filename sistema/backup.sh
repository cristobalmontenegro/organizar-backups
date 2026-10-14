#!/usr/bin/env bash
set -euo pipefail

DIR_SISTEMA="${DIR_SISTEMA:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export DIR_SISTEMA

# shellcheck source=lib/comunes.sh
. "$DIR_SISTEMA/lib/comunes.sh"
# shellcheck source=lib/notify.sh
. "$DIR_SISTEMA/lib/notify.sh"
# shellcheck source=lib/manifiesto.sh
. "$DIR_SISTEMA/lib/manifiesto.sh"
# shellcheck source=lib/fases.sh
. "$DIR_SISTEMA/lib/fases.sh"
# shellcheck source=lib/config.sh
. "$DIR_SISTEMA/lib/config.sh"
# shellcheck source=lib/perfiles.sh
. "$DIR_SISTEMA/lib/perfiles.sh"
# shellcheck source=lib/pull.sh
. "$DIR_SISTEMA/lib/pull.sh"
# shellcheck source=lib/background.sh
. "$DIR_SISTEMA/lib/background.sh"

MODO="${RESPALDO_MODO:-prod}"
export RESPALDO_MODO="$MODO"
if [[ "$MODO" == "pruebas" && -d "$DIR_SISTEMA/pruebas/stubs" ]]; then
  export PATH="$DIR_SISTEMA/pruebas/stubs:$PATH"
fi

cmd_ayuda() {
  cat <<'EOF'
Uso: backup.sh [comando] [opciones]

  menú
    menu                   menú interactivo (predeterminado)

  sólo lectura
    listar [pruebas]       perfiles, tamaños, origen y destino
    origen  <PERFIL>       de dónde sale la data (Servidor 14) + destino local
    ciclos                 ciclo vigente
    preflight <PERFIL>|all espacio disponible vs salida estimada

  con --real (si no, es dry-run). <PERFIL> también admite `all`.
    limpiar    <PERFIL> [--real]
    empaquetar <PERFIL> [--real]
    pull       <PERFIL> [--hoy=YYYY-MM-DD] [--real]
    procesar   <PERFIL> [--real]   preflight + limpiar + empaquetar + verificar + borrar
    verificar  <PERFIL>            prueba los juegos ya empaquetados

  segundo plano (largos: RESMAIL/RESINTRANET; pull y procesar con locks separados)
    fondo-iniciar <PERFIL> [--real]  lanza el PROCESADO en segundo plano (lock + log)
    pull-fondo    <PERFIL> [--real]  lanza el PULL en segundo plano
    fondo        <PERFIL> [--real]   worker del procesado (lo lanza fondo-iniciar)
    fondo-pull   <PERFIL> [--real]   worker del pull (lo lanza pull-fondo)
    avance                       estado en vivo de ambos trabajos: perfil, fase y %
                                 (en perfiles de troceo: X de Y archivos grandes)
    cron                         receta para el crontab (segundo plano en madrugada)

  plano de ejecución (global, se combina con seco/real)
    En plano FONDO, `pull` y `procesar` (y las opciones 4/5 del menú) se van solos
    a segundo plano; en FRENTE esperan en consola. Se cambia en el menú (opción 0).
    --fondo / --frente fuerzan el plano para una orden concreta.

  consultas y configuración
    manifiesto [PERFIL|all]  MANIFIESTO.csv del ciclo (ciclo, juego, vols, sha256)
    configurar ver <PERFIL>  tabla de interruptores del perfil
    configurar validar       comprueba que cada perfil define sus interruptores
    configurar              submenú de edición (guarda en perfiles.json + .bak)

  carpetas a respaldar (no hace falta editar el JSON a mano)
    perfil-nuevo <NOMBRE> [--origen RUTA_S14 | --manual] [--como PERFIL]
                             añade una carpeta/perfil (desde la plantilla)
    perfil-quitar <PERFIL>   quita la definición (NUNCA borra datos)
    descubrir [listar]       lista carpetas sin perfil y (asistente) las añade
    carpetas                 submenú de carpetas/perfiles

    ayuda                   esta ayuda

Los interruptores de política (empaquetar, trocear_grandes, comprimir, borrar_*, borrar, conservar, store)
no existen en global: cada carpeta los define en perfiles.json.
Sólo los parámetros operativos (raíces, volumen, aire, medio, correo) heredan de global.
  - empaquetar=false + trocear_grandes=true → "troceo por archivo": parte EN EL SITIO cada
    archivo mayor que <volumen> (98M) en piezas de ese tamaño; borra el original solo si verifica.
  - empaquetar=false + trocear_grandes=false → se quema tal cual (no toca nada).

MODO GLOBAL (estado/modo): seco (dry-run) por defecto; real ejecuta de verdad.
  - --real fuerza real en cualquier modo.
  - En el menú se cambia con la opción 0 (activa "real" escribiendo la palabra real).
  - La línea "ejecución: …" de la cabecera muestra siempre el modo vigente.

PLANO GLOBAL (estado/plano): frente por defecto; fondo = segundo plano automático.
  - Afecta a `pull` y `procesar` (y a las opciones 4/5 del menú).
  - Se cambia en el menú, opción 0. --fondo / --frente lo fuerzan por orden.

RESPALDO_MODO=pruebas usa global.raiz_pruebas en vez de /mnt/DATOS.
RESPALDO_VERBOSE=1 imprime el HTML del aviso cuando no hay correo.
EOF
}

_es_real() {
  local a
  for a in "$@"; do
    [[ "$a" == "--real" || "$a" == "--ejecutar" ]] && return 0
  done
  [[ "$(modo_actual)" == "real" ]]
}

# ¿toca segundo plano? --fondo/--frente mandan; si no, manda el plano global.
_es_fondo() {
  local a
  for a in "$@"; do
    [[ "$a" == "--fondo" ]] && return 0
    [[ "$a" == "--frente" ]] && return 1
  done
  [[ "$(plano_actual)" == "fondo" ]]
}

# `pull` y `procesar` (menú 4/5 y CLI) siguen el plano global.
cmd_procesar() {
  if _es_fondo "$@"; then cmd_fondo_iniciar "$@"; else _cmd_fase procesar "$@"; fi
}

cmd_pull_auto() {
  if _es_fondo "$@"; then cmd_fondo_iniciar --pull "$@"; else cmd_pull "$@"; fi
}

_cmd_modos() {
  local op
  while true; do
    printf '\n%s=== MODOS ===%s\n' "$C_NEG" "$C_RESET"
    printf '  1) Ejecución : %s\n' "$(modo_etiqueta)"
    printf '  2) Plano     : %s\n' "$(plano_etiqueta)"
    printf '  3) Volver\n'
    read -rp "$(cian '  Opción: ')" op
    case "$op" in
      1) modo_cambiar; esperar_enter ;;
      2) plano_cambiar; esperar_enter ;;
      3 | x | X | q | Q | "") return 0 ;;
      *) printf '  ? opción no válida\n' ;;
    esac
  done
}

_perfil_de() {
  local a
  for a in "$@"; do
    case "$a" in
      --*) ;;
      all | ALL | todos) printf '%s' "ALL" ;;
      *) printf '%s' "$a"
        return 0 ;;
    esac
  done
}

_cmd_preflight() {
  local p rc=0
  p="$(_perfil_de "$@")"
  printf '\n  %-15s %9s %9s %9s  %s\n' "PERFIL" "CRUDO" "SALIDA" "LIBRE" "ESTADO"
  if [[ -z "$p" || "$p" == "ALL" ]]; then
    local x
    while IFS= read -r x; do
      preflight "$x" || rc=1
    done < <(lista_perfiles)
  else
    existe_perfil "$p" || fatal "perfil desconocido: $p"
    preflight "$p" || rc=1
  fi
  return "$rc"
}

_cmd_fase() {
  local fn="$1"
  shift
  local p real=0
  if _es_real "$@"; then real=1; fi
  p="$(_perfil_de "$@")"
  [[ -n "$p" ]] || fatal "falta el perfil"
  validar_config || fatal "configuración incompleta: cada carpeta define sus propios interruptores"
  if [[ "$p" == "ALL" ]]; then
    local x rc=0
    while IFS= read -r x; do
      if [[ ! -d "$(destino "$x")" ]]; then
        aviso "$x: sin datos, se omite"
        continue
      fi
      if procesado_completo "$x"; then
        aviso "$x: ya procesado (listo para quemar), se omite"
        continue
      fi
      "$fn" "$x" "$real" || rc=1
    done < <(lista_perfiles)
    return "$rc"
  fi
  existe_perfil "$p" || fatal "perfil desconocido: $p"
  "$fn" "$p" "$real"
}

_cmd_verificar() {
  local p
  p="$(_perfil_de "$@")"
  [[ -n "$p" ]] || fatal "falta el perfil"
  if [[ "$p" == "ALL" ]]; then
    local x rc=0
    while IFS= read -r x; do
      if [[ -z "$(sets_de "$(destino "$x")" "${x}_")" ]]; then
        aviso "$x: sin juegos empaquetados, se omite"
        continue
      fi
      verificar "$x" || rc=1
    done < <(lista_perfiles)
    return "$rc"
  fi
  existe_perfil "$p" || fatal "perfil desconocido: $p"
  verificar "$p"
}

cmd_listar() {
  local modo="$MODO"
  [[ "${1:-}" == "pruebas" ]] && modo="pruebas"
  local raiz esp tot=0 tam p dest ori narch
  raiz="$(raiz_datos "$modo")"
  RAIZ="$raiz"
  esp="$(espacio_libre "$raiz")"
  [[ -d "$raiz" ]] || aviso "la raíz no existe en esta máquina: $raiz"

  printf '\n  RAIZ     : %s\n' "$raiz"
  printf '  LIBRE    : %s\n' "$(humano "$esp")"
  printf '  CICLO    : %s\n' "$(ciclo)"
  printf '  MEDIOS   : %s @ %s (%s de aire)\n' \
    "$(g medio)" "$(humano "$(volumen_bytes)")" "$(g aire_porcentaje)"
  printf '\n  %s%-15s %10s %7s  %-16s %s%s\n' "$C_NEG" "PERFIL" "TAMANO" "ARCHIVOS" "ORIGEN S14" "DESTINO" "$C_RESET"
  printf '  %-15s %10s %7s  %-16s %s\n' "---------------" "----------" "-------" "----------------" "-------"

  while IFS= read -r p; do
    dest="$(destino "$p")"
    ori="$(origen "$p" 2>/dev/null || echo "manual")"
    ori="${ori#$(s14 raiz)/}"
    [[ "$ori" == "$(s14 raiz)" ]] && ori="?"
    if [[ -d "$dest" ]]; then
      tam="$(bytes "$dest")"
      narch="$(find "$dest" -type f 2>/dev/null | wc -l)"
      tot=$((tot + tam))
      printf '  %-15s %10s %7s  %-16s %s\n' \
        "$p" "$(humano "$tam")" "$narch" "$ori" "$dest"
    else
      printf '  %-15s %10s %7s  %-16s %s%s%s\n' \
        "$p" "-" "-" "$ori" "$dest $C_AMAR(sin crear)$C_RESET"
    fi
  done < <(lista_perfiles)

  printf '  %-15s %10s\n' "TOTAL" "$(humano "$tot")"
  printf '\n'
}

cmd_origen() {
  local p="${1:-}"
  [[ -n "$p" ]] || fatal "uso: backup.sh origen <PERFIL>"
  existe_perfil "$p" || fatal "perfil desconocido: $p"
  local o
  if o="$(origen "$p")"; then
    printf '  Data de %s sale del Servidor 14:\n    %s@%s:%s\n' \
      "$p" "$(s14 usuario)" "$(s14 host)" "$o"
    printf '    (es lo que trae el "pull"; vacío = respaldo manual)\n'
  else
    printf '  %s es manual: no hay origen configurado en el Servidor 14.\n' "$p"
  fi
  printf '  Se quema desde (destino):  %s\n' "$(destino "$p")"
}

cmd_pull() {
  local p="" ejecutar=0 a
  PULL_HOY=""
  for a in "$@"; do
    case "$a" in
      --ejecutar | --real) ejecutar=1 ;;
      --fondo | --frente | --pull) ;;   # el plano lo decide cmd_pull_auto
      --hoy=*) PULL_HOY="${a#--hoy=}" ;;
      *) p="$a" ;;
    esac
  done

  [[ -n "$p" ]] || fatal "uso: backup.sh pull <PERFIL> [--hoy=FECHA] [--real]"
  local real=0
  [[ "$ejecutar" == "1" || "$(modo_actual)" == "real" ]] && real=1

  if [[ "$p" == "ALL" || "$p" == "all" ]]; then
    local x rc=0
    while IFS= read -r x; do pull_perfil "$x" "$real" || rc=1; done < <(lista_perfiles)
    return "$rc"
  fi
  existe_perfil "$p" || fatal "perfil desconocido: $p"
  pull_perfil "$p" "$real"
}

cmd_manifiesto() {
  local p="${1:-}"
  case "$p" in
    "" | all | ALL) p="" ;;
    *) existe_perfil "$p" || fatal "perfil desconocido: $p" ;;
  esac
  printf 'ciclo: %s\n' "$(ciclo)"
  printf 'ruta : %s\n\n' "$(ruta_manifiesto)"
  manifiesto_leer "$p"
  local n v b
  read -r n v b < <(manifiesto_total "$p")
  printf '\n  juegos OK: %s   volúmenes: %s   bytes: %s\n' "$n" "$v" "$(humano "$b")"
}

cmd_ciclos() {
  printf 'ciclo    : %s\n' "$(ciclo)"
  printf 'raiz     : %s\n' "$RAIZ"
  printf 'libre    : %s\n' "$(humano "$(espacio_libre "$RAIZ")")"
  printf 'medio    : %s @ %s (aire %s%%)\n' \
    "$(g medio)" "$(humano "$(volumen_bytes)")" "$(g aire_porcentaje)"
  printf 'volumen  : %s (%s bytes)\n' "$(g volumen)" "$(volumen_en_bytes)"
  printf 'quemados : %s\n' "$(dir_quemados)"
}

ELEGIDO=""

_cmd_perfil_nuevo() {
  local nombre="" origen="" manual=0 como="" a prev=""
  for a in "$@"; do
    case "$a" in
      --origen=*) origen="${a#--origen=}" ;;
      --origen)   ;;
      --manual)   manual=1 ;;
      --como=*)   como="${a#--como=}" ;;
      *)
        if [[ -z "$nombre" ]]; then nombre="$a"
        elif [[ "$prev" == "--origen" ]]; then origen="$a"
        elif [[ "$prev" == "--como" ]]; then como="$a"
        fi ;;
    esac
    prev="$a"
  done
  [[ -n "$nombre" ]] || fatal "uso: backup.sh perfil-nuevo <NOMBRE> [--origen RUTA_S14|--manual] [--como PERFIL]"
  perfil_crear "$nombre" "$origen" "$manual" "$como"
}

_cmd_perfil_quitar() {
  local nombre="${1:-}"
  [[ -n "$nombre" ]] || fatal "uso: backup.sh perfil-quitar <PERFIL>"
  perfil_quitar "$nombre"
}

_elegir_perfil() {
  local titulo="$1" con_all="${2:-}" extra="${3:-}" sel i=0 j p
  ELEGIDO=""
  printf '\n  %s%s%s\n' "$C_NEG" "$titulo" "$C_RESET"
  if [[ -n "$con_all" ]]; then
    printf '    %s0%s)  all  (todos)\n' "$C_CIAN" "$C_RESET"
  fi
  if [[ -n "$extra" ]]; then
    printf '   %sg%s)  %s\n' "$C_CIAN" "$C_RESET" "$extra"
  fi
  while IFS= read -r j; do
    i=$((i + 1))
    printf '   %2d)  %s\n' "$i" "$j"
  done < <(lista_perfiles | sort -f)
  printf '  %sEscribe el nº o el nombre del perfil. Enter/X = cancelar.%s\n' "$C_DIM" "$C_RESET"
  read -rp '  Perfil: ' sel
  case "${sel:-}" in
    "" | x | X | q | Q) aviso "cancelado"; return 1 ;;
    0) ELEGIDO=all; return 0 ;;
  esac
  if [[ -n "$extra" && ( "$sel" == "g" || "$sel" == "$extra" ) ]]; then
    ELEGIDO="_global_"
    return 0
  fi
  if [[ "$sel" =~ ^[0-9]+$ ]]; then
    p="$(lista_perfiles | sort -f | sed -n "${sel}p")"
  else
    p="$sel"
  fi
  if [[ -n "$p" ]] && existe_perfil "$p"; then
    ELEGIDO="$p"
    return 0
  fi
  aviso "perfil no válido: ${sel:-}"
  return 1
}

cmd_menu() {
  if [[ ! -t 0 ]]; then
    cmd_ayuda
    return 0
  fi
  set +e   # una opción que falle NO debe sacar del menú
  local p
  while true; do
    clear 2>/dev/null || true
    printf '%s=== RESPALDOS Blu-ray/DVD/CD ===%s   ciclo: %s\n' \
      "$C_NEG" "$C_RESET" "$(ciclo)"
    printf '  raíz: %s   libre: %s   medio: %s @ %s   volumen: %s\n' \
      "$RAIZ" "$(humano "$(espacio_libre "$RAIZ")")" \
      "$(g medio)" "$(humano "$(volumen_bytes)")" "$(g volumen)"
    printf '  ejecución: %s     plano: %s\n\n' "$(modo_etiqueta)" "$(plano_etiqueta)"
    local -a opc=()
    opc=(
      "0  Modos — ejecución (seco/real) y plano (frente/fondo)"
      "1  Listar perfiles — tamaños, origen y destino"
      "2  Preflight (espacio) — libre vs. necesario"
      "3  Ver origen en el S14 — de dónde sale la data"
      "4  Pull desde el S14 — traer los datos del perfil"
      "5  Procesar — limpiar+empaquetar+verificar+borrar"
      "6  Avance — perfil actual, fase y %"
      "7  Verificar — integridad (sha256) de los juegos"
      "8  Manifiesto — recibo CSV de lo quemado en el ciclo"
      "9  Configurar — interruptores y parámetros"
      "10 Carpetas — añadir/quitar perfiles y descubrir"
      "11 Ayuda — comandos no interactivos"
    )
    local i
    for i in "${!opc[@]}"; do
      printf '  %s\n' "${opc[$i]}"
    done
    printf '  %sX%s  Salir\n' "$C_MAG" "$C_RESET"
    printf '\n  %sElige por número (0-11) o letra X.%s\n' "$C_DIM" "$C_RESET"
    read -rp "$(cian '  Opción: ')" op
    case "$op" in
      x | X | q | Q | salir) printf '%sadiós%s\n' "$C_VERDE" "$C_RESET"; exit 0 ;;
      "") continue ;;
    esac
    case "$op" in
      0) _cmd_modos ;;
      1) cmd_listar ;;
      2) _cmd_preflight ;;
      3) _elegir_perfil 'Ver origen en el Servidor 14 (de dónde sale la data)' && cmd_origen "$ELEGIDO" ;;
      4) _elegir_perfil 'Pull desde el Servidor 14 (traer los datos a quemar)' all && cmd_pull_auto "$ELEGIDO" ;;
      5) _elegir_perfil 'Procesar (limpiar + empaquetar + verificar)' all && cmd_procesar "$ELEGIDO" ;;
      6) cmd_avance ;;
      7) _elegir_perfil 'Verificar juegos ya empaquetados' all && _cmd_verificar "$ELEGIDO" ;;
      8) _elegir_perfil 'Manifiesto del ciclo' all && cmd_manifiesto "$ELEGIDO" ;;
      9) cmd_configurar ;;
      10) cmd_carpetas ;;
      11) cmd_ayuda ;;
      *) printf '\n  ? opción no válida (0-11, o X)\n' ;;
    esac
    esperar_enter
  done
}

main() {
  local cmd="${1:-menu}"
  shift || true
  configurar
  asegurar_estado
  case "$cmd" in
    menu | m) cmd_menu "$@" ;;
    listar | l) cmd_listar "$@" ;;
    origen | o) cmd_origen "$@" ;;
    pull | p) cmd_pull_auto "$@" ;;
    preflight | pre) _cmd_preflight "$@" ;;
    limpiar | limpieza) _cmd_fase limpiar "$@" ;;
    empaquetar | empaquetado) _cmd_fase empaquetar "$@" ;;
    verificar | verificar_sets) _cmd_verificar "$@" ;;
    manifiesto | manif) cmd_manifiesto "$@" ;;
    configurar | config | cfg) cmd_configurar "$@" ;;
    perfil-nuevo | nuevo-perfil | nuevo) _cmd_perfil_nuevo "$@" ;;
    perfil-quitar | quitar-perfil | quitar) _cmd_perfil_quitar "$@" ;;
    descubrir | descubrir-carpetas) perfil_descubrir "${1:-}" ;;
    carpetas | perfiles) cmd_carpetas "$@" ;;
    procesar | proc) cmd_procesar "$@" ;;
    fondo | segundo_plano) cmd_fondo "$@" ;;
    fondo-pull) cmd_fondo_pull "$@" ;;
    fondo-iniciar | 2plano) cmd_fondo_iniciar "$@" ;;
    pull-fondo) cmd_fondo_iniciar --pull "$@" ;;
    avance | monitor | estado) cmd_avance "$@" ;;
    cron) cmd_cron "$@" ;;
    ciclos) cmd_ciclos "$@" ;;
    ayuda | -h | --help) cmd_ayuda ;;
    *) cmd_ayuda; fatal "comando desconocido: $cmd" ;;
  esac
}

main "$@"
