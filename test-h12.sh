#!/usr/bin/env bash
# Batería de pruebas H.12 — se ejecuta en servidor-produccion bajo /tmp (nada real).
# Uso:  ssh servidor-produccion 'bash -s' < test-h12.sh
set -u
export DIR_SISTEMA=/tmp/sistema-test
export CONFIG="$DIR_SISTEMA/perfiles.json"
export RESPALDO_MODO=pruebas
export RAIZ=/tmp/respaldos-prueba/quemar
mkdir -p "$DIR_SISTEMA/estado" "$DIR_SISTEMA/logs" "$RAIZ"

source "$DIR_SISTEMA/lib/comunes.sh"
source "$DIR_SISTEMA/lib/config.sh"
source "$DIR_SISTEMA/lib/manifiesto.sh"
source "$DIR_SISTEMA/lib/fases.sh"

# --- stubs: nada de correo ---
avisar_listo() { printf '   >>[stub] avisar_listo %s (ok=%s mal=%s)\n' "$1" "${VER_OK:-?}" "${VER_MAL:-?}"; }
avisar_fallo() { printf '   >>[stub] avisar_fallo %s: %s\n' "$1" "$2"; }

pz="$(volumen_en_bytes)"   # 98000000
hr() { printf '\n===== %s =====\n' "$1"; }
ok() { printf '   [OK]  %s\n' "$1"; }
mal() { printf '   [MAL] %s\n' "$1"; }

estado() {
  local p="$1" d; d="$(destino "$p")"
  printf '   -- contenido de %s:\n' "$d"
  ls -l "$d" 2>/dev/null | awk 'NR>1{printf "      %10s  %s\n",$5,$9}'
  printf '   -- carpetas de fuente que quedan: %s\n' "$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  local b
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    printf '      set %-28s piezas=%-3s sha=%s\n' "$(basename "$b")" \
      "$(numero_de_volumenes "$b")" "$([ -f "$b.sha256" ] && echo SI || echo NO)"
  done < <(sets_de "$d" "${p}_")
}

hr "PRUEBA 0 — _set_parece_completo"
T="$RAIZ/tmp-sets"; rm -rf "$T"; mkdir -p "$T"
head -c "$pz" /dev/urandom >"$T/trunc.part1.rar"
head -c "$pz" /dev/urandom >"$T/ok.part1.rar"; head -c 500000 /dev/urandom >"$T/ok.part2.rar"
head -c 30 /dev/urandom >"$T/uno.rar"
_set_parece_completo "$T/trunc" && mal "trunc (ultima==volumen) dio completo" || ok "trunc -> no completo"
_set_parece_completo "$T/ok"    && ok "ok (ultima<volumen) -> completo"        || mal "ok -> no completo"
_set_parece_completo "$T/uno"   && ok "uno (.rar sin trocear) -> verificable"  || mal "uno -> no verificable"

hr "PRUEBA 1 — flujo por unidad completo (procesar RESMAIL)"
D="$RAIZ/RESMAIL"; rm -rf "$D"; mkdir -p "$D"
for u in administracion aleon bodegagye; do
  mkdir -p "$D/$u/sub"; head -c 1500000 /dev/urandom >"$D/$u/correo1.mbx"; head -c 900000 /dev/urandom >"$D/$u/sub/correo2.mbx"
