#!/usr/bin/env bash

[[ -n "${_NOTIFY_CARGADA:-}" ]] && return 0
_NOTIFY_CARGADA=1

DIR_NOTIF="${DIR_NOTIF:-$DIR_SISTEMA/notificaciones}"

destinatarios() { jq -r '.global.correo[]?' "$CONFIG" 2>/dev/null; }

cuadra() {
  printf '<pre style="font-family:monospace;font-size:13px;line-height:1.45">%s</pre>' "$1"
}

filas_tabla() {
  local salida="" fila
  while IFS='|' read -r a b c d; do
    [[ -z "$a" ]] && continue
    printf -v fila '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>' "$a" "$b" "$c" "$d"
    salida+="$fila"
  done
  printf '%s' "$salida"
}

notificar() {
  local asunto="$1" cuerpo="$2"
  local dest
  dest="$(destinatarios)"
  if [[ -z "$dest" ]]; then
    aviso "sin correo configurado en perfiles.json -> aviso en consola: $asunto"
    [[ "${RESPALDO_VERBOSE:-0}" == "1" ]] && printf '%s\n' "$cuerpo"
    return 0
  fi
  if ! command -v msmtp >/dev/null 2>&1; then
    aviso "msmtp no instalado -> aviso en consola: $asunto"
    [[ "${RESPALDO_VERBOSE:-0}" == "1" ]] && printf '%s\n' "$cuerpo"
    return 0
  fi
  local d
  for d in $dest; do
    if [[ -x "$DIR_NOTIF/enviar-correo.sh" ]]; then
      printf '%s' "$cuerpo" | "$DIR_NOTIF/enviar-correo.sh" "$asunto" "$d"
    else
      aviso "no existe $DIR_NOTIF/enviar-correo.sh"
      return 1
    fi
  done
}

_tabla_manifiesto() {
  local p="$1" f fila
  f="$(ruta_manifiesto)"
  printf '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-family:monospace;font-size:13px">'
  printf '<tr style="background:#eee"><th>juego</th><th>volumenes</th><th>tamano</th><th>sha256</th></tr>'
  [[ -f "$f" ]] && while IFS=, read -r c fe per juego vol bytes sha estado; do
    [[ "$per" == "$p" ]] || continue
    [[ "$estado" == "OK" ]] || continue
    printf '<tr><td>%s</td><td>%s</td><td>%s</td><td style="font-size:11px">%s</td></tr>' \
      "$juego" "$vol" "$(humano "$bytes")" "$sha"
  done <"$f"
  printf '</table>'
}

_tabla_brutos() {
  local p="$1" d c f
  d="$(destino "$p")"
  printf '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-family:monospace;font-size:13px">'
  printf '<tr style="background:#eee"><th>ruta</th><th>tamano</th></tr>'
  if command -v contenedores >/dev/null 2>&1; then
    while IFS= read -r c; do
      [[ -e "$c" ]] || continue
      printf '<tr><td>%s</td><td>%s</td></tr>' "${c#"$RAIZ"/}" "$(humano "$(bytes "$c")")"
    done < <(contenedores "$p")
  fi
  while IFS= read -r f; do
    printf '<tr><td>%s</td><td>%s</td></tr>' "${f#"$RAIZ"/}" "$(humano "$(bytes "$f")")"
  done < <(find "$d" -maxdepth 1 -type f 2>/dev/null | sort)
  printf '</table>'
}

avisar_listo() {
  local p="$1" ok="${VER_OK:-0}" mal="${VER_MAL:-0}" tam tabla
  if [[ "$ok" -gt 0 ]]; then
    tam="$(manifiesto_total "$p")"
    tam="$(printf '%s' "$tam" | cut -d' ' -f3)"
    tabla="$(_tabla_manifiesto "$p")"
  else
    tam="$(bytes "$(destino "$p")")"
    tabla="$(_tabla_brutos "$p")"
  fi
  local cuerpo
  cuerpo="<h2>Respaldos listos para quemar: $p</h2>
<p>ciclo <b>$(ciclo)</b> &middot; $ok juego(s) verificado(s) &middot; $mal fallo(s) &middot; salida: $(humano "$tam")</p>
$tabla
<p>Este es un aviso automático de <code>backup.sh</code> en $(hostname).</p>"
  notificar "[Respaldos] $p: $ok listos para quemar" "$cuerpo"
}

avisar_fallo() {
  local p="$1" motivo="$2"
  notificar "[Respaldos][AVISO] $p: $motivo" \
    "<p><b>$p</b>: $motivo</p><p>ciclo $(ciclo) &middot; $(hostname)</p>"
}

avisar_pull() {
  local p="$1" destino="$2" resumen="$3"
  notificar "[Respaldos] pull de $p terminado" \
    "<h2>Pull de $p</h2><p>destino: <code>$destino</code></p>$resumen"
}
