#!/usr/bin/env bash
# Batería de pruebas D (filtros incluir/excluir) — aislada en /tmp, nada real.
# Uso:  ssh servidor-produccion 'bash -s' < test-filtros.sh
set -u
export DIR_SISTEMA=/tmp/sistema-test
export CONFIG=/tmp/sistema-test/perfiles-filt.json
export RESPALDO_MODO=pruebas
export RAIZ=/tmp/respaldos-prueba/fquemar
mkdir -p "$DIR_SISTEMA/estado" "$DIR_SISTEMA/logs" "$RAIZ"
cp -f "$DIR_SISTEMA/perfiles.json" "$CONFIG"

source "$DIR_SISTEMA/lib/comunes.sh"
source "$DIR_SISTEMA/lib/config.sh"
source "$DIR_SISTEMA/lib/manifiesto.sh"
source "$DIR_SISTEMA/lib/fases.sh"
source "$DIR_SISTEMA/lib/pull.sh"

avisar_listo() { :; }
avisar_fallo() { :; }
ok()  { printf '   [OK]  %s\n' "$1"; }
mal() { printf '   [MAL] %s\n' "$1"; }
hr()  { printf '\n===== %s =====\n' "$1"; }

# --- perfil de pruebas RESFILT, creado desde la plantilla + todas las claves ---
claves="$(cfg_claves_carpeta | jq -R . | jq -s -c .)"
jq --argjson k "$claves" '
  .global.volumen = "1M"
  | .perfiles.RESFILT = (
      (reduce $k[] as $c ({}; . + {($c): (.perfiles.RESCALIPSO[$c] // (.[$c] // false))}))
      + (.plantilla // {})
      + {origen_s14:null, fuente:"manual", carpeta_fecha:false, por_usuario:false}
    )
' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"

set_filtro() { # excluir-a | incluir-a | limpio
  case "$1" in
    excluir) jq '.perfiles.RESFILT.excluir=["invento"] | .perfiles.RESFILT.incluir=[]' "$CONFIG" >"$CONFIG.t" ;;
    incluir) jq '.perfiles.RESFILT.incluir=["solo"]   | .perfiles.RESFILT.excluir=[]' "$CONFIG" >"$CONFIG.t" ;;
    limpio)  jq '.perfiles.RESFILT.incluir=[]         | .perfiles.RESFILT.excluir=[]' "$CONFIG" >"$CONFIG.t" ;;
  esac
  mv "$CONFIG.t" "$CONFIG"
}

D="$(destino RESFILT)"
fecha="$(fecha_de RESFILT "$D")"
lista_set() { # imprime las rutas dentro del set
  local a; a="$(primer_archivo "$D/RESFILT_${fecha}")"
  [[ -n "$a" ]] || return 0
  ( cd "$D" && rar lb "$(basename "$a")" 2>/dev/null )
}

hr "PRUEBA F1 — excluir: 'invento' NO se respalda ni se borra"
set_filtro excluir
rm -rf "$D"; mkdir -p "$D/invento" "$D/real"
head -c 1500000 /dev/urandom >"$D/invento/x.bin"
head -c 1500000 /dev/urandom >"$D/real/y.bin"
procesar_unidades RESFILT 2>/dev/null | sed 's/^/   /'
con="$(lista_set)"
grep -q 'real/y.bin' <<<"$con" && ok "incluido 'real/y.bin' esta en el set" || mal "falta real/y.bin en el set"
grep -q 'invento/x.bin' <<<"$con" && mal "'invento/x.bin' se respaldo (no debia)" || ok "excluido 'invento' NO esta en el set"
[[ -f "$D/invento/x.bin" ]] && ok "excluido intacto en disco" || mal "se borro lo excluido"
[[ -e "$D/real" ]] && mal "'real' no se borro tras respaldar" || ok "'real' borrado tras respaldar"
[[ -f "$D/RESFILT_${fecha}.sha256" ]] && ok ".sha256 escrito" || mal "sin .sha256"

hr "PRUEBA F2 — incluir: SÓLO 'solo' se respalda"
set_filtro incluir
rm -rf "$D"; mkdir -p "$D/solo" "$D/otro"
head -c 1500000 /dev/urandom >"$D/solo/s.bin"
head -c 1500000 /dev/urandom >"$D/otro/o.bin"
procesar_unidades RESFILT 2>/dev/null | sed 's/^/   /'
con="$(lista_set)"
grep -q 'solo/s.bin' <<<"$con" && ok "incluido 'solo/s.bin' esta en el set" || mal "falta solo/s.bin"
grep -q 'otro/o.bin' <<<"$con" && mal "'otro/o.bin' se respaldo (no debia)" || ok "no incluido 'otro' NO esta en el set"
[[ -e "$D/otro" ]] && ok "no incluido 'otro' intacto" || mal "se borro 'otro'"
[[ -e "$D/solo" ]] && mal "'solo' no se borro" || ok "'solo' borrado tras respaldar"

hr "PRUEBA F3 — limpiar respeta los filtros (no borra dentro de 'invento')"
set_filtro excluir
jq '.perfiles.RESFILT.borrar=["tmp"] | .perfiles.RESFILT.borrar_vacios=true' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
rm -rf "$D"; mkdir -p "$D/invento/vacia" "$D/real/vacia"
echo x >"$D/invento/a.tmp"; echo x >"$D/real/b.tmp"
limpiar RESFILT 1 2>/dev/null | sed 's/^/   /'
[[ -f "$D/invento/a.tmp" ]] && ok "excluido a.tmp conservado" || mal "se borro a.tmp excluido"
[[ -e "$D/real/b.tmp" ]] && mal "b.tmp no se limpio" || ok "incluido b.tmp borrado"
[[ -d "$D/invento/vacia" ]] && ok "excluida carpeta vacia conservada" || mal "se borro la carpeta vacia excluida"
[[ -d "$D/real/vacia" ]] && mal "carpeta vacia incluida no se borro" || ok "incluida carpeta vacia borrada"

hr "PRUEBA F4 — procesado_completo ignora lo excluido"
set_filtro excluir
jq '.perfiles.RESFILT.borrar=[] | .perfiles.RESFILT.borrar_vacios=false' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
rm -rf "$D"; mkdir -p "$D/invento" "$D/real"
head -c 1500000 /dev/urandom >"$D/invento/x.bin"
head -c 1500000 /dev/urandom >"$D/real/y.bin"
procesar_unidades RESFILT 2>/dev/null >/dev/null
[[ -d "$D/invento" ]] && ok "'invento' sigue en disco (a proposito)" || mal "'invento' desaparecio"
procesado_completo RESFILT && ok "procesado_completo=0 pese a 'invento'" || mal "procesado_completo=1 (lo excluido bloquea)"

hr "PRUEBA F5 — troceo por archivo respeta los filtros"
set_filtro excluir
jq '.perfiles.RESFILT.empaquetar=false | .perfiles.RESFILT.trocear_grandes=true | .perfiles.RESFILT.comprimir=false' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
rm -rf "$D"; mkdir -p "$D/invento"
head -c 1500000 /dev/urandom >"$D/grande.bin"
head -c 1500000 /dev/urandom >"$D/invento/g2.bin"
empaquetar RESFILT 1 2>/dev/null | sed 's/^/   /'
[[ -e "$D/grande.bin" ]] && mal "grande.bin no se troceo" || ok "grande.bin troceado y borrado"
[[ -e "$D/invento/g2.bin" ]] && ok "invento/g2.bin intacto (excluido)" || mal "se troceo lo excluido"
jq '.perfiles.RESFILT.empaquetar=true | .perfiles.RESFILT.trocear_grandes=false | .perfiles.RESFILT.comprimir=true' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"

hr "PRUEBA F6 — patrones rsync del pull"
set_filtro incluir
printf '   incluir=["solo"] ->\n'; pull_filtros RESFILT | sed 's/^/      /'
set_filtro excluir
printf '   excluir=["invento"] ->\n'; pull_filtros RESFILT | sed 's/^/      /'
sal="$(pull_filtros RESFILT)"
grep -q -- '--exclude=/invento' <<<"$sal" && ok "excluir produce --exclude=/invento" || mal "patron excluir ausente"
set_filtro incluir
sal="$(pull_filtros RESFILT)"
grep -q -- '--include=/solo/***' <<<"$sal" && grep -q -- '--exclude=\*' <<<"$sal" \
  && ok "incluir produce --include + --exclude=*" || mal "patrones incluir mal"

hr "PRUEBA F7 — sin filtros: comportamiento clasico (todo)"
set_filtro limpio
jq '.perfiles.RESFILT.carpeta_fecha=true' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
rm -rf "$D"; mkdir -p "$D/$fecha/a" "$D/$fecha/b"
head -c 1500000 /dev/urandom >"$D/$fecha/a/1.bin"; head -c 1500000 /dev/urandom >"$D/$fecha/b/2.bin"
procesar_unidades RESFILT 2>/dev/null | sed 's/^/   /'
con="$(lista_set)"
grep -q 'a/1.bin' <<<"$con" && grep -q 'b/2.bin' <<<"$con" \
  && ok "sin filtros se respalda TODO" || mal "sin filtros no se respaldo todo"
[[ -e "$D/$fecha/a" || -e "$D/$fecha/b" ]] && mal "queda fuente sin filtros" || ok "fuente borrada"
RFC="$(pull_filtros RESFILT)"
[[ -z "$RFC" ]] && ok "sin filtros no se añaden patrones al pull" || mal "pull añade patrones sin filtros"

hr "PRUEBA F8 — filtros con carpeta_fecha=true (forma real)"
set_filtro excluir
rm -rf "$D"; mkdir -p "$D/$fecha/invento" "$D/$fecha/real"
head -c 1500000 /dev/urandom >"$D/$fecha/invento/x.bin"
head -c 1500000 /dev/urandom >"$D/$fecha/real/y.bin"
procesar_unidades RESFILT 2>/dev/null | sed 's/^/   /'
con="$(lista_set)"
grep -q 'real/y.bin' <<<"$con" && ok "incluido 'real/y.bin' esta en el set" || mal "falta real/y.bin"
grep -q 'invento/x.bin' <<<"$con" && mal "se respaldo lo excluido" || ok "excluido NO esta en el set"
[[ -f "$D/$fecha/invento/x.bin" ]] && ok "excluido intacto" || mal "se borro lo excluido"
[[ -e "$D/$fecha/real" ]] && mal "'real' no se borro" || ok "'real' borrado"

hr "FIN"