done
echo "--- REAL ---"; procesar RESMAIL 1 2>/dev/null
estado RESMAIL
[ "$(find "$D" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ] && ok "fuente borrada" || mal "queda fuente"
[ -f "$D/RESMAIL_administracion.sha256" ] && ok ".sha256 escrito" || mal "sin .sha256"
procesado_completo RESMAIL && ok "procesado_completo=0 (hecho)" || mal "procesado_completo=1"

hr "PRUEBA 2 — confiar en .sha256 (unidad nueva no re-verifica las viejas)"
mkdir -p "$D/cajauio"; head -c 1200000 /dev/urandom >"$D/cajauio/x.mbx"
mt_ant="$(stat -c %Y "$D/RESMAIL_administracion.rar")"
t0=$(date +%s); procesar RESMAIL 1 2>/dev/null; t1=$(date +%s)
mt_dsp="$(stat -c %Y "$D/RESMAIL_administracion.rar")"
estado RESMAIL
[ "$mt_ant" = "$mt_dsp" ] && ok "sets viejos NO se re-verificaron (mtime intacto)" || mal "se tocaron los sets viejos"
[ -f "$D/RESMAIL_cajauio.sha256" ] && ok "unidad nueva empaquetada y verificada" || mal "cajauio sin sha"
printf '   (tardo %ss)\n' "$((t1-t0))"

hr "PRUEBA 3 — set completo SIN .sha256 -> verifica, no re-empaqueta"
P=RESCALIPSO; D="$RAIZ/$P"; rm -rf "$D"; mkdir -p "$D/2026-10-13"
head -c 250000000 /dev/urandom >"$D/2026-10-13/big.bin"
( cd "$D/2026-10-13" && rar a -m0 -rr3% -r -v98M "$D/${P}_2026-10-13.rar" . >/dev/null 2>&1 )
md5_ant="$(md5sum "$D"/*.rar | md5sum)"
procesar_unidades "$P" 2>/dev/null | sed 's/^/   /'
estado "$P"
md5_dsp="$(md5sum "$D"/*.rar | md5sum)"
[ "$md5_ant" = "$md5_dsp" ] && ok "NO re-empaqueto (piezas intactas)" || mal "re-empaqueto el set"
[ -f "$D/${P}_2026-10-13.sha256" ] && ok "verifico y escribio .sha256" || mal "sin .sha256"
[ -d "$D/2026-10-13" ] && mal "no borro la carpeta fechada" || ok "carpeta fechada borrada"

hr "PRUEBA 4 — set completo SIN sha pero CORRUPTO -> reusa, falla, rehace"
rm -rf "$D"; mkdir -p "$D/2026-10-13"
head -c 250000000 /dev/urandom >"$D/2026-10-13/big.bin"
( cd "$D/2026-10-13" && rar a -m0 -rr3% -r -v98M "$D/${P}_2026-10-13.rar" . >/dev/null 2>&1 )
printf 'BASURA' | dd of="$D/${P}_2026-10-13.part1.rar" bs=1 seek=100000 conv=notrunc status=none
procesar_unidades "$P" 2>/dev/null | sed 's/^/   /'
estado "$P"
[ -f "$D/${P}_2026-10-13.sha256" ] && ok "rehecho y verificado" || mal "sin sha tras rehacer"

hr "PRUEBA 5 — fallo de verificación -> NO se borra la fuente (subshell)"
rm -rf "$D"; mkdir -p "$D/2026-10-13"; head -c 1200000 /dev/urandom >"$D/2026-10-13/big.bin"
(
  _verificar_set() { printf '  FALLA %s (simulada)\n' "$(basename "$2")"; return 1; }
  procesar_unidades "$P" 2>/dev/null
) | sed 's/^/   /'
[ -d "$D/2026-10-13" ] && ok "fuente conservada" || mal "borro la fuente con verificacion fallida"

hr "PRUEBA 6 — por_usuario (RESHOME): una unidad por usuario"
RH="$RAIZ/RESHOME"; rm -rf "$RH"; mkdir -p "$RH"
for u in alvarez perez juan; do mkdir -p "$RH/$u"; head -c 400000 /dev/urandom >"$RH/$u/d.txt"; done
procesar_unidades RESHOME 2>/dev/null | sed 's/^/   /'
ls -l "$RH" | awk 'NR>1{printf "      %10s  %s\n",$5,$9}'
[ "$(find "$RH" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ] && ok "usuarios borrados tras verificar" || mal "quedan usuarios"

hr "PRUEBA 7 — idempotente: re-ejecutar no hace nada"
sal="$(procesar_unidades RESHOME 2>/dev/null)"
printf '%s\n' "$sal" | sed 's/^/   /'
grep -q 'ya está procesado' <<<"$sal" && ok "idempotente: reconoce que ya está hecho" || mal "intento reprocesar"

hr "PRUEBA 8 — fuente MAS NUEVA que el .sha256 -> NO confia, rehace"
rm -rf "$D"; mkdir -p "$D/2026-10-13"
head -c 1200000 /dev/urandom >"$D/2026-10-13/a.bin"
procesar_unidades "$P" 2>/dev/null | sed 's/^/   /' >/dev/null
sleep 1
md5_ant="$(md5sum "$D"/*.rar | md5sum)"
mkdir -p "$D/2026-10-13"                                  # el procesado borro la fuente...
head -c 500000 /dev/urandom >"$D/2026-10-13/nuevo.bin"     # ...y la fuente VUELVE, mas nueva
echo "   (fuente re-aparece despues de verificar; ejecuto de nuevo)"
procesar_unidades "$P" 2>/dev/null | sed 's/^/   /'
estado "$P"
md5_dsp="$(md5sum "$D"/*.rar | md5sum)"
[ "$md5_ant" != "$md5_dsp" ] && ok "NO confio en el sha: rehizo el set" || mal "confio en sha viejo (riesgo de perder datos)"
[ -d "$D/2026-10-13" ] && mal "la fuente nueva sigue ahi" || ok "fuente nueva incluida y borrada"

hr "FIN"
