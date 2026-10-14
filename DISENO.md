# OrganizarBackups — Respaldo, compresión y quema de discos

Documento de referencia del proyecto: hallazgos, estado actual, diseño propuesto, pendientes y avances.

> **¿Buscas cómo usarlo?** Este documento (DISENO.md) es el de **diseño**. El uso diario
> (menú, comandos, configuración, flujo) está en **[`MANUAL.md`](MANUAL.md)**.

| | |
|---|---|
| **Fecha del documento** | 2026-10-06 |
| **Estado** | **Fase 0 (documentación) muy avanzada** — hallazgos + estructura real + diseño casi cerrado (§4–§7). Falta: rutas de origen en el Servidor 14 (P4) y empezar a codificar. |
| **Origen del material** | `backup.zip` (26 scripts, copiado el 2026-01-20) → descomprimido en `backup/` |
| **Máquina de análisis** | `equipo-local` (esta) |
| **Máquina operativa** | `usuario@servidor-produccion` → `/mnt/DATOS/quemar/` |
| **Herramienta actual** | 26 scripts `.sh` casi idénticos + `dele.sh` (intentos de menú comentados) |

---

## 0. Resumen ejecutivo

**Qué se está construyendo:** documentar y luego reemplazar los 26 scripts `.sh` por **un solo sistema** que respalde y queme (BD / DVD / CD) los datos de `servidor-produccion` (= «servidor 45»), con compresión, verificación, aviso por correo, reanudación y **copia pull desde el Servidor 14**.

**Estado:** **Fase 0 (documentación) muy avanzada — diseño casi cerrado.** Falta implementar (§Bloque 1) y cerrar P4–P7.

**Ya confirmado:**

- **9 carpetas** hoy en `quemar/` (no 7): `RESCALIPSO`, `RESDOCKER`, `RESINTRANET`, `RESMAIL`, `RESNAS`, `RESNETSUITE`, `RESNEXTCLOUD`, `RESODOO`, `USUARIOS` → **~724 G / 1 071 908 archivos** (§4.1, §4.3).
- **Set de perfiles (decidido):** 6 directos + NAS descompuesto en **5** (`RESHOME`, `RESPUBLICO`, `RESPRIVADO`, `RESELECTRON`, `RESISO`) + `RESNEXTCLOUD` + **`RESOTROS`** (ex `USUARIOS`, bajas) → **13 perfiles** (§4.8).
- **Volumen único `-v98M`** (2 % de aire). BD-R real → **242–250 piezas** (§5).
- **Correo: `msmtp` + Gmail** (§7.5).
- **Origen de todo: el Servidor 14** → el script crea `quemar/<PERFIL>/YYYY-MM-DD/` y lanza el `rsync` (§7.10).
- **Perfiles ya comprimidos:** RESCALIPSO/RESODOO/RESINTRANET → **solo trocear** (`comprimir:false` = piezas de 98 MB en modo *store*, sin recomprimir, ver H.1); RESNETSUITE **sí** comprime; todos se **envuelven en carpeta fechada** (§4.3.2, §7.9).
- **Principio del usuario:** cada usuario conserva su carpeta (§7.8).
- **Alcance por tandas:** el origen `respaldos:/mnt/bak` pesa **~6 TB** → no se respalda todo; se copian **tandas** que el usuario elige (p. ej. hoy correos) y se queman. Estos discos son la **4.ª copia** (§4.8, §7.10).

**Riesgos que el diseño ya corrige** (detalle en §3): **C1** (no operar sobre el CWD), **C3** (archivos sueltos ignorados), **C5** (verificar antes de borrar), **A1** (comodines de borrado), **A8** (volúmenes parciales).

**Bloqueante para empezar a programar: ninguno** — el mapeo de perfiles → origen en el Servidor 14 ya está cerrado (§4.8, §7.10). Quedan ajustes (P5/P6/P7 y correo).

---

## 1. Objetivo

Tener **un solo punto de entrada** desde la consola que:

1. Muestre **qué hay para respaldar** (detección automática de carpetas pendientes).
2. **Verifique espacio** antes de empezar y avise si no va a alcanzar.
3. Ejecute limpieza + compresión **en segundo plano**, sobreviviendo al cierre de la sesión SSH.
4. Permita **revisar el estado / reanudar** al volver otro día.
5. **Notifique por email** cuando termine, para ponerse a quemar discos.
6. Incluya la opción de **montar el Servidor 14** para dejar copiando datos hacia esta máquina.
7. Separe y **identifique los respaldos por tipo** (RESCALIPSO, RESDOCKER, RESINTRANET, RESMAIL, RESNAS, RESNETSUITE, RESNEXTCLOUD, RESODOO, USUARIOS) y **por usuario** dentro de cada uno (§7.8).

---

## 2. Inventario del material recibido

### 2.1 Los 26 scripts

Todos comparten el mismo esqueleto de 6 fases. Solo cambian **la ruta** y **el tamaño de volumen**.

| # | Script | Ruta destino | Vol. | Fases | Nota |
|---|---|---|---|---|---|
| 1 | `usuario-a.sh` | `quemar/usuario-a/` | 694M | T D B V R | |
| 2 | `BAK.sh` | `quemar/BAK/` | 694M | T D B V R | |
| 3 | `caratulas.sh` | `quemar/CARATULAS/` | 694M | T D B V R | |
| 4 | `electron.sh` | `quemar/2026/RESNAS/electron/` | 687M | R | sin limpieza |
| 5 | `usuario-b.sh` | `quemar/usuario-b/` | 694M | T D B V R | |
| 6 | `home.sh` | `quemar/2026/RESNAS/home/` | 688M | D B V R | sin T |
| 7 | `ISO.sh` | `quemar/2026/RESNAS/ISO/` | 688M | R | sin limpieza |
| 8 | `usuario-c.sh` | `quemar/usuario-c/` | 694M | T D B V R | |
| 9 | `netsuite.sh` | `quemar/2026/RESNETSUITE/` | 688M | D B V R | sin T |
| 10 | `nextcloud.sh` | `quemar/RESNEXTCLOUD/` | 694M | T D B V R | |
| 11 | `privado.sh` | `quemar/2026/RESNAS/PRIVADO/` | 687M | D B V R | sin T |
| 12 | `publico.sh` | `quemar/2026/RESNAS/publico/` | 687M | T D B V R | **borra `*.jpg` y `*.png`** |
| 13 | `rescalipso.sh` | `quemar/RESCALIPSO/` | 694M | T D B V R | |
| 14 | `resintranet.sh` | `quemar/2026/RESINTRANET/` | 694M | T D B V R | |
| 15 | `resmail.sh` | `quemar/2026/RESMAIL/` | 666M | R | sin limpieza |
| 16 | `resmail2.sh` | `quemar/salieronEE/RESMAIL/` | 694M | T D B V R | colisión de nombre con 15 |
| 17 | `resnextcloud.sh` | `quemar/2026/RESNC/` | 666M | T D B V R | |
| 18 | `resodoo.sh` | `quemar/2026/RESODOO/` | 687M | T D B V R | |
| 19 | `restakeout.sh` | `quemar/salieronEE/google takeout/` | 694M | T D B V R | |
| 20 | `resvm.sh` | `quemar/RESVM/` | 694M | T D B V R | |
| 21 | `resweb.sh` | `quemar/RESWEB/` | 687M | T D B V R | |
| 22 | `usuario-d.sh` | `quemar/usuario-d/` | 694M | T D B V R | |
| 23 | `usuario-e.sh` | `quemar/usuario-e/` | 694M | T D B V R | |
| 24 | `usuarios.sh` | `quemar/usuarios/` | 694M | T D B V R | el directorio real es `USUARIOS` |
| 25 | `webcalipso.sh` | `quemar/RESINTRANET/` | 694M | D B V R | apunta a la misma carpeta que 14 si `2026/` ya no existe |
| 26 | `dele.sh` | — | — | — | 8 líneas, todas comentadas: esbozo de menú |

**Fases:** `T` = borrar `files_trashbin` · `D` = `fdupes` (deduplicar) · `B` = borrar basura por extensión · `V` = borrar vacíos · `R` = `rar -df` (comprimir y mover).

**Distribución de volúmenes:** 694M ×15 · 687M ×5 · 688M ×3 · 666M ×2 · (sin rar: `dele.sh`).

### 2.2 El esqueleto repetido (referencia: `backup/rescalipso.sh`)

```bash
#!/bin/bash
carpeta="/mnt/DATOS/quemar/RESCALIPSO/"
cd "$carpeta"                                              # línea 4
find . -type d -name "files_trashbin" -exec rm -rf {} +    # T
for folder in */; do fdupes -rdN "$folder"; done           # D
find . -type f \( -name \*.gif -o ... \) -delete           # B (línea 13)
find . -empty -type f -delete                              # V
find . -empty -type d -delete                              # V
for folder in */; do rar a -m5 -v694M -df -R "${folder%/}.rar" "$folder"; done   # R (línea 18)
find . -empty -type d -delete                              # limpieza final
```

---

## 3. Hallazgos

### 3.1 CRÍTICOS — pueden perder datos

| ID | Hallazgo | Evidencia |
|---|---|---|
| **C1** | **No hay verificación de que la carpeta exista.** Si `cd "$carpeta"` falla, el script **sigue ejecutándose en el directorio de trabajo actual** (donde lo invoques): `fdupes -d`, `find -delete` y `rm -rf` corren contra ese directorio. | `rescalipso.sh:4` — sin `set -e`, sin `[ -d "$carpeta" ] \|\| exit` |
| **C2** | **`publico.sh` borra `*.jpg` y `*.png`.** En un respaldo eso es pérdida directa de imágenes. | `publico.sh:13` (versión comentada en línea 11 sugiere que se añadió después) |
| **C3** | **Los archivos sueltos en la raíz de `carpeta` nunca se comprimen, pero sí se borran.** Todo el modelo itera `for folder in */`; cualquier `.mp3`, `.gif`, `.tmp`, archivo vacío o duplicado **a nivel superior** pasa por `find -delete` y queda fuera del `rar`. | `rescalipso.sh:9,13,15,18` |
| **C4** | **`fdupes -rdN` borra duplicados de forma irreversible y sin confirmación** (elegido el primer hallazgo al azar). Sobre datos ya deduplicados vuelve a actuar en cada corrida. | `rescalipso.sh:9` |
| **C5** | **`rar ... -df` = mover** (`rar.txt:880-883`: «-df Delete files after archiving … performs the same action as the command "M"»). Si el proceso muere a mitad de un volumen, o el volumen se daña, la fuente ya no existe. **No hay verificación (`rar t`) antes de borrar.** | `rescalipso.sh:18` |
| **C6** | **Varios scripts apuntan a rutas que probablemente ya no existen** (ver §4). Combinado con C1 = ejecución destructiva en el CWD. | §4 |

### 3.2 ALTOS — rompen o invalidan el proceso

| ID | Hallazgo | Detalle |
|---|---|---|
| **A1** | **7 de las 15 extensiones de la lista de basura no borran nada:** falta el `*`. → **ver demostración §3.2.1** | `rescalipso.sh:13` y 21 scripts más (22 en total) |
| **A2** | **"Arreglar" A1 sería peligroso:** si se corrigiera a `*.iso` y `*.img`, el script borraría exactamente lo que `ISO.sh` se esfuerza por respaldar. **La lista de basura debe ser por perfil, no global**, y nunca debe incluir `.iso/.img/.exe` por defecto. | consecuencia de A1 |
| **A3** | **3 variantes distintas de lista de basura** entre los 26 scripts (una con 9 extensiones, otra con 15, una tercera con 11 que añade jpg/png). Sin documentar por qué. | ver Apéndice A |
| **A4** | **4 tamaños de volumen distintos sin justificación** (666/687/688/694M). Ningún script explica el porqué. | §5 |
| **A5** | **Modelo de carpetas inconsistente: 3 generaciones conviven.** `quemar/XX/`, `quemar/2026/XX/`, `quemar/salieronEE/XX/`. El `ls` del servidor solo muestra rutas de primer nivel → la mayoría de los `2026/…` quedaron obsoletos. | §4 |
| **A6** | **Falta `RESDOCKER`.** Existe la carpeta de datos (actualizada hoy) y **no hay ningún script** que la respalde. | `ls` del servidor |
| **A7** | **Sin `set -euo pipefail`, sin log, sin lock, sin código de salida.** Un fallo intermedio pasa desapercibido: el script "termina bien" y no hay rastro de qué se hizo. | los 26 |
| **A8** | **No hay idempotencia en la fase R.** Si un `rar` queda interrumpido con `.part1.rar` huérfano, re-ejecutar `rar a foo.rar foo/` puede fallar o mezclar volúmenes (RAR **no permite modificar un volumen existente**). No hay limpieza ni detección de volúmenes parciales. | `rescalipso.sh:18` |

### 3.2.1 A1 explicado con un ejemplo

Así está la línea en tus scripts (simplificado):

```bash
find . -type f \( -name \*.gif -o -name \*.pst -o -name \.msi -o -name \.tmp -o -name \.iso ... \) -delete
```

`find -name PATRÓN` compara **el nombre del archivo contra el patrón**. Y en un patrón de `find` **sin `*` no hay comodín**: busca el texto exacto.

| Escrito en el script | `find` recibe | ¿Qué coincide? | ¿Funciona? |
|---|---|---|---|
| `-name \*.gif` | `*.gif` | `foto.gif`, `a.gif`, `cualquiera.gif` | ✅ sí |
| `-name \.msi` | `.msi` | **solo** un archivo llamado exactamente `.msi` | ❌ no |
| `-name \.iso` | `.iso` | **solo** un archivo llamado exactamente `.iso` | ❌ no |

**Demostración real** (creé 10 archivos vacíos y corrí los dos patrones):

```
$ ls -1
basura.tmp  cancion.mp3  correos.pst  disco.iso  foto.gif  imagen.img
instalar.exe  peli.mpg  perfil.dbx  setup.msi  video.mp4

# patrón TAL COMO ESTÁ EN TUS SCRIPTS
$ find . -type f \( -name \*.gif -o -name \*.pst -o -name \.msi -o -name \.dbx \
                     -o -name \.tmp -o -name \.iso -o -name \.img -o -name \.exe \
                     -o -name \.mpg -o -name \*.mp3 \)
./correos.pst
./foto.gif
./cancion.mp3          ← 3 de 10.  Los otros 7 quedan intactos.

# MISMO PATRÓN CON EL * PUESTO
$ find . -type f \( -name '*.gif' -o -name '*.pst' -o -name '*.msi' -o -name '*.dbx' \
                     -o -name '*.tmp' -o -name '*.iso' -o -name '*.img' -o -name '*.exe' \
                     -o -name '*.mpg' -o -name '*.mp3' \)
./correos.pst  ./basura.tmp  ./peli.mpg  ./disco.iso  ./foto.gif  ./imagen.img
./perfil.dbx  ./cancion.mp3  ./setup.msi  ./instalar.exe   ← 10 de 10.
```

**Traducción:** hoy tus scripts **imprimen** «borrando archivos no deseados» y no borran `.msi .dbx .tmp .iso .img .exe .mpg`. Solo están borrando `gif`, `pst`, `mp3`, `wma`, `wmv`, `mp4`, `avi`, `mov` (+ `jpg/png` en `publico.sh`).

**Y aquí viene lo importante (A2):** no basta con agregar el `*`. Si lo haces, el script empezaría a borrar **`.iso` e `.img`** — que es exactamente lo que `ISO.sh` se esfuerza por respaldar, y probablemente imágenes de disco con valor. Por eso la corrección no es «falta un asterisco», sino: **la lista de extensiones a borrar tiene que decidirse perfil por perfil, con `*` y con intención.**

### 3.3 MEDIOS

| ID | Hallazgo |
|---|---|
| **M1** | `webcalipso.sh` → `quemar/RESINTRANET/` y `resintranet.sh` → `quemar/2026/RESINTRANET/`. Si `2026/` ya no existe, **ambos operan sobre la misma carpeta** y pueden correr en paralelo. |
| **M2** | `resmail.sh` vs `resmail2.sh`: mismo nombre de respaldo, rutas distintas y opuestas en limpieza (una limpia, la otra no). Imposible saber cuál es la vigente. |
| **M3** | `usuarios.sh` → `usuarios/` (minúscula); el directorio real es `USUARIOS/`. En Linux es **case-sensitive** → `cd` falla → véase C1. |
| **M4** | `ISO.sh` y `electron.sh` no limpian nada (correcto para ISO), pero tampoco lo documentan; `home.sh`, `netsuite.sh`, `privado.sh`, `webcalipso.sh` **no borran `files_trashbin`**. ¿Intencional? |
| **M5** | `-m5` (máxima compresión) sobre **todo** incluyendo `jpg/mp4/mp3/zip` que ya están comprimidos: CPU desperdiciada, ratios casi idénticos. Falta `-msjpg;mp4;mp3;zip;7z;rar`. |
| **M6** | **No se usan registros de recuperación (`-rr`)**, que justamente son lo que protege un soporte óptico con errores de quema/deterioro. |
| **M7** | Permisos sucios en el servidor: `RESMAIL` es `root:root 777`, `RESNETSUITE` es `777` con otro dueño. Cualquier proceso local puede borrar ahí. |
| **M8** | `find . -type d -name "files_trashbin" -exec rm -rf {} +` borra directorios **durante** la traversada de `find` → errores/esfuerzo desperdiciado. Mejor `find … -prune -exec rm -rf {} +`. |
| **M9** | La carpeta `salieronEE/` (¿"salieron EE"?) no aparece en el `ls` actual: probablemente archivada o movida. |

### 3.4 BAJOS — higiene

- Ningún script tiene `#!/bin/bash` + `set -u` + permisos consistentes (`dele.sh` no es ejecutable).
- `#echo $fdd` y `##find …` son restos muertos en los 26.
- Comentarios `echo` sin `set -x` ni destino: no queda registro de lo que se hizo.
- Sin `--dry-run` en ninguna parte.
- `dele.sh` es la única "orquestación" y está **enteramente comentada**.

---

## 4. Estructura de datos real vs. rutas de los scripts

### 4.1 Inventario confirmado en `servidor-produccion` — **disposición actual (9 carpetas)**

```bash
$ find /mnt/DATOS/quemar -maxdepth 1
/mnt/DATOS/quemar
/mnt/DATOS/quemar/RESINTRANET
/mnt/DATOS/quemar/USUARIOS
/mnt/DATOS/quemar/RESODOO
/mnt/DATOS/quemar/RESNETSUITE
/mnt/DATOS/quemar/RESNEXTCLOUD      ← NUEVO
/mnt/DATOS/quemar/RESCALIPSO
/mnt/DATOS/quemar/RESDOCKER
/mnt/DATOS/quemar/RESMAIL
/mnt/DATOS/quemar/RESNAS            ← NUEVO (hoy renombrada a RESHOME)

$ df -h /mnt/DATOS
Filesystem   Size  Used Avail Use% Mounted on
/dev/sdb      1,8T  1,1T  671G  62% /mnt/DATOS
```

**9 carpetas.** El usuario añadió `RESNEXTCLOUD` y `RESNAS` (=respaldos del NAS). **`quemar/RESNAS` se renombró a `quemar/RESHOME`** (lo que había era `home/`); el NAS completo se descompone en 5 perfiles (§4.8.1). Ya **no existe** `2026/`, `salieronEE/`, ni las carpetas personales (`BAK`, `CARATULAS`, `usuario-c`, `usuario-a`, `usuario-d`, `usuario-e`, `usuario-b`, `RESWEB`, `RESVM`, `usuarios`…).

→ **21 de los 26 scripts siguen apuntando a rutas inexistentes** (los que usaban `2026/…` o `quemar/RESWEB/…`). Solo tienen ruta viva los que apuntan a `quemar/{RESCALIPSO,RESODOO,USUARIOS,RESINTRANET}`.

- Disco: **671 GB libres** de 1,8 TB (62 % usado).
- Los **1,1 TB usados** incluyen `quemar/` más `calibre/libros/mas/roms` (§4.7) → el resto del volumen ronda los ~370 GB.
- `RESDOCKER` sigue **sin script** (A6). `USUARIOS` en mayúsculas → `usuarios.sh` falla (M3).
- **El número de perfiles crecerá** al descomponer el NAS (§4.8.1) y al separar `RESNEXTCLOUD`.

### 4.1b Estructura `ls -l` (información auxiliar)

```
drwxrwxr-x usuario usuario    4096 may 29 14:40 RESCALIPSO     link=2  → 0 subdirs
drwxrwxr-x usuario usuario    4096 oct  6 11:36 RESDOCKER      link=2  → 0 subdirs   ← HOY
drwxrwxr-x usuario usuario   49152 sep 16 13:58 RESINTRANET    link=2  → 0 subdirs
drwxrwxrwx root         root            4096 may 27 11:47 RESMAIL        link=14 → 12 subdirs
drwxrwxrwx usuario usuario    4096 nov  1  2025 RESNETSUITE    link=23 → 21 subdirs
drwxrwxr-x usuario usuario   12288 oct  6 11:36 RESODOO        link=2  → 0 subdirs   ← HOY
drwxrwxr-x usuario usuario    4096 ago 19 08:14 USUARIOS       link=8  → 6 subdirs
```

> **Nota de análisis:** `nlink - 2` = número de subdirectorios. En **RESCALIPSO, RESDOCKER, RESINTRANET y RESODOO hay 0 subdirectorios** → el bucle `for folder in */` **no itera nada** y la fase R no hace efecto. Ahí hay dos posibilidades: (a) ya quedaron comprimidos y ahora son `.partN.rar` sueltos a nivel raíz, o (b) son archivos sueltos que **el modelo actual jamás va a comprimir** (véase C3).

### 4.2 Discrepancias detectadas

| Ruta en los scripts | ¿Existe en el servidor? | Problema |
|---|---|---|
| `quemar/2026/RESNETSUITE/` | No (está `quemar/RESNETSUITE/`) | A5 / C6 |
| `quemar/2026/RESMAIL/` | No (está `quemar/RESMAIL/`) | A5 / C6 |
| `quemar/2026/RESINTRANET/` | No (está `quemar/RESINTRANET/`) | A5 / M1 |
| `quemar/2026/RESODOO/` | No (está `quemar/RESODOO/`) | A5 / C6 |
| `quemar/2026/RESNC/` | Sin equivalente visible | A5 |
| `quemar/2026/RESNAS/{home,ISO,PRIVADO,publico,electron}/` | **Consolidado en `quemar/RESNAS/`** (ya sin `2026/`) | A5 (falta `/2026/` en scripts) |
| `quemar/2026/RESNC/` | **Consolidado en `quemar/RESNEXTCLOUD/`** | A5 |
| `quemar/usuarios/` | Existe como `USUARIOS/` | **M3** (case) |
| `quemar/salieronEE/…` | No visible | M9 |
| `quemar/{RESWEB,RESVM,BAK,CARATULAS,usuario-c,usuario-a,usuario-d,usuario-e,usuario-b}/` | **Dentro de `RESNAS/` / `RESNEXTCLOUD/`** | A5 / C6 |
| **`quemar/RESDOCKER/`** | **Sí — y sin script** | **A6** |
| **`quemar/RESNEXTCLOUD/`** | **Sí — recupera ruta válida para `resnextcloud.sh`** | (bueno) |

### 4.3 Desglose por carpeta — **P1b ✅ (foto de 9 carpetas, 2026-10-06)**

| Carpeta | subdirs | archivos en **raíz** | total archivos | tamaño |
|---|---:|---:|---:|---:|
| RESCALIPSO | 0 | **28** | 28 | 56 G |
| RESDOCKER | 0 | **13** | 13 | 256 K |
| RESINTRANET | 0 | **1 007** | 1 007 | **329 G** |
| RESMAIL | 16 | 0 | **933 957** | 295 G |
| RESNAS | 39 | 0 | 1 654 | 871 M |
| RESNETSUITE | 21 | 0 | 132 981 | 3,9 G |
| RESNEXTCLOUD | 2 | 0 | 1 353 | 1,4 G |
| RESODOO | 0 | **202** | 202 | 22 G |
| USUARIOS | 2 | 0 | 713 | 16 G |
| **Total** | **80** | **1 250** | **1 071 908** | **≈ 724,2 G** |

**Qué confirma esto:**

- **C3 sigue igual:** 4 carpetas con **0 subdirectorios** → `for folder in */` **no itera**. Son **407 GB** (RESCALIPSO + RESDOCKER + RESINTRANET + RESODOO) y **1 250 archivos sueltos en raíz** que la fase R actual **jamás comprime**. **RESINTRANET sola = 329 GB**, el agujero más grande.
- **RESMAIL = 87 % de los archivos** (933 957 de 1 071 908) en 16 directorios; el cuello de botella ahí son **inodos**, no GB.
- **RESNETSUITE**: 132 981 archivos en solo 3,9 GB → fichas diminutas; pesa el nº de archivos.
- **RESNAS**: 39 carpetas de usuario (usuario-f…thidalgo) pero apenas **871 M / 1 654 archivos** → son homes viejos chicos. **PERMISOS `777` en todas.**
- **RESNEXTCLOUD**: solo **2 usuarios** (`persona1@ejemplo.com`, `persona2@ejemplo.com`), 1,4 G.
- **USUARIOS se redujo** (antes 6 subdirs / 11 998 archivos / 23 G → ahora 2 / 713 / 16 G): el usuario sacó datos de ahí. Posible solape con RESNAS/RESNEXTCLOUD → ver §4.3.1.

> **Ningún `.partN.rar` producido por los scripts** (los `.rar` que hay son de usuarios), igual que en la medición anterior.

### 4.3.1 ⚠️ Desorden detectado: datos de usuario en TRES árboles

Hay carpetas de la misma gente repartidas en tres raíces distintas, con **nombres distintos**, lo que **arriesga quemar tres veces al mismo usuario** (y dispara `fdupes`):

| Raíz | Cómo nombra al usuario | Ejemplos |
|---|---|---|
| `USUARIOS/` | nombre suelto (minúscula) | (2 subdirs, a confirmar) |
| `RESNAS/` | nombre suelto (minúscula) | `usuario-f`, `usuario-a`, `usuario-g`, `usuario-c`… (39) |
| `RESNEXTCLOUD/` | **correo** | `persona1@ejemplo.com`, `persona2@ejemplo.com` (2) |

**Coincidencias visibles:** `usuario-g`, `usuario-h` aparecen **en RESNAS y en RESNEXTCLOUD**. `usuario-a`, `usuario-c` también estaban antes como carpetas sueltas.

> **Ojo:** que un usuario aparezca en dos árboles **no es necesariamente duplicado** — puede ser su *home viejo* (RESNAS) vs su *Nextcloud* (RESNEXTCLOUD), que es exactamente lo que el usuario quiere distinguir (§7.8). Solo `fdupes` decide si el **contenido** se repite. Lo que sí es un riesgo real es **perder la ruta** al empaquetar.

Comando para cuantificar solape (solo lectura):

```bash
Q=/mnt/DATOS/quemar
echo "=== usuarios en cada árbol ==="
for r in USUARIOS RESNAS RESNEXTCLOUD; do
  echo "--- $r"; ls -1 "$Q/$r" | sed 's/@.*//' | sort -u
done
echo "=== cuánto pesa cada uno en RESNAS (top) ==="
du -sh "$Q"/RESNAS/*/ 2>/dev/null | sort -rh | head -15
echo "=== duplicados globales entre los 3 árboles (solo cuenta) ==="
fdupes -r "$Q/USUARIOS" "$Q/RESNAS" "$Q/RESNEXTCLOUD" 2>/dev/null | wc -l
```

### 4.3.2 Naturaleza de cada perfil (confirmado por el usuario)

| Perfil | Qué es | Contenido real | ¿Comprimir? |
|---|---|---|---|
| **RESCALIPSO** | ERP **Calipso** (PostgreSQL) | `.backup` (pg_dump **ya comprimido**) + `.log` + `.zip`. **55,3 GB** | **No comprime, solo trocea** (`comprimir:false` → `-m0`) |
| **RESODOO** | ERP **Odoo** | 68 `.log` + 68 `.backup` + 66 `.zip`. Set 2024-12 → **2026-06** | **No** |
| **RESNETSUITE** | **Mirror de NetSuite** (viene del Servidor 14) | **72 160 xml** + **56 108 pdf** + txt/docx/xlsx/png. Set 2025-10 → **2026-06** | **Sí** `-m5 -ms pdf,png,docx,xlsx…` |
| **RESDOCKER** | Configs/instancias **Docker** | **13 `.json`** (256 K). Set 2026-09 | Trivial |
| **RESINTRANET** | Respaldos de **sistemas** (fuentes + varias bases de datos) | **551 `.zip` + 454 `.tar` + 2 `.old`** → **ya comprimido**. Set 2019 → **2026-06** | **No** |
| **USUARIOS / RESNAS / RESNEXTCLOUD / RESMAIL** | Datos **por usuario** | — | Según tipo |

**Lo que más se actualiza en RESNETSUITE** (según el usuario): las carpetas **`RIDES`**, **`XML Firmado`** y **`cmc`** — ahí está la facturación electrónica que cambia a diario. Son el foco del respaldo incremental.

### 4.4 Extensiones — define el ratio de compresión

| Ext. | nº archivos | Comportamiento |
|---|---:|---|
| `.eml` | **933 942** | texto + adjuntos base64 → RAR `-m5` rinde ~1,6–2,2× |
| `.xml` | 72 190 | comprime muy bien, 5–10× |
| `.pdf` | 57 823 | ya comprimido → ~1× |
| `.txt` | 3 481 | 3–5× |
| `.zip` / `.tar` | 657 / 454 | `.zip` ~1×; `.tar` 2–4× |
| `.xlsx` `.docx` `.xls` `.doc` | 429+387+133+46 | OOXML/OLE son zip internos → ~1× |
| `.jpg` `.png` `.jpeg` | 365+207+37 | **sin compresión útil** → `-ms…` |
| resto (`.js .descarga .enc .log .backup .csv .html .svg .whiteboard .json .jsp .md`) | ~1 000 | mixto |

**Perfil dominante:** texto/e-mail → `-m5`. **Segundo:** PDFs ya comprimidos → `-m3` + `-ms`. **Fotos:** `-ms` obligatorio.

**Ratio global estimado: 0,55–0,80×** → la salida de 724,9 GB pesará aproximadamente **400–570 GB**.

### 4.5 Espacio — la estrategia de secuencia (corregido)

> ⚠️ **Corrección:** la versión anterior de esta sección decía «no cabe». **Era un error de cálculo**: sumaba origen + salida como si el origen hubiera que *escribirlo*. El origen **ya está en el disco** (forma parte de los 1,1 T usados). Lo que hay que *escribir* es solo la salida.

**Estado real del volumen (unidades `df`, GiB):**

| Concepto | GiB |
|---|---:|
| Total del volumen | 1 834 |
| Usado (incluye los 724,9 de `quemar/`) | 1 137 |
| **Libre** | **671** |
| Otro contenido (usado − `quemar/`) | ~412 |

**¿Cabe hacerlo de una sola pasada (sin borrar hasta el final)?**

| Escenario | Salida estimada | ¿≤ 671 GiB? |
|---|---:|---|
| Ratio 0,55× | 399 GiB | ✅ sí (margen 272) |
| Ratio 0,70× | 507 GiB | ✅ sí (margen 164) |
| Ratio 0,80× | 580 GiB | ✅ sí (margen 91) |
| **Ratio 1,00×** (todo incompresible: PDF, JPG, ZIP…) | **725 GiB** | ❌ **no** |

→ En el caso esperado **cabe de una pasada**, pero con poco margen. Y en el peor caso **no cabe**.

#### La solución: comprimir en orden ascendente, liberando cada paso

Esta es la secuencia que ya venías usando, y es **demostrablemente óptima**:

```
ordenar los trabajos por SALIDA estimada, de MENOR a MAYOR
para cada trabajo:
    si libre < salida_estimada × margen → SALTAR y avisar (no empezar)
    comprimir → rar t → borrar el origen de ESE trabajo
    (el espacio liberado se acumula)
```

**Por qué es óptimo:** cada trabajo libera `origen − salida > 0`. La restricción es «tener `salida` libre *antes* de borrar la fuente». Si existe un orden que completa todo, el ascendente también lo hace (intercambiar dos trabajos no puede empeorar la viabilidad). Es la clásica ordenación *coste−reembolso*.

**Simulación con tus datos reales (ratio 0,70×, libre inicial 671 GiB):**

| # | Carpeta | Origen | Salida est. | Libre al empezar | ¿entra? |
|---:|---|---:|---:|---:|:--:|
| 1 | RESDOCKER | ~0 | ~0 | 671,0 | ✅ |
| 2 | RESNETSUITE | 3,9 | 2,7 | 671,0 | ✅ |
| 3 | RESODOO | 22 | 15,4 | 672,2 | ✅ |
| 4 | USUARIOS | 23 | 16,1 | 678,8 | ✅ |
| 5 | RESCALIPSO | 56 | 39,2 | 685,7 | ✅ |
| 6 | RESMAIL | 291 | 203,7 | 702,5 | ✅ |
| 7 | RESINTRANET | 329 | 230,3 | 789,8 | ✅ |

- **Pico requerido:** 230,3 GiB (RESINTRANET) con **789,8 GiB libres** → margen **3,4×**.
- El libre **crece en cada paso** (671 → 888 GiB).
- **Incluso en el peor caso (ratio = 1×, nada comprime), siempre entra:** el mayor trabajo son 329 GiB ≤ 671 libres, y el libre nunca baja porque cada trabajo libera lo que ocupa.

**Regla de oro que se deriva:**

> **El único límite duro es que *ningún trabajo individual* supere el espacio libre.** Con orden ascendente el resto se resuelve solo.

**Requisito de seguridad (tu punto):** antes de comprimir cada trabajo, estimar la salida y comparar con el libre + margen. **Si no entra, NO se comprime** — se marca el trabajo como *saltado*, se avisa y se sigue con el siguiente. Comprimir a medias llena el disco, deja volúmenes parciales (**A8**) y es peor que no hacerlo.

→ **B8b** (§9) recoge esto. La secuencia recomendada se muestra en el menú (§7.2).

---

### 4.6 Máquinas del proyecto y herramientas disponibles

Hasta ahora se hablaba de «el servidor». En realidad intervienen **tres** máquinas:

| Máquina | Usuario | Rol |
|---|---|---|
| **`equipo-local`** (esta) | `cmc` | **Desarrollo y pruebas** del sistema (nada de datos reales) |
| **`servidor-produccion` = «servidor 45»** | `usuario` | **Producción**: datos `/mnt/DATOS` + **grabadora** · IP **10.0.0.45** · Ubuntu 24.04.5 |
| **`servidor-respaldos`** | `usuario` | Tiene **`msmtp` ya configurado** (Gmail) → referencia de notificaciones |

> ✅ **Confirmado 2026-10-06:** `servidor-produccion` **es** el «servidor 45» (misma máquina, IP `10.0.0.45`). No hay que «copiar a la 45»: **el sistema se instala donde ya están los datos y la grabadora.**

### 4.6.1 Herramientas — estado 2026-10-06

| Herramienta | `equipo-local` (dev) | `servidor-produccion` = 45 (prod) | Para qué |
|---|:---:|:---:|---|
| `bash` | **5.2.21** | **5.2.21** | `set -euo pipefail`, arrays asociativos |
| `rar` | ❌ NO | ✅ **RAR 6.02 (trial)** | Empaquetado con volúmenes |
| `unrar` | ❌ NO | ✅ | Verificación (`rar t`) |
| `fdupes` | ❌ NO | ✅ | Deduplicación |
| `jdupes` | ❌ NO | ❌ NO | Alternativa a `fdupes` |
| `xorriso` | ✅ | ✅ **1.5.6** | Crear ISO / consultar capacidad |
| `dvd+rw-mediainfo` | ✅ | ✅ | Capacidad real del disco |
| `cdrecord` | ✅ | ✅ **pero es `wodim`** → no acepta `-media-info` | Grabación |
| `cdrskin` | ❌ | ✅ | Comandos MMC alternativos |
| `growisofs` | ✅ | ✅ | Grabación (alternativa) |
| `genisoimage` / `mkisofs` | ✅ | ✅ | Armar ISO |
| `msmtp` | ❌ | ❌ (**solo en `servidor-respaldos`**) | Correo |
| `jq` | ✅ | ✅ | **Parsear `perfiles.json`** |
| `python3` | ✅ | ✅ | Cálculos / verificación |
| `tmux` | ❌ | ✅ | Segundo plano |
| `flock` | ✅ | ✅ | Evitar solapamientos |
| `7z` / `7za` | ❌ | ✅ | Alternativa a RAR |
| `rsync` | — | ✅ | Copias / staging |

> ⚠️ **`rar` es versión *trial*.** Funciona y no caduca, pero muestra un aviso. Si el proyecto va a producción seria, valorar licencia.
> ⚠️ **`cdrecord` en `servidor-produccion` es en realidad `wodim`** (cdrkit) y **no acepta `-media-info`**. Para consultas MMC usar `cdrskin`; para grabar, `growisofs` o `xorriso`.

### 4.6.2 Qué se puede y qué no se puede probar en `equipo-local`

- **Sí se puede probar aquí:** lógica de menú, lectura de `perfiles.json` (`jq`), aritmética de empaque de discos, `--dry-run`, **generación de ISO** (`xorriso`/`genisoimage`), guardas de espacio, reanudación `flock`, y el armado del correo con un `msmtp` simulado.
- **No se puede probar de verdad (sin instalar):** `rar`, `fdupes`, `msmtp`, `tmux`.
  → Opciones: **(A)** instalar `rar` (AUR), `fdupes`, `msmtp`, `tmux` en dev; **(B)** *stubs* (falsos) en `pruebas/` que simulan el comportamiento para los tests; **(C)** probar esas fases directamente en `servidor-produccion` con datos reales.
- **No hay `/mnt/DATOS` aquí** → las pruebas usan datos sintéticos en `/tmp/opencode/...` y **nunca** tocan nada real.

> **Regla:** en `equipo-local` **nunca** se toca `/mnt/DATOS/quemar` ni la grabadora. Todo ensayo va sobre datos sintéticos en `/tmp`.

### 4.6.3 Plan de trabajo por etapas

1. **Documentar** (ahora) — cerrar el MD.
2. **Construir** el entregable en `sistema/`, con su estructura (`backup.sh`, `lib/`, `perfiles.json`, `notificaciones/`, `pruebas/`).
3. **Probar en `equipo-local`** con datos falsos, sin tocar nada real.
4. **Desplegar** a `servidor-produccion` (= servidor 45), donde ya están los datos y la grabadora, y ponerlo a trabajar.
5. **Alternativa:** si acaso, empaquetar todo en un `.tar.gz` con los ajustes finales para copiarlo de una vez.

---

### 4.7 Carpetas extra en `/mnt/DATOS` (fuera de `quemar/`)

El sondeo del 2026-10-06 reveló que `/mnt/DATOS` **no solo** contiene `quemar/`:

| Carpeta | Qué parece ser | ¿Al respaldo? |
|---|---|---|
| `calibre` | Biblioteca de Calibre | **por decidir** |
| `libros` | Libros / documentación | **por decidir** |
| `mas` | (contenido vario) | **por decidir** |
| `roms` | ROMs / emuladores | **por decidir** |
| `.Trash-1000` | **Papelera** de `/mnt/DATOS` | candidata a **vaciar**, no a respaldar |

→ **Nueva pregunta abierta:** ¿estas carpetas entran al respaldo/quemado o se quedan fuera? Hoy el alcance definido es solo `quemar/` (los 9 perfiles).

### 4.8 El Servidor 14 — **`servidor-respaldos`** (origen)

El «Servidor 14» es la máquina **`servidor-respaldos`** (Linux/Ubuntu como esta), accesible por **SSH**.

| Dato | Valor |
|---|---|
| Host | **`10.0.0.14`** (el nombre `servidor-respaldos` **no resuelve** desde `servidor-produccion`) |
| Acceso | **SSH** (`usuario@10.0.0.14`) |
| SO | Linux (Ubuntu) |
| Ruta origen | **`/mnt/bak/`** → pesa **≈ 6 TB** |
| Qué se le pide | copiar **tandas** hacia `servidor-produccion` para quemar |

> ⚠️ `servidor-respaldos` no resuelve por nombre → usar la **IP `10.0.0.14`**, o añadir `10.0.0.14 servidor-respaldos` a `/etc/hosts`.

**Contenido real de `/mnt/bak` (2026-10-06):**

| Carpeta S14 | Qué es | Va a `quemar/` |
|---|---|---|
| `RESCALIPSO/` | ERP Calipso | **RESCALIPSO** ✅ |
| `RESDOCKER/` | Docker | **RESDOCKER** ✅ |
| `RESINTRANET/` | intranet | **RESINTRANET** ✅ |
| `RESMAIL/` | correos | **RESMAIL** ✅ |
| `RESNETSUITE/` | mirror NetSuite | **RESNETSUITE** ✅ |
| `RESODOO/` | ERP Odoo | **RESODOO** ✅ |
| `RESNAS/` | **storage NAS**, gigantesco → **se descompone** en `home/` (54 usuarios), `publico/`, `PRIVADO/`, `electron/`, `ISO/` (§4.8.1) | **RESHOME / RESPUBLICO / RESPRIVADO / RESELECTRON / RESISO** ✅ |
| `RESNC/` | **data de Nextcloud** (usuarios `@usuario.com`, `__groupfolders`, `appdata_*`, `files_external`, `nextcloud.log`) = **el mismo `RESNEXTCLOUD`**, renombrado al migrar de servidor | **RESNEXTCLOUD** ✅ |
| `RESNEXTCLOUD/` | **vacío** — nombre viejo; el contenido real está en `RESNC` | — |
| `INSTALADORES/` | instaladores (`exe/msi/par`) → **se quema tal cual** (`empaquetar:false`, no se toca nada) | ✅ |
| `QUEMAR/` | **bandeja del S14**: `Docker/`, `Odoo/`, `RESMAIL/` (ya apartado para quemar, 2025-10-06) | acción **B** (§7.10) |
| `ACTIVOS/`, `ARCHIVO/` | **vacíos** (creados 2025-09-07) | futuras tandas |
| `RESVM/`, `RESWEB/` | VMs / web antiguos | futuras tandas |
| `lost+found/` | fs | ignorar |

**Origen por perfil (resuelto):**

| Perfil en `quemar/` | Origen en `/mnt/bak/` |
|---|---|
| RESCALIPSO | `RESCALIPSO/` ✅ |
| RESDOCKER | `RESDOCKER/` ✅ |
| RESINTRANET | `RESINTRANET/` ✅ |
| RESMAIL | `RESMAIL/` ✅ |
| RESNETSUITE | `RESNETSUITE/` (ojo `RIDES`, `XML Firmado`, `cmc`) ✅ |
| RESODOO | `RESODOO/` ✅ |
| RESNEXTCLOUD | `RESNC/` (= `RESNEXTCLOUD`, usuarios `@usuario.com`) ✅ |
| RESHOME | `RESNAS/home/` ✅ |
| RESPUBLICO | `RESNAS/publico/` ✅ |
| RESPRIVADO | `RESNAS/PRIVADO/` ✅ |
| RESELECTRON | `RESNAS/electron/` ✅ |
| RESISO | `RESNAS/ISO/` ✅ |
| USUARIOS *(→ RESOTROS)* | **manual** — Google Takeout + PCs de bajas |

### 4.8.1 Descomposición del NAS (`RESNAS` → 5 perfiles)

`RESNAS` es **gigantesco** y con partes de **importancia y frecuencia distintas**, así que conviene **separarlo en 5 perfiles** (recomendación: **sí vale la pena** — cada uno se respalda/quema/restaura por su cuenta, y añadir perfiles al `perfiles.json` es barato):

| Perfil | Origen | Contenido |
|---|---|---|
| **RESHOME** | `RESNAS/home/` | homes de usuario (54) → funciona el bucle por usuario |
| **RESPUBLICO** | `RESNAS/publico/` | carpeta pública |
| **RESPRIVADO** | `RESNAS/PRIVADO/` | carpeta privada |
| **RESELECTRON** | `RESNAS/electron/` | documentos de **facturación electrónica** |
| **RESISO** | `RESNAS/ISO/` | documentos **ISO 9000** (no imágenes de disco) |

> Estado real: `quemar/RESNAS` se **renombró a `quemar/RESHOME`** (lo que ya estaba ahí era `home/`). Los otros 4 se crearán según se vayan respaldando.

### 4.8.2 Perfiles por usuario fuera del NAS

| Perfil actual | Qué es | Nombre propuesto |
|---|---|---|
| **RESNEXTCLOUD** | data de Nextcloud por usuario (`@usuario.com`) | mantener `RESNEXTCLOUD` (unificar con `RESNC`) |
| **RESNEXTCLOUD** | data de Nextcloud por usuario (`@usuario.com`) | mantener `RESNEXTCLOUD` |
| **RESOTROS** | **bajas**: Google Takeout + PC de personas que salieron, por persona | **`RESOTROS`** (decidido) |

> `USUARIOS` = respaldos de personas que **salieron de la empresa** (Takeout de su cuenta + su PC), guardados por persona → **renombrado a `RESOTROS`**. La lógica del nombre original venía de `quemar/salieronEE/` (**M9**).

**Además, hay una bandeja de quema en el propio S14** (`/mnt/bak/QUEMAR/` con `Docker`, `Odoo`, `RESMAIL`): son las "carpetas obsoletas del 14 que deben quemarse" (acción B, §7.10).

**Clave de alcance:** `/mnt/bak` pesa **~6 TB** — **no se respalda entero ni de lejos.** El respaldo se hace **por tandas**: hoy correos, en un mes otra cosa, según decida el usuario. El sistema **no inventa** qué copiar: pregunta, copia el set elegido y lo deja listo para quemar (§7.10).

**Jerarquía de copias (según el usuario):**

| Copia | Dónde |
|---|---|
| **1.ª** | `/mnt/bak` (Servidor 14) ← **origen que se copia** |
| **2.ª** | `/mnt/mirror` (Servidor 14) |
| **3.ª** | Nube |
| **4.ª** | **Estos Blu-ray** ← el objetivo de este proyecto |

Estos discos son una **red de seguridad extra (4.ª copia)**, no la copia principal.

## 5. El factor «700 MB» — análisis técnico

### 5.1 Cómo interpreta RAR el sufijo

De la documentación oficial (`rar.txt`, `-v<size>[k|b|f|m|M|g|G]`):

| Sufijo | Significado | Factor |
|---|---|---|
| *(ninguno)* | miles de bytes | ×1000 |
| `k` | kilobytes | ×1024 |
| `b` | bytes | ×1 |
| `m` | megabytes (binario) | ×1024×1024 |
| **`M`** | **millones de bytes (decimal)** | **×1 000 000** |
| `g` | gigabytes (binario) | ×1024³ |
| `G` | billones de bytes (decimal) | ×1 000 000 000 |

**Tus scripts usan `-v694M` → 694 000 000 bytes exactos.** ✅ El *orden de magnitud* es correcto.

- Capacidad de un CD-R 700 MB = **700 000 000 bytes**.
- Margen con `694` = 6 000 000 bytes = **0,86 %** — por debajo del 2 % que necesita el grabador.
- Si se hubiera escrito `-v694m` (minúscula) serían 727 711 744 B → **no cabría en el CD**.

> **Valor final adoptado: `-v98M`** para los tres soportes (§5.4). El `694` funcionaba «de casualidad» en CD, pero no servía ni para DVD ni para BD. La regla que lo unifica todo es `V = (100 − p) MB`.
>
> El problema real no es el número, es que estaba **cristalizado en 26 archivos con 4 valores distintos y sin documentar**.

### 5.2 Capacidad real — **MEDIDA en tu grabadora** (2026-10-06)

**Grabadora:** HL-DT-ST **BD-RE WH16NS40** (firmware 1.00) · **Disco de prueba:** BD-R SRM **CMC Magnetics** (`CMCMAG/BA5`), 12x.

| Medida | Sectores | Bytes | GiB |
|---|---:|---:|---:|
| Total del disco (*unformatted*) | 12 219 392 | **25 025 314 816** | 23,28 |
| Capacidad *formateada* `00h(3000)` | 11 826 176 | **24 220 008 448** | 22,56 |
| Lo que `xorriso` reporta libre | 12 219 392 | **25 025 314 816** | 23,3 |

- `READ BD SPARE INFORMATION failed` → **esta unidad/disco NO reporta zona de repuesto** (el BD-R SRM puro no la tiene). Confirmado: si llenas al 100 %, no hay margen para un sector malo → **falla al final**.
- Con `-v98M` sobre la capacidad **llena** → **250 piezas**, aire **525 MB = 2,10 %**.
- Con la capacidad **formateada (24,22 GB)** → **242 piezas** y dejas **1,31 GB = 5,23 %** libre.

> **Recomendación (por tu historial de fallos al final + medio barato):** arrancar con el número conservador **`24 220 008 448` → 242 piezas (~5 % libre)** y **grabar a 4x–6x, no a 12x**. Si sale bien, subir a 250. El número de capacidad es un dato de configuración (`perfiles.json`), no toca el `-v98M`.

**Cómo se midió (una vez por tipo de disco):**

```bash
dvd+rw-mediainfo /dev/sr0            # READ FORMAT CAPACITIES: 00h(3000) y 'unformatted'
xorriso -outdev /dev/sr0 -tell_media_space   # 'Media space: Ns'  (N = sectores × 2048 B)
```

**Capacidades estándar de referencia** (por si no se miden):

| Soporte | Sectores | Bytes |
|---|---:|---:|
| BD-R SL | 12 219 392 | 25 025 314 816 |
| DVD-R SL | 2 298 496 | 4 707 319 808 |
| CD-R 80 min | 360 000 | 737 280 000 |

*Nota: el MD usaba antes `700 000 000` (CD) y `4 700 000 000` (DVD) «redondos»; los reales son los de esta tabla. Con `-v98M` el conteo no cambia: 250 / 47 / 7.*

**El espacio para la lista de archivos es un fantasma.** El cluster en BD es de 64 KB (2 KB en ISO9660); el directorio de 250 entradas ocupa unos cientos de KB. Lo único que pagas es el *padding* por archivo: `98 000 000` no es múltiplo de `65 536`, así que cada `.partN.rar` se redondea ~41 KB hacia arriba → 250 archivos ≈ 10 MB. Sigue siendo despreciable frente a los 500 MB de aire.

### 5.3 La matemática — la regla del aire

**Decisión fijada:** **un solo `-v` para BD, DVD y CD**, con **2 % de aire** (500 MB en un BD). Número: **`-v98M`**.

#### La regla (vale para cualquier `p`)

```
V = (100 − p) MB          p = % de aire que quieras dejar
```

Da **exactamente 250 / 47 / 7 piezas** en BD25 / DVD / CD, con **exactamente `p` % de aire** — para cualquier `p`.

**Por qué es exacto:** las capacidades son múltiplos limpios de 100 →

```
25 000 = 250 × 100     4 700 = 47 × 100     700 = 7 × 100
⇒ 250 × (100 − p) = 25 000 × (1 − p/100)   … y lo mismo para DVD y CD
```

| aire `p` | **`-v`** | BD25 | DVD | CD | uso del disco |
|---:|---|---:|---:|---:|---:|
| 1 % | 99M | 250 | 47 | 7 | 99 % |
| **2 %** | **98M** | **250** | **47** | **7** | **98 %** |
| 3 % | 97M | 250 | 47 | 7 | 97 % |
| 5 % | 95M | 250 | 47 | 7 | 95 % |
| 10 % | 90M | 250 | 47 | 7 | 90 % |

#### `-v98M` en detalle

| Soporte | Capacidad | Presupuesto `B = 98 %` | ÷ 98 000 000 | Usado | Aire |
|---|---:|---:|---:|---:|---:|
| **BD-R SL 25 GB** | 25 000 000 000 | 24 500 000 000 | **250 piezas** | 24 500 000 000 | 500 000 000 = **2,00 %** |
| **DVD-R 4,7 GB** | 4 700 000 000 | 4 606 000 000 | **47 piezas** | 4 606 000 000 | 94 000 000 = **2,00 %** |
| **CD-R 700 MB** | 700 000 000 | 686 000 000 | **7 piezas** | 686 000 000 | 14 000 000 = **2,00 %** |

> ⚠️ **`-v` por sí solo NO garantiza el aire.** Las últimas piezas de cada carpeta son más pequeñas que `V`, y el quemador rellena los huecos hasta dejarte en **0**. El 2 % **lo debe imponer el empaquetador** (**B8c**): al armar la lista de cada disco, parar en `capacidad × 0,98`. El `-v98M` hace que, en el caso ideal de piezas todas iguales, caigas en 2,00 % exacto.

#### Por qué 2 % y no 1 %

- El *filesystem* (ISO9660/Rock Ridge) apenas gasta **< 1 MB**. Ese no es el problema.
- El problema real es la **zona de repuesto (*spare area*) del BD-R**: si la grabadora encuentra un sector defectuoso durante la grabación, lo reasigna ahí. Con el disco lleno al 100 % **no hay a dónde reasignar y la grabación falla al final** — exactamente el «eructo con error» que quieres evitar. **2 % = 500 MB** de colchón lo cubre con holgura.
- También absorbe la variación real de capacidad entre marcas y firmwares (~24,2 a 25,0 GB).

Si quieres aún más colchón con el mismo número de piezas: **`-v97M`** (3 % = 750 MB en BD) o **`-v95M`** (5 % = 1,25 GB).

### 5.4 Veredicto — **`-v98M` para todo**

**Un solo número para BD, DVD y CD: `-v98M` (98 000 000 bytes).**

- **BD25** → 250 piezas · **DVD** → 47 · **CD** → 7. Exacto en los tres.
- Aire **2 %** en los tres = 500 MB / 94 MB / 14 MB.
- Número redondo, universal y con colchón de sobra para la estructura y el *spare area* del grabador.
- Si algún día quieres más margen **sin cambiar el número de piezas**: `-v97M` (3 %) o `-v95M` (5 %).
- BD-R DL (50 GB, si lo usaras) → automáticamente 500 piezas por disco, aire también 2 %.

**Medir la capacidad real de tus discos (una vez, con un disco virgen en `servidor-produccion`):**
```bash
xorriso -indev /dev/sr0 -tell_media_space   # ⚠️ NO existe -report_medium en xorriso 1.5.6
dvd+rw-mediainfo /dev/sr0                   # alternativa, más legible (dvd+rw-tools, ya instalado)
```

Si la capacidad real medida difiere de la nominal, la regla se recalcula sola: `V = capacidad × 0,98 ÷ N`.

### 5.5 Mejoras de compresión recomendadas (por perfil)

```bash
# Texto / SQL dumps / configs / .eml → máxima compresión + integridad
rar a -m5 -rr3% -v98M -idq

# Fotos / vídeo / ISO / zip → comprimir solo el contenedor, guardar el resto
rar a -m3 -msjpg;jpeg;png;mp4;mkv;mp3;zip;7z;rar;gz -rr3% -v98M

# ya comprimido de fábrica (pdf, zip, jpg) → store
rar a -m0 -v98M
```

- **`-rr3%` / `-rr5%`**: registro de recuperación. En soporte óptico esto es lo que te deja reconstruir un volumen con un error de quema o un deterioro puntual. **Recomendado en todos los perfiles**, coste ~3 % de espacio.
- **`-ms…`**: evita re-comprimir lo ya comprimido (M5 actual).
- **`-idq`**: salida silenciosa, logs legibles.

---

## 6. Estructura propuesta

### 6.1 En el servidor

```
/mnt/DATOS/
├── quemar/                        ← STAGING: solo lo que se va a quemar
│   ├── RESCALIPSO/
│   │   └── 2025-03-07/            ← sets con fecha (§7.9); aquí van los pg_dump
│   ├── RESDOCKER/
│   │   └── 2026-09-13/
│   ├── RESINTRANET/               ← 1 007 zip/tar sueltos (¿set fechado? — pendiente)
│   ├── RESMAIL/                   ← por usuario
│   ├── RESNAS/                    ← por usuario (39)
│   ├── RESNETSUITE/
│   │   └── 2026-06-03/            ← set actual; el próximo respaldo = carpeta nueva
│   ├── RESNEXTCLOUD/              ← por usuario (2)
│   ├── RESODOO/
│   │   └── 2026-06-01/
│   └── USUARIOS/                  ← por usuario
│
├── quemados/                      ← manifiesto de lo ya quemado
│   └── 2026-S1/
│       ├── MANIFIESTO.csv         ← fecha, perfil, soporte, nº volúmenes, SHA256, disco usado
│       └── listas/
│
└── _backup/                       ← el sistema (scripts, perfiles, estado, logs)
    ├── backup.sh                  ← MENÚ PRINCIPAL (único punto de entrada)
    ├── lib/
    │   ├── comunes.sh             ← log, lock, espacio, colores, errores
    │   ├── fases.sh               ← trash / dupes / basura / vacios / comprimir / verificar
    │   └── notify.sh              ← email / telegram
    ├── perfiles.json              ← configuración del sistema (global + por perfil) — ver §6.3
    ├── config.usuario.json        ← override local (rutas, correo); NO se versiona
    ├── state/
    │   ├── lock/                  ← un lock por perfil
    │   └── <perfil>.estado        ← pendiente / en_curso / listo / verificado / quemado
    ├── logs/
    │   └── <perfil>-<YYYYMMDD-HHMMSS>.log
    └── reportes/
```

**Reglas de la estructura:**

1. **Un solo nivel de carpetas** bajo `quemar/` — elimina el problema `2026/` vs raíz de una vez.
2. **Un solo nombre por perfil**, en mayúsculas, sin versiones (adiós `resmail`/`resmail2`; `USUARIOS` → **`RESOTROS`**).
3. `quemar/` es **solo staging**: nunca se borra nada de los orígenes.
4. `quemados/` guarda el manifiesto, no los datos (los datos ya están en los discos).
5. Los scripts dejan de copiarse a mano entre máquinas: viven en `_backup/`.

### 6.2 En `equipo-local` (esta máquina) — ✅ esqueleto creado

```
Documentos/Antigravity/OrganizarBackups/
├── DISENO.md                  ← este documento (diseño)
├── backup/                    ← LEGADO, solo lectura (26 scripts, no tocar)
├── backup.zip                 ← LEGADO, original
├── notificaciones/            ← ✅ creado (instalar-msmtp.sh, msmtprc.template, enviar-correo.sh)
└── sistema/                   ← ENTREGABLE: lo que se copia a servidor-produccion
    ├── backup.sh              ← ✅ menú + dispatcher
    ├── perfiles.json          ← ✅ 13 perfiles con origen real (§4.8)
    ├── lib/
    │   ├── comunes.sh         ← ✅ log, config (jq), rutas, tamaño, espacio
    │   ├── config.sh          ← ✅ editor de interruptores (menú «Configurar»)
    │   ├── fases.sh           ← ✅ preflight + limpieza + empaquetado + verificación
    │   ├── manifiesto.sh      ← ✅ MANIFIESTO.csv del ciclo (§7.1)
    │   ├── pull.sh            ← ✅ pull desde el Servidor 14 con rsync (§7.10)
    │   └── notify.sh          ← ✅ aviso HTML (listo/fallo/pull) → enviar-correo.sh
    ├── notificaciones → ../notificaciones
    ├── diagnostico/diagnostico-45.sh   ← ✅ creado
    ├── pruebas/
    │   ├── datos.sh           ← ✅ datos sintéticos en /tmp/respaldos-prueba/quemar
    │   └── stubs/fdupes       ← ✅ reimplementación mínima (equipo-local no tiene fdupes)
    ├── estado/                ← (runtime) ciclo vigente
    └── logs/                  ← (runtime) qué se borró, por perfil (C5)
```

**`RESPALDO_MODO=pruebas`** cambia la raíz a `global.raiz_pruebas` **y mete `pruebas/stubs/` en el PATH** → se prueba en `/tmp` sin tocar `/mnt/DATOS`. **Todo es dry-run por defecto**: nada se borra ni se empaqueta sin `--real`.

**Comandos:**

```bash
cd sistema
./pruebas/datos.sh                  # genera datos en /tmp

./backup.sh listar [pruebas]        # 13 perfiles, tamaño, origen, destino
./backup.sh origen RESHOME          # usuario@10.0.0.14:/mnt/bak/RESNAS/home
./backup.sh preflight all           # crudo vs salida estimada vs libre
./backup.sh ciclos                  # ciclo, raíz, libre, medio, volumen, manifiesto
./backup.sh pull RESHOME            # sólo imprime el rsync
./backup.sh pull all --real         # jala todo (sólo perfiles con origen)
./backup.sh manifiesto [PERFIL|all] # MANIFIESTO.csv del ciclo

./backup.sh limpiar    RESHOME --real
./backup.sh empaquetar RESHOME --real
./backup.sh verificar  RESHOME      # verifica aunque ya esté empaquetado
./backup.sh procesar   RESHOME --real   # pipeline completo
./backup.sh procesar   all --real
./backup.sh menu                     # menú interactivo (TTY)

./backup.sh configurar ver RESHOME   # tabla: valor perfil / global / efectivo / origen
./backup.sh configurar               # submenú de edición (guarda + .bak)
```

**Pipeline (`procesar`)** — verificado de punta a punta con 7z (y con `rar` en `servidor-produccion`):

1. **preflight** — `crudo × 0,9 × 1,05 ≤ libre`; si no, **se salta y avisa** (A8).
2. **limpieza** — papelera → versiones → duplicados (por usuario, §7.8) → basura → vacíos. Cada paso **lista primero** y deja el log en `logs/<PERFIL>-*.txt` (**C5**).
3. **empaquetado** — un juego por carpeta fechada (`por_usuario`: un juego por usuario + `_RAIZ` si hay archivos sueltos en la raíz, **C3**), volumen exacto de `98 000 000` B.
4. **verificación** — `rar t` / `7z t` sobre el primer volumen + `*.sha256` por juego.
5. **borrado de la fuente** — **solo si la verificación pasó**; si falla, no se borra nada.
6. **manifiesto + aviso** — cada set OK se registra en `quemados/<ciclo>/MANIFIESTO.csv` (con `sha256` del juego) y se manda el correo (§7.5). Re-verificar **no duplica** filas.

Perfiles con `comprimir:false` (RESCALIPSO/RESODOO/RESINTRANET, ya comprimidos) **se trocean en modo *store*** (`-m0`, sin recomprimir) en piezas de 98 MB para poder repartirlas en discos con k3b; se verifican y se borra la fuente igual que el resto (H.1).

**`MANIFIESTO.csv`** (una fila por juego, append con deduplicado):

```
ciclo,fecha,perfil,juego,volumenes,bytes,sha256,estado
2026-10-07,2026-10-07,RESHOME,RESHOME_2026-10-07_alvarez,1,276,cb93db5c…,OK
```

**Corrección de diseño:** el deduplicado corre por **unidad de usuario**, nunca entre usuarios — si no se rompería el principio «cada usuario conserva su carpeta» (§7.8).

### 6.3 `perfiles.json` — **cada carpeta con sus propios interruptores** (tu corrección)

**Un solo archivo JSON**, con cuatro bloques:

| Bloque | Qué contiene |
|---|---|
| `global` | **Sólo parámetros operativos**: raíces, medio, capacidad, volumen, aire, compresión, integridad, empaquetador, correo, orden, `dry_run`. |
| `plantilla` | Valores por defecto de los interruptores de carpeta; sirve para **completar** un perfil desde el menú (`Completar desde plantilla`), nunca se lee en runtime. |
| `servidor14` | host, usuario, raíz de origen (`/mnt/bak`). |
| `perfiles` | **Cada una de las 14 carpetas define TODOS sus interruptores**: `comprimir`, `carpeta_fecha`, `por_usuario`, los 8 `borrar_*`, `borrar`, `conservar`, `store`, `origen_s14`. |

> **Regla clave (decisión 2026-10-07):** los interruptores de política **no heredan de `global`** — no existen ahí. Si un perfil no lo define, `configurar validar` lo acusa y `limpiar`/`empaquetar`/`procesar` se niegan a correr. Esto evita que un «global» silencioso borre fotos o duplicados en una carpeta que no lo pedía.

```jsonc
{
  "global": {
    "raiz_datos": "/mnt/DATOS/quemar",
    "raiz_pruebas": "/tmp/respaldos-prueba/quemar",
    "medio": "BD25",
    "capacidad_bytes": 24220008448,   // conservador (§5.2)
    "volumen": "98M",                 // = 98 000 000 bytes exactos (§5.4)
    "aire_porcentaje": 2,             // V = (100 − p) MB
    "compresion": "m5",
    "integridad": "rr3%",
    "factor_salida": 0.9,
    "empaquetador": "",               // vacío = rar si existe, si no 7z
    "verificar_antes_de_borrar": true,
    "pull_excluir": [".trash", "files_trashbin", "lost+found", ".DS_Store", "Thumbs.db", "desktop.ini"],
    "dry_run": true,
    "orden": "ascendente",
    "correo": []
  },
  "plantilla": {                      // sólo para «Completar perfil»
    "comprimir": true, "carpeta_fecha": true, "por_usuario": false,
    "borrar_papelera": false, "borrar_versiones": false, "borrar_duplicados": false,
    "borrar_vacios": true, "borrar_fotos": false, "borrar_videos": true,
    "borrar_musica": true, "borrar_instaladores": false,
    "borrar": [".gif",".pst",".msi",".dbx",".tmp",".iso",".img",".exe"],
    "conservar": [], "store": ["jpg","jpeg","png", … , "pdf"]
  },
  "servidor14": { "host": "10.0.0.14", "usuario": "usuario", "raiz": "/mnt/bak" },
  "perfiles": {
    "RESCALIPSO": { "origen_s14": "RESCALIPSO", "comprimir": false, "carpeta_fecha": true,
      "por_usuario": false, "borrar_papelera": false, "borrar_versiones": false,
      "borrar_duplicados": false, "borrar_vacios": true, "borrar_fotos": false,
      "borrar_videos": true, "borrar_musica": true, "borrar_instaladores": false,
      "borrar": [".gif",".pst",".msi",".dbx",".tmp",".iso",".img",".exe"],
      "conservar": [], "store": [ … 16 … ] },
    "RESHOME":    { … "por_usuario": true, "borrar_papelera": true, "borrar_duplicados": true … },
    "RESNEXTCLOUD": { "origen_s14": "RESNC", "por_usuario": true, "borrar_papelera": true,
      "borrar_versiones": true, "borrar_duplicados": true, … },
    "RESPUBLICO": { … "borrar_fotos": true … },          // único con fotos=true (pendiente)
    "RESOTROS":   { "origen_s14": null, "fuente": "manual",
      "borrar_instaladores": true, "borrar_duplicados": true, … },
    "RESISO":     { … "nota": "NO archivos ISO: documentos y procesos ISO 9000" … },
    "INSTALADORES": { … "empaquetar": false, "carpeta_fecha": false,
      "borrar": [], "conservar": [], "nota": "se quema tal cual, no se toca nada" … },
    … 13 carpetas en total, todas con el mismo juego de claves …
  }
}
```

**Interruptores — dos ámbitos (columna `ÁMBITO` en `configurar ver`):**

| Ámbito `carpeta` (obligatorio, sin herencia) | Qué hace |
|---|---|
| `comprimir` | genera volumen; `false` = **solo trocear** en store (`-m0`), sin recomprimir (RESCALIPSO/RESODOO/RESINTRANET) |
| `carpeta_fecha` | envuelve en subcarpeta `AAAA-MM-DD` (unidad de restauración) |
| `por_usuario` | un juego por usuario; nunca mezclar usuarios (RESHOME, RESNEXTCLOUD) |
| `borrar_papelera` | `files_trashbin`, `.trash` → **true en RESHOME y RESNEXTCLOUD** |
| `borrar_versiones` | `files_versions` → **true sólo en RESNEXTCLOUD** |
| `borrar_duplicados` | `fdupes` (siempre dentro del mismo usuario) → **true en RESHOME, RESNEXTCLOUD, RESOTROS** |
| `borrar_vacios` | carpetas y archivos vacíos (true en las 14) |
| `borrar_videos` | `.mp4 .avi .mov .mkv .wmv .mpg .flv .webm …` |
| `borrar_musica` | `.mp3 .wma .wav .flac .aac .ogg .m4a …` |
| `borrar_fotos` | `.jpg .jpeg .png .heic .webp` → **sólo `RESPUBLICO`** (pendiente de confirmar) |
| `borrar_instaladores` | `.iso/.msi/.exe/.img` → **true sólo en RESOTROS** |
| `borrar` | lista de extensiones basura (difiere por perfil) |
| `conservar` | nunca se borra aunque esté en `borrar` |
| `empaquetar` | `true` crea conjuntos; `false` = **quemar tal cual** (no crea archivos, no borra) — `INSTALADORES` |
| `trocear_grandes` | `true` parte en piezas de 98 MB lo que supere el volumen; `false` = el archivo grande va entero |
| `store` | `-ms` por extensión (`RESNETSUITE`: pdf,png,jpg,docx,xlsx) |
| `origen_s14` | ruta relativa a `/mnt/bak` (vacío/`null` = manual) |

| Ámbito `operativo` (puede faltar, hereda de `global`) | Valor global |
|---|---|
| `compresion` / `integridad` | `m5` / `rr3%` |
| `volumen` / `aire_porcentaje` / `medio` | `98M` / `2` / `BD25` |
| `correo` | `[]` (sin destinatarios → aviso en consola) |

> **Reglas de negocio (sin cambio):** `conservar` **gana** sobre `borrar` (`! -iname` por cada elemento) y **nada se borra sin listar antes** (**C5**) — los listados van a `logs/<PERFIL>-basura.txt` etc. `verificar_antes_de_borrar` (operativo) obliga a `verificar` con éxito antes de borrar la fuente.

**Guardas implementadas:** `bool_config`/`lista_config` sólo leen `.perfiles[<p>][<k>]` para claves `carpeta`; `configurar` se niega a editar una clave de carpeta en `global` y a **quitarla** de un perfil; `procesar`/`limpiar`/`empaquetar` abortan si falta alguna (`validar_config`).

---

## 7. Diseño del sistema

### 7.1 Diagrama de fases

```
 ┌─ 0. PREFLIGHT ───────────────────────────────────────────┐
 │ detecta carpetas  →  calcula tamaño  →  estima salida    │
 │ verifica libre en /mnt/DATOS  →  verifica herramientas   │
 │ ¿alcanza?  NO ─→ avisa y aborta.  SÍ ─→ continúa        │
 └──────────────────────────────────────────────────────────┘
 ┌─ 1. LIMPIEZA (dry-run primero, luego real) ──────────────┐
 │ trashbin → fdupes (lista, luego borra) → basura del      │
 │ perfil → vacíos                                          │
 └──────────────────────────────────────────────────────────┘
 ┌─ 2. EMPAQUETADO ─────────────────────────────────────────┐
 │ rar/7z con volumen = soporte − 2%, -rr, -ms, por perfil  │
 │ y con archivos sueltos de la raíz incluidos (C3)         │
 └──────────────────────────────────────────────────────────┘
 ┌─ 3. VERIFICACIÓN ────────────────────────────────────────┐
 │ rar t sobre cada juego de volúmenes + SHA256 del set     │
 │ SOLO AHORA se habilita el borrado de la fuente (-df)     │
 └──────────────────────────────────────────────────────────┘
 ┌─ 4. MANIFIESTO + NOTIFICACIÓN ───────────────────────────┐
 │ escribe MANIFIESTO.csv → email/telegram con resumen      │
 └──────────────────────────────────────────────────────────┘
```

### 7.2 Menú principal (interfaz)

```
═══════════════════════════════════════════════════════════
  RESPALDOS — servidor-produccion            /mnt/DATOS   libre: 671G
═══════════════════════════════════════════════════════════
  PLAN SUGERIDO  (de MENOR a MAYOR — nunca te quedas sin aire)
  #  PERFIL        ORIGEN   EST.CRUDO   LIBRE    CABE   SOPORTE
  1  RESDOCKER     256K     180K        671G     sí     BD25
  2  RESNETSUITE   3,9G     2,7G        671G     sí     BD25
  3  RESODOO       22G      15G         672G     sí     BD25
  4  RESOTROS      23G      16G         679G     sí     BD25
  5  RESCALIPSO    56G      39G         686G     sí     BD25
  6  RESMAIL       291G     204G        702G     sí     BD50
  7  RESINTRANET   329G     230G        790G     sí     BD25
───────────────────────────────────────────────────────────
  [1] Analizar (dry-run)          [2] Ejecutar perfil
  [3] Ejecutar TODO (en orden)    [4] Estado / reanudar
  [5] Ver log de un proceso       [6] Montar Servidor 14
  [7] Quemar (generar ISO)        [8] Manifiesto / histórico
  [9] Configurar                  [0] Salir
═══════════════════════════════════════════════════════════
Selección: _
```

- La columna **LIBRE** es el espacio que habrá *antes* de ese paso: como cada perfil comprimido y borrado **libera** espacio, va subiendo (671 → 790 G).
- La columna **CABE** es el preflight por trabajo: si un paso no cupiera, se marca **NO** y el plan lo **salta** (nunca arranca algo que no puede terminar).
- La opción **[1] Analizar** es la que «detecta lo que hay que grabar y en base a eso propone»: lista carpetas, tamaño crudo, tamaño estimado comprimido (ratio histórico del perfil), discos necesarios y espacio libre.
- Todo lo que corra más de ~1 minuto se lanza **automáticamente en segundo plano** y el menú te devuelve el PID/session name.

> **Estado (2026-10-13):** `cmd_menu` con **12 opciones** (0–11 + salir): modos · listar · preflight · origen · pull · procesar · **avance** · verificar · manifiesto · configurar · carpetas · ayuda. El **plano FRENTE/FONDO** es un **modo global** (`estado/plano`) análogo a SECO/REAL; `pull`/`procesar` (menú 4/5) lo siguen. Segundo plano implementado (`lib/background.sh`: por **tipo de trabajo**, con **locks separados** pull/procesar y **% de avance**), ver §7.3 y **H.15**.

**`[8] Configurar` (implementado — `lib/config.sh`):**

```
  1  Ver la configuración de un perfil      tabla INTERRUPTOR / PERFIL / GLOBAL / EFECTIVO / ÁMBITO / ORIGEN + qué hace
  2  Editar un interruptor de un perfil     valor actual + descripción, pide confirmación
  3  Editar la configuración operativa      sólo claves ámbito `operativo` (raíces, volumen, medio, correo…)
  4  Completar perfil desde la plantilla    sólo lo que falta; no pisa lo que ya está definido
  5  Comprobar que los perfiles están completos   `configurar validar` (lo hace también al entrar)
  6  Quitar un interruptor operativo        borra la clave → hereda de global (los de carpeta se niegan)
  7  Volver
```

- Se acepta **número o nombre** de clave, y en la lista el valor nuevo se escribe con comas.
- Cada escritura: `jq` valida el JSON → **copia `perfiles.json.bak`** → reescribe. Si el JSON no es válido, **no se toca nada**.
- Sin confirmación no se guarda (dry-run del propio editor).
- Las claves **`carpeta`** no se pueden editar desde «global» ni quitar de un perfil: `configurar` lo rechaza con aviso.

### 7.3 Ejecución en segundo plano y reanudación

```bash
./backup.sh pull-fondo   <PERFIL|all> [--real]   # pull en segundo plano
./backup.sh fondo-iniciar <PERFIL|all> [--real]  # procesar en segundo plano
./backup.sh avance                               # estado de AMBOS trabajos (perfil, fase, %)
./backup.sh fondo <PERFIL> [--real]              # worker del procesado (lo lanza fondo-iniciar)
./backup.sh fondo-pull <PERFIL> [--real]         # worker del pull (lo lanza pull-fondo)
```

- **Dos trabajos independientes** (H.15), cada uno con **lock y estado propios**:
  `estado/bg-procesar.*` y `estado/bg-pull.*` (+ `logs/bg-<tipo>.log`). Locks
  separados → un pull y un procesado pueden correr a la vez sin estorbarse.
- **Plano global** (`estado/plano`): en FONDO, `pull`/`procesar` (menú 4/5) se lanzan
  solos a segundo plano; en FRENTE esperan. `--fondo`/`--frente` lo fuerzan por orden.
- **Cola `all`** ordenada por salida estimada **de menor a mayor** (ascendente = libera disco poco a poco).
- **% de avance** del procesado en `estado/bg-procesar.json`: el proceso marca la fase
  (`preflight→limpiar→empaquetar→verificar→fin`) y un vigilante recalcula el % por
  bytes ya producidos en los sets (`<PERFIL>_*`) contra el objetivo. El **pull** no
  produce sets que contar → `avance` lo muestra como «transfiriendo…» (sin %).
- **Persiste a cierres de SSH** (`setsid -f`); el log va a `logs/bg-<tipo>.log`.
- **Reanudación:** antes de empaquetar re-detecta huérfanos `.partN.rar` y los **verifica** (`rar t`) o los archiva a `.partial/` para rehacer limpio (mitiga A8). El `pull` usa `rsync --partial` (reanudable).

### 7.4 Verificación de espacio y orden de ejecución (lo que pediste)

**Dos niveles de chequeo.**

**1) Plan global (dry-run, opción `[1]`):**

```
for perfil in perfiles:
    salida[perfil] = crudo[perfil] × ratio_historico[perfil]     # o peor_caso=1.0
ordenar perfiles por salida ASC                                  # ← clave
```

**2) Ejecución, un perfil a la vez:**

```
libre = df(/mnt/DATOS)
for perfil in orden:                              # de menor a mayor
    salida    = crudo[perfil] × ratio[perfil]
    necesario = salida × 1.05 + 64 MB              # margen + colchón del contenedor

    if libre < necesario:
        ALERTA  "no cabe <perfil>: faltan N GB"
        marcar NO_CABE;  saltar;  continuar        # ← NUNCA arrancar lo que no entra
    ...
    rar a ... -v98M ...                            # empaquetar
    rar t  ...                                     # VERIFICAR (C5) antes de borrar
    rm -rf <crudo del perfil>                      # liberar SOLO este perfil
    libre = df(/mnt/DATOS)                         # sube; el siguiente cabe mejor
```

**Por qué nunca te quedas sin espacio:**

- Se ordena **de menor a mayor** → el trabajo más grande siempre se hace **al final**, cuando ya se liberó todo lo anterior (§4.5).
- En el peor caso absoluto (`ratio = 1.0`, nada comprime): el pico es **el perfil más grande** (~329 G), muy por debajo de los 671 G libres. Cabe igual.
- Si aun así un paso no cabe, **se salta y avisa** — no se arranca. Arrancar y quedarse a medias deja volúmenes huérfanos (**A8**) y un borrado a medias (**C5**) → justo lo que quieres evitar.

**Otros detalles:**

- El `ratio` se **aprende**: se guarda el real de cada corrida en el manifiesto y la siguiente estimación usa el histórico del perfil (no un número mágico).
- **Multi-día:** el estado vive en `state/<perfil>.estado`. Si se interrumpe, `[4]` retoma por donde iba sin repetir lo ya verificado.
- Chequeo doble: espacio en `/mnt/DATOS` **y** que `rar`/`fdupes` estén instalados.

### 7.5 Notificación por email

**RESUELTO (P3) — `msmtp` + Gmail**, replicando el patrón que ya funciona en `servidor-respaldos` (`monitordisco.sh:274-279`).

**Config `~/.msmtprc` (permisos obligatorios `600`):**

```ini
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        default
host           smtp.gmail.com
port           587
from           admin@ejemplo.com
user           admin@ejemplo.com
password       <APP-PASSWORD>        # NO la contraseña normal
```

**Envío de HTML (patrón exacto probado):**

```bash
enviar_correo() {                      # $1=asunto  $2=HTML  $3=destino
  { echo "Subject: $1"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    printf "%b" "$2"
  } | msmtp "$3"
}
```

**Lo que hay que tener en cuenta:**

- **Gmail exige *App Password*** si la cuenta tiene 2FA: se genera en <https://myaccount.google.com/apppasswords>. Sin 2FA, «acceso a apps menos seguro». La contraseña **nunca** va al repo ni a los respaldos → el repo lleva solo una **plantilla**.
- Instalación: `msmtp` + `ca-certificates` (y `msmtp-mta` para que exista `/usr/sbin/sendmail` y lo usen otras herramientas).
- Probar sin molestar a nadie: `msmtp --serverinfo` y `printf 'Subject: prueba\n\nhola\n' | msmtp destino@x`.
- El mensaje mínimo: perfil · OK/errores · GB producidos · nº de discos a quemar · ruta del manifiesto.

**Replicar en el servidor 45:**

```bash
sudo apt update && sudo apt install -y msmtp msmtp-mta ca-certificates
# copiar la plantilla a ~/.msmtprc, poner la App Password, y:
chmod 600 ~/.msmtprc
printf 'Subject: prueba\n\nhola\n' | msmtp tu-correo@ejemplo.com   # test
```

**Entregables:** `notificaciones/instalar-msmtp.sh` · `notificaciones/msmtprc.template` · `notificaciones/enviar-correo.sh` (ver §8).

> **Estado (2026-10-07):** implementado en `lib/notify.sh` → `avisar_listo` (con la tabla del manifiesto), `avisar_fallo` y `avisar_pull`. **Pendiente:** instalar `msmtp` en `servidor-produccion` y poner la dirección en `global.correo`; mientras tanto se imprime el asunto en consola (`RESPALDO_VERBOSE=1` imprime el HTML).

### 7.6 Montar el Servidor 14

El **Servidor 14 es el origen de todo** (§7.10). Opción `[6]` del menú: ejecuta un helper `montar-s14.sh` con el protocolo que corresponda (pendiente P4): NFS, SMB/CIFS o SSHFS. Debe:

1. Montar en `/mnt/S14/` (con `--mkdir`).
2. Verificar conectividad y espacio.
3. Dejar el origen disponible para que la acción «sacar respaldo» (§7.10) lance su `rsync -aH --info=progress2` hacia `quemar/<PERFIL>/YYYY-MM-DD/`, con log y reanudable.
4. Desmontar al terminar (`umount` con reintento).

### 7.7 Seguridad — cambios de comportamiento obligatorios

| Hoy | Propuesto |
|---|---|
| `cd $carpeta` sin verificar | `[[ -d $carpeta ]] \|\| { log ERROR; exit 1; }` + `set -euo pipefail` + **nunca operar sobre el CWD** (usar rutas absolutas, no `cd`) |
| `fdupes -rdN` directo | Primero `fdupes -rdN --print0` → manifiesto → confirmar → borrar |
| `rar -df` (borra al empaquetar) | Primero `rar` **sin** `-df` → `rar t` verificar → **luego** borrar/borrar-origen |
| Sin dry-run | Toda fase tiene `--dry-run` y el menú lo usa por defecto en `[1]` |
| Basura global | Lista por perfil; **nunca** `.iso/.img/.exe` por defecto; **jpg/png solo si el perfil lo dice explícitamente** |
| Archivos raíz ignorados (C3) | Incluir los archivos sueltos de `carpeta/` en el archive: `rar a … "${carpeta%/}.rar" "$carpeta"/` (un solo archive por perfil) o moverlos a `_raiz/` antes |

### 7.8 Principio de restauración — **cada usuario, su carpeta** (diseño del usuario)

El usuario lo organiza así a propósito: **un directorio por usuario** y, al quemar, se conserva la **ruta completa `RESNEXTCLOUD/<usuario>/…`** (igual en `RESMAIL`, etc.). Ventaja: al restaurar **ves de quién es cada archivo** y copias solo esa carpeta, sin ambigüedad.

**Es un requisito del sistema, no un detalle:**

1. **No aplanar rutas.** El `.rar`/disco debe guardar `RESNEXTCLOUD/<usuario>/…`, nunca volcar todo a un nivel.
2. **Un `.rar` por usuario** = una unidad de restauración. El bucle `for folder in */` ya lo hace bien… y es justo lo que **falla** en las 4 carpetas planas (C3): sin subdirs no hay "usuario" que preservar.
3. **Nombrar el volumen por el usuario**, no `d001`: p. ej. `RESNEXTCLOUD_usuario-g.part01.rar`. Si un usuario no cabe en un disco, sus partes van **contiguas** en el siguiente y el nombre lo dice.
4. **Agrupar discos respetando al usuario:** llenar el disco con **usuarios completos**; solo partir un usuario si por tamaño no cabe entero, manteniendo prefijo + numeración.
5. **Manifiesto por disco** = lista de usuarios/rutas quemadas → permite restaurar sin abrir los `.rar`.

| Estrategia | ¿Fácil de restaurar? | ¿Aprovecha el disco? |
|---|---|---|
| Aplastar todo a `d001` por bytes | ❌ hay que abrir el `.rar` para saber de quién es | ✅ 100 % |
| **Por usuario, llenando discos** | ✅ se ve la ruta | ✅ ~98 % |
| Un usuario por disco sin llenar | ✅✅ | ❌ desperdicia si el usuario es chico |

→ **Regla:** empaquetar **por usuario** y **agrupar** usuarios en cada disco hasta llenarlo (2 % de aire). Nunca aplastar. Esto aplica a `RESNAS` (39 usuarios), `RESNEXTCLOUD` (2), `RESMAIL` (16).

### 7.9 Patrón «carpeta fechada» para sets planos (tu propuesta — ✅ adoptada)

**Problema:** perfiles como RESCALIPSO/RESODOO/RESNETSUITE/RESDOCKER/RESINTRANET son **planos** (0 subdirs) → el `for folder in */` no hace nada y **no hay identidad de restauración**.

**Solución (tu idea): envolver cada set en una subcarpeta con la fecha de su último respaldo.**

```
quemar/RESNETSUITE/
└── 2026-10-06/          ← el set actual, fechado = unidad de restauración
    └── … (todo lo de hoy)

quemar/RESDOCKER/
└── 2026-10-06/
    └── …
```

**Por qué conviene (4 razones):**

1. Convierte un perfil plano en un perfil **con subcarpeta** → el bucle por carpeta (§7.8) ya funciona.
2. La **subcarpeta fechada = unidad de restauración** identificable.
3. Si el set **crece** (RESNETSUITE), **cada respaldo nuevo = nueva carpeta fechada** con solo lo nuevo → incremental real, y los discos se llenan con unidades fechadas completas.
4. Aunque haya **una sola** subcarpeta, el respaldo corre igual sobre ella.

**Nomenclatura:** `YYYY-MM-DD` (se ordena solo). Opcional: `2026-10-06_facturacion-electronica`.

**Fecha del set actual** = la del archivo más reciente:

```bash
Q=/mnt/DATOS/quemar
for d in RESCALIPSO RESODOO RESNETSUITE RESDOCKER RESINTRANET; do
  printf '%-13s rango: %s → %s\n' "$d" \
    "$(find "$Q/$d" -type f -printf '%TY-%Tm-%Td\n' | sort | head -1)" \
    "$(find "$Q/$d" -type f -printf '%TY-%Tm-%Td\n' | sort | tail -1)"
done
```

**Excepción — sets ya comprimidos (RESCALIPSO/RESODOO/RESINTRANET):** no recomprimir. Van con `"comprimir": false` → el empaquetador corre en **modo store** (`7z -mx0` / `rar -m0`): trocea en piezas de 98 MB **sin gastar CPU ni agrandar nada**, y tras la verificación se borra la fuente. Recomprimir un `.rar/.zip` solo gasta CPU y no gana nada.

### 7.10 Flujo real: el sistema **jala (pull) desde el Servidor 14**

Aclaración clave del usuario: **todo el origen está en `/mnt/bak` del Servidor 14 (`servidor-respaldos`)**, que pesa **~6 TB**. Aquí en `servidor-produccion` no se generan datos: se **copian tandas** del 14 hacia `quemar/`. La decisión de *qué* respaldar y *cuándo* es **del usuario** (hoy correos, en un mes otra cosa); el script **obedece, crea la carpeta y copia**. Estos Blu-ray son la **4.ª copia** (seguro, no la principal).

**Acceso: `rsync` sobre SSH, sin montar (recomendado).** Es más simple y robusto que montar con `sshfs` y copiar; no hay que montar/desmontar y es reanudable:

```bash
# copia directa por SSH: reanudable, preserva permisos/fechas/enlaces
rsync -aH --info=progress2 --partial \
  usuario@respaldos:/mnt/bak/<PERFIL>/ \
  /mnt/DATOS/quemar/<PERFIL>/$(date +%F)/
```

`sshfs` en modo `ro` queda como **alternativa** si se quiere *explorar* el 14 a mano; para automatizar, `rsync`-over-SSH basta.

**Qué hace el script:**

| Acción | Comportamiento |
|---|---|
| **A. Sacar respaldo de hoy** | Elige perfil (p. ej. RESMAIL) → crea `quemar/RESMAIL/YYYY-MM-DD/` → `rsync -aH -e ssh usuario@respaldos:/mnt/bak/<PERFIL>/ …` |
| **B. Traer carpetas obsoletas de S14** | Copia (o mueve) carpetas viejas del 14 a `quemar/` como un set más, para quemar |
| **C. Aviso de pendientes** | Si quedan sets sin quemar → **correo** (§7.5): «hay N sets pendientes de quemar» con la lista |
**⚠️ Origen por perfil en `/mnt/bak` (S14 = `10.0.0.14`):**

| Perfil | Origen (`/mnt/bak/…`) |
|---|---|
| RESNETSUITE | `RESNETSUITE/` (ojo `RIDES`, `XML Firmado`, `cmc`) |
| RESCALIPSO | `RESCALIPSO/` |
| RESODOO | `RESODOO/` |
| RESINTRANET | `RESINTRANET/` |
| RESDOCKER | `RESDOCKER/` |
| RESMAIL | `RESMAIL/` |
| RESHOME | `RESNAS/home/` |
| RESPUBLICO | `RESNAS/publico/` |
| RESPRIVADO | `RESNAS/PRIVADO/` |
| RESELECTRON | `RESNAS/electron/` |
| RESISO | `RESNAS/ISO/` |
| RESNEXTCLOUD | `RESNC/` (usuarios `@usuario.com`) |
| USUARIOS *(→ RESOTROS)* | **manual** (bajas: Takeout + PC) |

`10.0.0.14` es el anfitrión; el nombre `servidor-respaldos` no resuelve. **Todos los perfiles tienen origen definido**; el NAS se descompone en 5 (§4.8.1).

---

## 8. Catálogo de entregables

| # | Archivo | Función | Prioridad |
|---|---|---|---|
| 1 | `backup.sh` | Menú principal + dispatcher | **Alta** |
| 2 | `lib/comunes.sh` | log, flock, colores, preflight, cálculo de espacio | **Alta** |
| 3 | `lib/fases.sh` | las 6 fases parametrizadas | **Alta** |
| 4 | `perfiles.json` | configuración global + un objeto por tipo de respaldo (§6.3) | **Alta** |
| 5 | `--estado` / `--reanudar` | ver progreso y seguir | **Alta** |
| 6 | `lib/notify.sh` | email / telegram | Media |
| 7 | `montar-s14.sh` | montaje + rsync desde Servidor 14 | Media |
| 8 | `generar-manifiesto.sh` | CSV + SHA256 por set de volúmenes | Media |
| 9 | `quemar.sh` | generar ISO multi-sesión (`xorriso`/`growisofs`, ambos instalados) y/o grabar directo | Baja |
| 10 | `inventario.sh` | inventario real de `/mnt/DATOS/quemar` (para cerrar §4) | **Alta** |

---

## 9. Pendientes (backlog)

### Bloque 0 — Información (bloqueante para el diseño)

- [x] **P1.** Nivel 1 de `/mnt/DATOS/quemar` + `df` → **HECHO 2026-10-06** (§4.1). Resultado: **9 carpetas** (tras reorganización), **21 de 26 scripts** con ruta inválida; 671 GB libres.
- [x] **P1b.** Desglose por carpeta: tamaño, subdirs vs archivos sueltos, total archivos, extensiones → **HECHO 2026-10-06** (§4.3–§4.4). Resultado: **724,2 GB**, 1 071 908 archivos, 1 250 sueltos en raíz; **4 carpetas con 0 subdirs = 407 GB que hoy no se comprimen**; ratio estimado 0,55–0,80×.
- [x] **P1c.** Capacidad real escribible de un BD virgen → **HECHO 2026-10-06** (§5.2): **25 025 314 816 B** llena · **24 220 008 448 B** formateada → **242 piezas** conservador. ⚠️ El flag **no es** `-report_medium` (no existe en xorriso 1.5.6); usar:
  ```bash
  xorriso -indev /dev/sr0 -tell_media_space
  dvd+rw-mediainfo /dev/sr0
  ```
- [x] **P2.** Herramientas en `servidor-produccion` → **HECHO 2026-10-06**: `rar` 6.02 (trial), `unrar`, `7z`/`7za`, `fdupes`, `tmux`, `xorriso` 1.5.6, `cdrskin`, `growisofs`, `dvd+rw-mediainfo`, `jq`, `rsync`. **`msmtp` ❌** (instalar).
- [x] **P3.** Canal de notificación → **RESUELTO: `msmtp` + Gmail** (§7.5).
- [x] **P4.** Servidor 14 → **SSH a `10.0.0.14:/mnt/bak`** (el nombre `servidor-respaldos` **no resuelve**). **Todos los perfiles con origen definido** (§4.8): 6 directos + 5 del NAS descompuesto + `RESNEXTCLOUD`←`RESNC` + `RESOTROS` (manual).
- [ ] **P5.** Confirmar política de medios por perfil: ¿cuáles van a CD, cuáles a DVD, cuáles a BD25/BD50?
- [ ] **P6.** Confirmar política de "basura": ¿se pueden seguir borrando `mp4/avi/mov/mp3/gif` de los respaldos de usuarios? ¿Y `jpg/png` en `publico`? (Hoy: sí, y es C2/A1.)
- [ ] **P7.** **Estandarizar nomenclatura** (decisión tuya): todas las carpetas en MAYÚSCULAS, un solo nivel bajo `quemar/`, un solo nombre por respaldo. Cierra **M3**, **M2**, **A5**.
- [x] **P8.** Naturaleza de los perfiles planos + fuente de respaldos → **RESUELTO** (§4.3.2, §7.9, §7.10): sets con fecha; el usuario decide y el script hace el `rsync` desde el 14.

### Bloque 1 — Núcleo

- [ ] **B1.** Escribir `lib/comunes.sh` con preflight + `set -euo pipefail` + rutas absolutas (cierra **C1**).
- [ ] **B2.** Escribir `perfiles.json` con las **9 rutas reales** de §4.1 (incluye `RESDOCKER`, **A6**) + nomenclatura en mayúsculas (**M3**, **M2**, **A5**).
- [ ] **B3.** `lib/fases.sh` con dry-run, y fase de basura **por perfil** (**A1**, **A2**, **A3**, **C2**).
- [ ] **B4.** Fase de empaquetado que incluya archivos sueltos de la raíz (**C3**) y aplique el volumen **único** `-v98M` (**§5.4**) + `-rr` (**M6**) + `-ms` (**M5**).
- [ ] **B5.** Verificación (`rar t`) **antes** de borrar la fuente (**C5**).
- [ ] **B6.** Detección y limpieza de volúmenes parciales (**A8**).
- [ ] **B7.** `backup.sh` con menú y ejecución en background + `flock` + `state/` (**A7**, §7.3).
- [ ] **B8.** Preflight de espacio con ratio aprendido (**§7.4**).
- [ ] **B8b.** **Secuencia ascendente + liberación incremental** (§4.5, §7.4): ordenar los trabajos por salida estimada **de menor a mayor**; comprimir → `rar t` → borrar el origen de *ese* trabajo → siguiente. Es **óptimo** y siempre cabe (peor caso: el mayor trabajo son 329 GiB ≤ 671 libres). Reconcilia **C5** con el espacio.
- [ ] **B8d.** **Guarda de preflight por trabajo:** si `libre < salida_estimada × 1,05`, **saltar y avisar**; nunca empezar a comprimir algo que no va a entrar (evita **A8** + disco lleno + trabajo perdido). El menú muestra la secuencia recomendada y qué trabajos entran (§7.2).
- [ ] **B8c.** El empaquetador **impone el 2 % de aire** por disco (corta la lista en `capacidad × 0,98`), porque las piezas finales de cada carpeta son más pequeñas que `V` y el quemador rellenaría los huecos hasta 0 (§5.4).

### Bloque 2 — Complementos

- [ ] **B9.** Notificación (**§7.5**, sujeto a P3).
- [ ] **B10.** Montaje de Servidor 14 + `rsync` de sets a `quemar/<PERFIL>/YYYY-MM-DD/` (**§7.6**, **§7.10**, sujeto a P4).
- [ ] **B11.** Manifiesto `quemados/<ciclo>/MANIFIESTO.csv`.
- [ ] **B12.** Generación de ISO multisesión para quemar.
- [ ] **B13.** Revisitar permisos `777`/`root:root` (**M7**).

### Bloque 3 — Limpieza de legado

- [ ] **B14.** Mover `backup/` + `backup.zip` a `legado/` en solo lectura.
- [ ] **B15.** Migrar `dele.sh` → menú real y archivarlo.

---

## 10. Avances / changelog

| Fecha | Fase | Detalle |
|---|---|---|
| 2026-01-20 | — | `backup.zip` creado (26 scripts + `dele.sh`) en `equipo-local` |
| 2026-10-12 | **H.1** | **Troceado en `-m0` para k3b (decisión del usuario, opción A).** `comprimir:false` ya no «solo quema»: ahora trocea en piezas de 98 MB en modo *store* (`7z -mx0` / `rar -m0`, sin recomprimir), verifica y borra la fuente igual que el resto. Suprimido el atajo «se conserva la fuente» de `procesar`. |
| 2026-10-12 | **H.2** | **Layout real tolerado:** usuarios sueltos al tope (RESHOME=39, RESNEXTCLOUD=2) → un juego por usuario (`PERFIL_<fecha>_<usuario>`, se respeta el nombre tal cual); `adoptar_raiz` no envuelve perfiles `por_usuario`; raíz suelta se limpia tras `_RAIZ`. |
| 2026-10-12 | **H.3** | **Nombres con espacios (datos reales `RESNETSUITE_ARCHIVO CASOS`):** `sets_de` pasa a `find -printf %p` (glob partido rompía verificación con `for f in …`). Regresión: 9 OK / 0 fallas. |
| 2026-10-12 | **H.4** | **Interruptores `empaquetar` y `trocear_grandes` + régimen k3b (decisiones del usuario).** `empaquetar:false` = quemar tal cual (INSTALADORES: sin tocar nada). `trocear_grandes` controla el `-v98M`: `true` parte lo que supere 98 MB; `false` deja el archivo grande entero (RESCALIPSO/RESINTRANET/RESODOO = `-m0` store; trocear sólo cuando supere el volumen). **RESISO aclarado y registrado:** NO son archivos ISO, es documentación/procesos **ISO 9000** (conservar vacío, nota en el perfil). |
| 2026-10-12 | **H.5** | **Segundo plano con % de avance (`lib/background.sh`).** `fondo-iniciar <PERFIL|all> [--real]` lanza con `setsid`+lock global (`flock`); cola `all` ascendente por salida estimada; `avance` muestra fase en vivo y barra de progreso (bytes producidos en sets vs objetivo, vigilante cada 5 s). Menú: opciones 6-7. `prog_fase()` engancha la fase desde `procesar()`. `cron` imprime la receta de crontab (no se autoinstala: quemado manual). |
| 2026-10-12 | **H.6** | **Modo global SECO ⇄ REAL.** `estado/modo` (por defecto `seco`): en seco nada se ejecuta ni borra; en real `procesar`/`pull`/`fondo` actúan sin `--real`. `--real` fuerza real en cualquier modo. `_es_real()` consulta el modo; `pull` también. Menú: línea `ejecución: …` en la cabecera y opción `0` para cambiar (activar REAL exige escribir la palabra `real`). |
| 2026-10-12 | **H.7** | **Colores y entrada amigable.** ANSI en terminal (respeto `NO_COLOR`; sin color al pipear/log). `log()` colorea INFO/AVISO/ERROR. Menú, pickers, tablas y cabeceras coloreados; estado de preflight/listar (OK verde, sin datos amarillo, NO ALCANZA rojo). Submenús de CONFIGURAR usan el selector numerado (con `g) global`) en vez de pedir el perfil a ciegas; todo prompt indica qué escribir. |
| 2026-10-12 | **H.8** | **Fix volúmenes RAR con ceros + verificación idempotente.** rar 6.02 crea piezas `nombre.part001.rar` (con ceros) y `sets_de`/`primer_archivo` solo buscaban `part1.rar` → verificación daba `0 ok / 0 fallas` y bloqueaba el borrado de la fuente (caso real RESELECTRON, 224 volúmenes). Ahora se detectan `.part*.rar`, `.rar`, `.7z*` (cualquier padding) y `primer_archivo` usa `sort -V` (resuelve `part001`/`part1`/`r00…`). Además `_empaquetar_en` ahora **omite set ya existente** (`sets_existen`): re-procesar no re-empaqueta, solo verifica y borra la fuente. |
| 2026-10-12 | **H.9** | **La cola detecta el estado real de cada carpeta.** `fondo all` / `procesar all`: *sin datos* se omite; *ya procesado* (todo empaquetado, sin fuente suelta y sets íntegros) se omite con aviso; *a medias* continúa. `set_completo()` valida piezas `partNNN.rar`/`7z.NNN` consecutivas (un set interrumpido se re-empaqueta, no se salta). `procesado_completo()` exige sin fuente suelta + al menos un set completo; perfiles `empaquetar=false` (tal-cual) nunca se marcan hechos. `procesar <perfil>` también salta lo ya terminado (avisa usar `verificar`); cola vacía aborta limpio (nada pendiente). |
| 2026-10-13 | **H.10** | **Autorreparación de sets a medias (rar interrumpido).** El marcador de "hecho" pasa a ser el `.sha256` (el flujo lo escribe **solo cuando la verificación de ese set pasa**). `empaquetar` ahora: omite el set si tiene `.sha256` **y** su fuente no cambió desde esa verificación (`-type f -newer`); si falta el `.sha256` (rar interrumpido: piezas truncadas) o hay fuente más nueva, **borra las piezas viejas y lo rehace**. `verificar` borra el `.sha256` al fallar. `procesado_completo` exige `.sha256` en cada set. Caso real: RESMAIL 4 sets y RESINTRANET quedaron truncados anoche; ahora se regeneran solos sin quedar bloqueados. |
| 2026-10-13 | **H.11** | **Modo «troceo por archivo» (`empaquetar=false` + `trocear_grandes=true`).** Para carpetas con archivos sueltos que no caben en un disco (RESINTRANET: `*.tar` de 37 GB). En vez de envolver todo en un set del perfil, parte **en el sitio** cada archivo mayor que una pieza (`volumen`, 98M) en piezas de ese tamaño (store según `comprimir`), **verifica** el troceado y **solo entonces borra ESE original**; los archivos ≤ pieza y las subcarpetas quedan intactos. Nunca toca `${PERFIL}_*`, `.sha256` ni las propias piezas. Idempotente (re-ejecutar no repite) y `procesado_completo` da "hecho" cuando no queda archivo > pieza. Probado aislado en `/tmp` (250 MB → 3 piezas de 98M; <98M intactos; interrupción → rehace; piezas ≤ 98 000 000 B). |
| 2026-10-13 | **H.12** | **Procesado por unidad (buzón a buzón).** `procesar` ya no empaqueta todo y verifica al final: recorre las unidades y, por cada una, **empaqueta → verifica ESE set → y sólo si pasa borra la fuente de ESA unidad**, liberando disco incrementalmente (pico ≈ una unidad, no el total → menos riesgo de ENOSPC, causa de los sets truncados). **Confía en el `.sha256`**: si el set ya está verificado y su fuente no cambió, borra la fuente **sin re-verificar** (los 12 sets de RESMAIL ya no se re-prueban). **Reutiliza sets completos sin verificar** (rar terminó y se interrumpió al verificar): los verifica tal cual en vez de re-empaquetar (heurística: la última pieza es parcial; si mide exactamente un volumen se sospecha truncado y se rehace; si el set reusado no verifica, se rehace una vez). `_por_unidad` extrae la enumeración (idéntica) que antes vivía en `empaquetar`. Probado aislado en `/tmp` (8/8: por unidad, confianza `.sha256`, reutilización, corrupción→rehace, fallo→conserva fuente, por_usuario, idempotencia, fuente más nueva→rehace). |
| 2026-10-13 | **H.13** | **Añadir/quitar carpetas sin editar el JSON.** Nuevo `lib/perfiles.sh`: `perfil-nuevo <NOMBRE> [--origen RUTA_S14\|--manual] [--como PERFIL]` crea el bloque desde la plantilla (o copiando los interruptores de otro perfil), valida el JSON y guarda `.bak`; aparece solo en menú/`listar`/`all`/`preflight`. `perfil-quitar <PERFIL>` quita la definición (**nunca** borra datos; avisa si la carpeta tiene contenido). `descubrir` lista las carpetas sin perfil (en el S14 `/mnt/bak/*` y en `$RAIZ/*`, ignorando `lost+found`/`pull_excluir`) y, con terminal, un **asistente** pregunta una por una y las añade. Menú: opción `12 Carpetas`. Probado aislado en `/tmp` (`perfil_crear`/`perfil_quitar`/`validar_config`, asistente con pty). **`descubrir` ya detectó 6 carpetas reales sin perfil en el S14: ACTIVOS, ARCHIVO, QUEMAR, RESVM, RESWEB y RESNEXTCLOUD** (ojo: el perfil `RESNEXTCLOUD` apunta a `/mnt/bak/RESNC`, no a `/mnt/bak/RESNEXTCLOUD`). |
| 2026-10-13 | **H.14** | **Filtros de subcarpetas por perfil (`incluir`/`excluir`).** Dos listas **opcionales** por perfil (claves de ámbito `opcional`: no obligatorias, no heredan de global; vacías = todo, comportamiento clásico idéntico). `excluir` = «respalda todo menos X»; `incluir` = «sólo X». Patrones glob relativos a la carpeta que se empaqueta (el contenedor); una carpeta que coincide excluye todo su contenido. **Se aplican en los 6 puntos que tocan datos**: (1) **pull** (rsync `--exclude=/X` o `--include=/X/*** --include=/X --exclude=*`) → lo excluido ni se descarga; (2) **empaquetado** (`_por_unidad` enumera el primer nivel y salta lo filtrado; sin filtros sigue pasando `.`); (3) **borrado** (lo excluido no entra en ninguna unidad ⇒ **jamás** se borra); (4) **limpieza** (`limpiar`: papelera/vacíos/tmp respetan filtros); (5) **troceo por archivo**; (6) **`procesado_completo`** (una subcarpeta conservada a propósito no bloquea el «hecho»). Probado aislado en `/tmp` (8/8: excluir, incluir, limpieza, `procesado_completo`, troceo, patrones rsync, sin-filtros=clásico, con `carpeta_fecha=true`). Nota: en un perfil con `carpeta_fecha=false` y **sólo** subcarpetas sin archivos sueltos, la raíz se salta (comportamiento pre-existente de H.10; hoy no afecta a ningún perfil real: sólo `INSTALADORES` usa `carpeta_fecha=false` y con `empaquetar=false`). |
| 2026-10-13 | **Despliegue** | **H.11–H.14 desplegadas a `~/sistema` (servidor-produccion).** `rsync -rltD` sin `--delete` (excluye `estado/`, `logs/`, `*.bak`); 5 ficheros (backup.sh, lib/config.sh, lib/fases.sh, lib/pull.sh, **lib/perfiles.sh nuevo**); perfiles.json idéntico (465e7d28). Verificado: md5 local=remoto, `bash -n` OK, `configurar validar` OK, `descubrir listar` OK. Copia previa: `~/sistema-copia-20261013-123630` (servidor-produccion) + `copias/` (local). **Revisión de carpetas descubiertas:** `ACTIVOS`, `ARCHIVO`, `RESWEB`, `RESNEXTCLOUD` (vacías; el Nextcloud real es `RESNC`, que sí tiene perfil) y `QUEMAR` (subdirs `Docker`/`Odoo`/`RESMAIL` vacíos) → **no se añaden**; **`RESVM` (509 GB de backups VM/BD, sin perfil) → el usuario decide NO añadirla**; `RESCALIPSO2` (56 GB) y `RESODOO2` (22 GB) en el destino → se dejan como están. |
| 2026-10-13 | **H.15** | **Plano global FRENTE/FONDO + pull en segundo plano (idea del usuario).** El segundo plano deja de ser una opción aparte (se retira la opción 6) y pasa a ser un **modo global** análogo a SECO/REAL: `estado/plano` (`frente` por defecto). `pull` y `procesar` (y las opciones 4/5 del menú) **siguen el plano**: en FONDO se lanzan solos a segundo plano. `--fondo`/`--frente` lo fuerzan por orden. `lib/background.sh` **generalizado por tipo de trabajo** (`procesar`/`pull`) con **locks y estado separados** (`bg-procesar.*` / `bg-pull.*`, `logs/bg-procesar.log` / `logs/bg-pull.log`): un pull y un procesado pueden correr a la vez sin estorbarse. Nuevos comandos `pull-fondo`, `fondo-pull` (worker). `avance` muestra **ambos** trabajos (procesar con barra y %; pull como "transfiriendo…", sin %). Menú **renumerado 0–11** (opción 0 = submenú de modos; avance→6, verificar→7, manifiesto→8, configurar→9, carpetas→10, ayuda→11). Probado: H.12 8/8, filtros D 8/8, B/C OK; en servidor-produccion, fondo de pull y de procesar, rechazo por lock ocupado y arranque simultáneo con locks distintos. Copia previa en servidor-produccion: `~/sistema-copia-20261013-140749-fondoback`. |
| 2026-10-13 | **H.15.1** | **`avance` con progreso real del troceo por archivo.** En perfiles `empaquetar:false` + `trocear_grandes:true` (p. ej. RESINTRANET) la barra de sets no avanza durante el troceo (`producido` sólo cuenta `PERFIL_*`). Ahora `avance` detecta ese caso y muestra, calculado al vuelo desde el destino, `X de Y archivos grandes (N piezas · Z pendientes)` con barra real del troceo (los hechos se derivan de los stems de `*.partN.rar` cuyo original ya no está). Sin tocar el worker. Verificado en local y contra el trabajo real de RESINTRANET (25 de 84, 1369 piezas, 204,4 GB pendientes). |
| 2026-10-13 | **Docs** | **Manual de usuario `MANUAL.md`** (nuevo, ~600 líneas): qué hace, modos SECO/REAL y FRENTE/FONDO, menú, referencia de comandos, conceptos (perfil/contenedor/set/unidad/`.sha256`/manifiesto), flujo diario, pull, configuración e filtros `incluir`/`excluir`, añadir/quitar carpetas, segundo plano y cron, avisos, problemas frecuentes y glosario. Enlazado desde `README.md`. |
| 2026-10-06 | **Fase 0** | Inventario de los 26 scripts. Tabla maestra, mapeo de rutas, detección de las 6 fases comunes y sus 4 variantes de volumen / 3 variantes de limpieza. |
| 2026-10-06 | **Fase 0** | Análisis del factor 700 MB contra `rar.txt` oficial: confirmado `-v694M` = 694 000 000 B → **correcto para CD 700 MB**. |
| 2026-10-06 | **Fase 0** | 6 hallazgos críticos (C1–C6), 8 altos (A1–A8), 9 medios (M1–M9). |
| 2026-10-06 | **Fase 0** | Cotejo de rutas scripts vs `ls` del servidor → 3 generaciones de estructura inconsistentes; falta `RESDOCKER`; `USUARIOS` vs `usuarios` case-mismatch. |
| 2026-10-06 | **Fase 0** | Diseño de estructura destino, menú principal, pipeline de 4 fases con verificación previa al borrado, ejecución en background con lock/estado, y catálogo de 10 entregables. |
| 2026-10-06 | **Fase 0** | **P1 ejecutado.** Nivel 1 confirmado: 7 carpetas reales, 671 GB libres. **22 de 26 scripts quedan con ruta inválida.** §4 reescrito con datos confirmados. |
| 2026-10-06 | **Fase 0** | **A1 demostrado empíricamente** (§3.2.1): con el patrón actual `find` borra 3 de 10 archivos de prueba; con `*` borra 10 de 10. Añadida la advertencia A2 de por qué *no* basta agregar el `*`. |
| 2026-10-06 | **Fase 0** | ⚠️ **Corrección de diseño:** la v1 proponía `-v24500M` (1 archivo de 25 GB por disco). **Eso es un desperdicio de discos**, no una optimización. Reescrito §5.2–§5.4: la fórmula es `sobrante = capacidad mod V`, luego **a menor `V`, menos desperdicio y más piezas para mezclar carpetas**. Recomendación nueva: **`-v500M`** para BD25 (50 piezas exactas, sobrante 0), `-v470M` DVD, `-v694M` CD. |
| 2026-10-06 | **Fase 0** | **P1b ejecutado.** §4.3–§4.4 nuevos: 724,9 GB en 7 carpetas, 1 071 908 archivos, **1 250 archivos sueltos en raíz** y **4 carpetas con 0 subdirs = 407 GB que el modelo actual jamás comprime** (**C3** confirmado con datos; el mayor agujero es RESINTRANET con 329 GB). Extensiones: 933 942 `.eml` (87 %), 72 190 `.xml`, 57 823 `.pdf` → ratio estimado 0,55–0,80×. |
| 2026-10-06 | **Fase 0** | **P2 parcial:** en `servidor-produccion` sí están `rar`, `fdupes`, `tmux`, `xorriso` y `dvd+rw-mediainfo`. **No hay `mail` ni `msmtp`** → el aviso no puede ser email local. |
| 2026-10-06 | **Fase 0** | 🔧 **Corrección de flag:** `xorriso -report_medium` **no existe** en xorriso 1.5.6. El correcto es **`-tell_media_space`** (o `dvd+rw-mediainfo /dev/sr0`). Corregido en §5.4 y §11. |
| 2026-10-06 | **Fase 0** | 🔧 **Corrección (espacio §4.5):** el hallazgo anterior («pico ~1 295 GB, no cabe») era **erróneo** — sumaba el origen como si hubiera que escribirlo, cuando ya está en el disco. El cálculo correcto: solo hay que escribir la **salida**. Con ratio 0,55–0,80× (400–570 GB) **sí cabe** en 671 GiB libres; solo falla en el peor caso `ratio = 1.0` (~725 GiB > 671). |
| 2026-10-06 | **Fase 0** | ✅ **Solución al espacio (§4.5, §7.4) — idea del usuario:** procesar **de menor a mayor**, comprimiendo → verificando → borrando cada trabajo antes de pasar al siguiente. Demostrado **óptimo** (el libre crece monótonamente) y **siempre cabe**, incluso con `ratio = 1.0`: el pico es el trabajo más grande (~329 GiB) frente a 671 libres. Añadidos **B8b** (secuencia ascendente) y **B8d** (guarda: nunca arrancar un trabajo que no entra; saltar y avisar). El menú muestra la secuencia con columna `LIBRE`/`CABE` (§7.2). |
| 2026-10-06 | **Fase 0** | ⚠️ **Corrección de diseño — 1 % → 2 % y número único:** el usuario pidió **un solo número para BD, DVD y CD**, con colchón suficiente para no fallar al final de la quema (zona de repuesto del BD-R). Se descubre la regla **`V = (100 − p) MB`**, que da **exactamente 250 / 47 / 7 piezas** en BD25 / DVD / CD con **exactamente `p` % de aire**, para cualquier `p`. **Veredicto final: `-v98M`** → 2 % = 500 MB en BD, 94 MB en DVD, 14 MB en CD. Supersede `-v495M`/`-v465M`/`-v693M`. |
| 2026-10-06 | **Fase 0** | ✅ **P3 RESUELTO:** correo por **`msmtp` + Gmail** (patrón de `servidor-respaldos`, ref. `monitordisco.sh:274-279`). §7.5 reescrito; entregables `notificaciones/{instalar-msmtp.sh,msmtprc.template,enviar-correo.sh}` **creados**. Falta instalar `msmtp` en `servidor-produccion`. |
| 2026-10-06 | **Fase 0** | ✅ **«servidor 45» = `servidor-produccion`** (IP 10.0.0.45). Corregido §4.6: **no hay que copiar a otra máquina**; el sistema se instala donde están los datos y la grabadora. |
| 2026-10-06 | **Fase 0** | ✅ **P1c HECHO (disco virgen medido):** grabadora **HL-DT-ST BD-RE WH16NS40**, BD-R **CMC**. Capacidad **25 025 314 816 B** llena · **24 220 008 448 B** formateada. `READ BD SPARE INFORMATION failed` → **sin spare area** (explica los fallos al final). §5.2 reescrito; recomendación **conservadora 242 piezas** y grabar a **4x–6x**. Apéndice C con capacidades reales (BD · DVD 4 707 319 808 · CD 737 280 000). |
| 2026-10-06 | **Fase 0** | **Herramientas de `servidor-produccion` confirmadas:** todo presente (`rar 6.02 trial`, `unrar`, `7z`/`7za`, `xorriso 1.5.6`, `cdrskin`, `growisofs`, `fdupes`, `tmux`, `flock`, `jq`, `rsync`); **falta `msmtp`**. `cdrecord` es en realidad `wodim` (sin `-media-info`). |
| 2026-10-06 | **Fase 0** | **§4.7 nuevo:** `/mnt/DATOS` tiene carpetas extra — `calibre`, `libros`, `mas`, `roms`, `.Trash-1000`. Decisión pendiente. |
| 2026-10-06 | **Fase 0** | **Apéndice A ampliado:** matriz script-por-script de los 26. Confirma 3 duplicados (RESNEXTCLOUD, RESINTRANET, RESMAIL), 3 valores `-v`, y que solo 4 rutas están vivas. |
| 2026-10-06 | **Fase 0** | **§6.3 nuevo: `perfiles.json`** con `global` + `perfiles` y **interruptores por carpeta** (tu idea): duplicados, papelera, versiones, `tmp`, `.iso/.msi/.exe`, fotos. Regla `conservar` > `borrar`. |
| 2026-10-06 | **Fase 0** | **Entregables creados:** `notificaciones/` (3 archivos) y `sistema/diagnostico/diagnostico-45.sh`. Estrategia de prueba local en `equipo-local` con datos sintéticos. |
| 2026-10-06 | **Datos** | 🔄 **Reorganización hecha por el usuario en `quemar/`:** pasa de **7 → 9 carpetas**; se añaden **`RESNEXTCLOUD`** y **`RESNAS`** (consolidación de lo que antes estaba en `2026/RESNAS/*` y `2026/RESNC`). §4.1 actualizado. **§4.3 (tamaños) queda DESACTUALIZADO** → re-medir. |
| 2026-10-06 | **Datos** | ✅ **Re-medición de las 9 carpetas (§4.3):** 80 subdirs, **1 250 archivos en raíz**, **1 071 908 archivos**, **≈724,2 GB** (casi lo mismo que antes, solo redistribuido). Novedades: `RESNAS` (39 carpetas de usuario, solo 871 M, perms 777), `RESNEXTCLOUD` (2 usuarios), `RESMAIL` sube a 16 subdirs/295 G, `USUARIOS` baja a 2 subdirs/16 G. **§4.3.1 nuevo:** datos de usuario repartidos en **3 árboles** (USUARIOS/RESNAS/RESNEXTCLOUD) → riesgo de quemar duplicado. |
| 2026-10-06 | **Diseño** | ✅ **§7.8 nuevo — principio del usuario:** un directorio por usuario y se conserva la **ruta `RESNEXTCLOUD/<usuario>/…`** al quemar, para restaurar fácil. Regla de empaque: **por usuario, llenando discos**; nunca aplastar a `d001`; nombre de volumen = usuario; manifiesto por disco. Aplicado a `RESNAS`/`RESNEXTCLOUD`/`RESMAIL`. |
| 2026-10-06 | **Diseño** | ✅ **§4.3.2 + §7.9 — «set con fecha» (idea del usuario):** los perfiles planos ya comprimidos (RESCALIPSO/RESODOO) **solo se queman**; los que crecen (RESNETSUITE/RESDOCKER) se envuelven en **`AAAA-MM-DD/`** para recuperar subcarpeta y unidad de restauración. Añadido flag `"comprimir": false` a `perfiles.json`. **RESINTRANET (329 G) sigue sin definir.** |
| 2026-10-06 | **Datos** | ✅ **Naturaleza de cada perfil confirmada** (§4.3.2): RESCALIPSO/RESODOO = pg_dump `.backup`+`.zip` (ya comprimido) → `comprimir:false`; RESINTRANET = 551 `.zip`+454 `.tar` (ya comprimido); RESNETSUITE = 72 160 xml + 56 108 pdf → **sí** comprime; `RIDES`/`XML Firmado`/`cmc` = lo que más cambia. |
| 2026-10-06 | **Diseño** | ✅ **§7.10 Flujo real:** todo el origen está en el **Servidor 14** (mirror de NetSuite). El usuario decide qué respaldar; el script **crea `quemar/<PERFIL>/YYYY-MM-DD/`**, lanza el **`rsync`** desde el 14 y **avisa por correo** los sets pendientes de quemar. Único bloqueo: las **rutas de origen en el 14** por perfil (P4). Añadido `origen_s14` a `perfiles.json`. |
| 2026-10-06 | **Datos** | ✅ **Servidor 14 = `servidor-respaldos`** (SSH, Ubuntu, origen `/mnt/bak` ≈ **6 TB**). **Jerarquía de copias:** 1.ª `/mnt/bak` · 2.ª `/mnt/mirror` · 3.ª nube · **4.ª = estos Blu-ray**. **Respaldo por tandas** que elige el usuario. Recomendado **`rsync` sobre SSH** directo (sin montar) en vez de `sshfs` (§7.10). |
| 2026-10-06 | **Datos** | ✅ **Listado real de `/mnt/bak` obtenido** (§4.8): `ACTIVOS`, `ARCHIVO`, `INSTALADORES`, `QUEMAR`, `RESCALIPSO`, `RESDOCKER`, `RESINTRANET`, `RESMAIL`, `RESNAS`, `RESNC`, `RESNETSUITE`, `RESNEXTCLOUD`, `RESODOO`, `RESVM`, `RESWEB`. **Host = `10.0.0.14`** (el nombre `servidor-respaldos` no resuelve). **P6:** carpeta `INSTALADORES` localizada. |
| 2026-10-06 | **Datos** | ✅ **Mapeo S14 resuelto** (§4.8, §7.10): 6 perfiles directos. `RESNAS/` = storage NAS/Nextcloud (`home/publico/PRIVADO/electron/ISO`); **`RESNEXTCLOUD` ← `RESNC/`** (data Nextcloud, usuarios `@`); `RESNEXTCLOUD/` en S14 está **vacío**; `/mnt/bak/QUEMAR/` = bandeja de quema del 14 (`Docker`, `Odoo`, `RESMAIL`); `ACTIVOS`/`ARCHIVO` vacíos. **Solo `USUARIOS` sin origen claro.** |
| 2026-10-06 | **Datos** | ✅ **NAS descompuesto** (§4.8.1): `RESNAS` → **RESHOME / RESPUBLICO / RESPRIVADO / RESELECTRON / RESISO** (decidido). `quemar/RESNAS` renombrado a **RESHOME**. **`RESNC` = `RESNEXTCLOUD`** (mismo servidor, renombrado en la migración). **`USUARIOS` = `RESOTROS`** (bajas, manual). **Set = 13 perfiles.** `perfiles.json` actualizado con orígenes reales. **P4 cerrado.** |
| 2026-10-07 | **Código** | ✅ **Esqueleto de `sistema/` creado y probado** (§6.2): `perfiles.json` (13 perfiles, rutas relativas → pruebas en `/tmp`), `lib/comunes.sh`, `lib/notify.sh`, `backup.sh` (`listar`, `origen`, `pull`, `ciclos`, `ayuda`), `pruebas/datos.sh`. `pull` solo imprime el `rsync` salvo `--ejecutar`. |
| 2026-10-07 | **Código** | ✅ **`lib/fases.sh` completo y probado de punta a punta** (§6.2): `preflight` (A8), `limpiar` (papelera/versiones/duplicados/basura/vacíos, con listado previo = C5), `empaquetar` (volumen exacto 98 000 000 B, `por_usuario` + `_RAIZ` = C3), `verificar` (`7z t`/`rar t` + `sha256`), `borrar_fuente` **solo si verificó**. **Dedup por usuario** (§7.8). Corregido el bug `//` de jq que hacía ignorar `comprimir:false`. |
| 2026-10-07 | **Código** | ✅ **Fase 4 (manifiesto + aviso), `pull` y menú.** `lib/manifiesto.sh` escribe `quemados/<ciclo>/MANIFIESTO.csv` (ciclo · fecha · perfil · juego · volúmenes · bytes · `sha256` · estado), con deduplicado al re-verificar; `verify` ahora barre `${perfil}_*` en el destino → **verifica también los sets ya empaquetados** (antes daba 0 tras borrar la fuente). `lib/pull.sh` con `--exclude` desde `global.pull_excluir`, log en `logs/<P>-pull.log` y aviso. `avisar_listo`/`avisar_fallo`/`avisar_pull` (HTML con tabla del manifiesto). Menú con 9 opciones. **`verificar all`, `pull all`, `manifiesto [all]`, `ciclos`**. |
| 2026-10-07 | **Código** | ✅ **`[8] Configurar` implementado** (`lib/config.sh`, §7.2): catálogo de 19 interruptores con descripción; `configurar ver <P>` muestra PERFIL / GLOBAL / EFECTIVO / ORIGEN; edición de sí-no, texto, número y listas con confirmación; **quitar clave → hereda de global**; cada escritura valida el JSON y guarda `perfiles.json.bak`. **`conservar` pasa a estar implementado** (filtra el `find` de basura, precedencia sobre `borrar`) y **`borrar_duplicados` ahora es interruptor real** (global a `true` para no cambiar el comportamiento actual). |
| 2026-10-07 | **Datos** | ✅ **`borrar_videos` + `borrar_musica`** (petición del usuario): las extensiones de vídeo/música salen del `borrar` genérico y pasan a dos interruptores propios, **globales a `true`** (mismo comportamiento que antes, pero controlable por perfil). Cobertura ampliada (`.mkv .flac .webm .opus`…). Motivo: no se van a respaldar colecciones de música, vídeos de YouTube ni fotos personales que no son de la empresa. **`borrar_fotos` sigue en `true` sólo en `RESPUBLICO` → pendiente de confirmar** (riesgo de borrar evidencia fotográfica de trabajo). |
| 2026-10-07 | **Diseño** | ✅ **Sin interruptores globales de política (corrección del usuario):** `global` deja de contener `comprimir`, `carpeta_fecha`, `por_usuario`, los 8 `borrar_*`, `borrar`, `conservar`, `store` y `origen_s14`. **Las 14 carpetas los definen explícitamente** (`RESPUBLICO` único con `borrar_fotos:true`; `RESOTROS` único con `borrar_instaladores:true`; `RESHOME`/`RESNEXTCLOUD` con papelera/duplicados; `RESISO` e `INSTALADORES` con listas `borrar` sin `.iso/.img/.exe/.msi` y su `conservar` correspondiente). Sólo heredan de `global` los **parámetros operativos** (raíces, medio, capacidad, volumen, aire, compresión, integridad, empaquetador, correo, orden, `dry_run`). |
| 2026-10-07 | **Código** | ✅ **Ámbito `carpeta`/`operativo` en el editor + guardas:** `bool_config`/`lista_config` **ya no caen en `global`** para claves de carpeta (clave `operativo` como `verificar_antes_de_borrar` sigue heredando — era una trampa de regresión). `configurar` gana columnas `ÁMBITO`, subcomando **`configurar validar`** (`validar_config`, 14×16 comprobaciones) y opciones **Completar desde plantilla** / **Comprobar completos**; rechaza editar una clave de carpeta en `global` y **quitarla** de un perfil. `procesar`/`limpiar`/`empaquetar` abortan si falta alguna. Nueva clave raíz `plantilla` (sólo para completar, **nunca se lee en runtime**). Regresión completa: `procesar all --real` rc=0 (RESPUBLICO borró 5 basuras, RESOTROS instaladores+vídeo, RESHOME papelera+duplicados, RESNEXTCLOUD papelera+versiones, RESCALIPSO/RESODOO/RESINTRANET conservaron fuente), `verificar all` rc=0, `manifiesto all` 45 juegos OK. |
| 2026-10-07 | **Código** | 🔧 **Bug detectado al desplegar en `servidor-produccion`: los datos están en la RAÍZ del perfil (sin carpeta `AAAA-MM-DD`) y `empaquetar` no hacía nada (rc=0, silencioso).** Arreglado: `contenedores()` usa la raíz como contenedor si no hay subcarpetas; nuevo **`adoptar_raiz`** mueve los archivos sueltos de la raíz a `AAAA-MM-DD/` de hoy (idempotente, **nunca toca `${p}_*` ni `*.sha256`** → cierra **C3**); `fecha_de()` pone la fecha de hoy cuando el contenedor es la raíz; **`borrar_fuente` ya no borra la raíz entera** (sólo lo que no sea juego ni manifiesto — si no, habría borrado los `.rar` recién creados). **Probado en real sobre `servidor-produccion`:** `RESDOCKER` → 13 `.json` → `2026-10-07/` → `rar a -m5 -v98M -rr3% -ms…` → **1 volumen**, `rar t` **OK**. Primera vez que la rama `rar` corre de verdad. |
| 2026-10-07 | **Código** | 🔧 **Regresión de seguridad encontrada en la corrida real de `servidor-produccion`: `verificar_antes_de_borrar` caía a `false`** (la clave estaba fuera del catálogo → `_config_ambito` la trataba como `carpeta` → el perfil no la define → `false`), así que **`borrar_fuente` borró la fuente SIN verificar** y el aviso decía «0 listos». Arreglado: `_config_ambito` ahora **si la clave vive en `global` la trata como `operativa`**, y `verificar_antes_de_borrar` / `empaquetador` / `factor_salida` entran al catálogo (visibles y editables). Añadido **guarda de idempotencia**: si un perfil ya está procesado, `empaquetar` dice «nada que empaquetar» en vez de empaquetar los juegos dentro de sí mismos; `borrar_fuente` en raíz conserva `${p}_*` y `*.sha256`. Verificado en real: re-ejecutar `procesar RESDOCKER --real` → `OK (1 volúmenes)`, `.rar` intacto, «1 listos». Regresión local 9 OK / 0 fallas. |
| — | Fase 1 | *No iniciada* — ver Bloque 1 del backlog. |

---

## 11. Lo que necesito (comandos a pegar en `servidor-produccion`)

> **Estado 2026-10-06:** los bloques **1, 3, 4 y 5** ya se ejecutaron (§4.3–§4.4, P1b/P2). Para lo que falta, usa el **bloque ampliado §11.1** (lo reemplaza y lo completa), sobre todo:
> **(A)** medir la capacidad real con un **disco virgen** (P1c), **(C)** localizar los **instaladores** `.iso/.msi/.exe`, **(D)** peso por extensión **por perfil** y **(B)** confirmar qué rutas viejas siguen vivas.

```bash
Q=/mnt/DATOS/quemar

echo "===== 1. TAMAÑO Y ESTRUCTURA POR CARPETA ====="
for d in "$Q"/*/; do
  printf "%-14s subdirs=%-5s archivos_raiz=%-8s total_archivos=%-8s %s\n" \
    "$(basename "$d")" \
    "$(find "$d" -mindepth 1 -maxdepth 1 -type d | wc -l)" \
    "$(find "$d" -mindepth 1 -maxdepth 1 -type f | wc -l)" \
    "$(find "$d" -type f | wc -l)" \
    "$(du -sh "$d" 2>/dev/null | cut -f1)"
done

echo; echo "===== 2. TOTALES ====="
du -sh "$Q"; find "$Q" -type f | wc -l

echo; echo "===== 3. ¿YA EXISTEN .RAR? ¿CÓMO SE LLAMAN? ====="
find "$Q" -name '*.rar' | head -20
echo "total .rar: $(find "$Q" -name '*.rar' | wc -l)"

echo; echo "===== 4. EXTENSIONES (define el ratio de compresión) ====="
find "$Q" -type f -printf '%f\n' | grep -o '\.[^.]*$' | tr 'A-Z' 'a-z' \
  | sort | uniq -c | sort -rn | head -25

echo; echo "===== 5. HERRAMIENTAS INSTALADAS ====="
for c in rar unrar fdupes tmux screen 7z rsync mail msmtp mutt curl; do
  printf "%-8s %s\n" "$c" "$(command -v "$c" || echo NO)"
done

echo; echo "===== 6. CAPACIDAD REAL ESCRIBIBLE DE UN BD VIRGEN ====="
ls -l /dev/sr* 2>/dev/null || echo "sin /dev/sr*"
xorriso -indev /dev/sr0 -tell_media_space 2>&1 | head -30
dvd+rw-mediainfo /dev/sr0 2>&1 | head -30

echo; echo "===== 7. MONTAJES Y FSTAB ====="
mount | grep -E 'DATOS|S14'
grep -vE '^\s*#|^\s*$' /etc/fstab

echo; echo "===== 8. SERVIDOR 14 (si aplica) ====="
ip route | head -3
ls -l ~/.ssh/ 2>/dev/null | head
grep -rA3 -i 's14\|servidor14' ~/.ssh/config /etc/fstab 2>/dev/null

echo; echo "===== 9. RUTAS VIEJAS DE LOS SCRIPTS ====="
for p in 2026 salieronEE RESWEB RESVM RESNEXTCLOUD BAK CARATULAS usuario-c \
         usuarios usuario-a usuario-d usuario-e usuario-b publico PRIVADO home ISO electron; do
  [ -e "$Q/$p" ] && echo "EXISTE   $Q/$p" || echo "NO EXISTE $Q/$p"
done

echo; echo "===== 10. PESO POR EXTENSIÓN (afina el ratio) ====="
find "$Q" -type f -printf '%s %f\n' \
  | awk '{ n=$2; sub(/.*\./,"",n); if (n==$2) n="(sin ext)"; s[tolower(n)]+=$1; c[tolower(n)]++ }
         END { for (e in s) printf "%12d  %8d  %s\n", s[e], c[e], e }' \
  | sort -rn | head -25

echo; echo "===== 11. ESPACIO DEL VOLUMEN ====="
df -h /mnt/DATOS
df -B1 /mnt/DATOS | tail -1
```

**Qué me dicen estos bloques:**

| Bloque | Qué resuelve | Estado |
|---|---|---|
| 1–2 | Saber qué pesa qué → perfiles, estimación de salida y de discos necesarios | **1 ✅ hecho** |
| 1 (columna `archivos_raiz`) | Detecta **C3**: carpetas con archivos sueltos que hoy jamás se comprimen | **✅ hecho** — 1 250 archivos / 407 GB |
| 3 | Saber si ya hay volúmenes `.rar` hechos y con qué `-v` (reanudación, **A8**) | **✅ hecho** — 12 `.rar`, todos de usuarios |
| 4 | Decidir `-m5` vs `-m3` vs `-m0` y `-ms…` por perfil (**M5**) | **✅ hecho** (conteos) — falta el **bloque 10** con los **bytes** |
| 5 | Saber si hay que instalar `rar`/`fdupes`/`tmux` (**P2**) | **✅ hecho** — todo presente; `rar` es *trial*, falta **`msmtp`** en `servidor-produccion` |
| 6 | **P1c** — capacidad real escribible → número exacto del `-v` (§5.2) | ✅ **HECHO** — 25 025 314 816 B; conservador 24 220 008 448 → **242 piezas** |
| 7–8 | Montaje de `/mnt/DATOS` (✅ ext3) y ruta al Servidor 14 (**P4**) | S14 ⏳ pendiente (SSH sin entradas para S14) |
| 9 | Confirmar qué scripts quedan definitivamente muertos | ✅ **HECHO** — solo los 7 perfiles de `quemar/` existen; el resto de rutas no |
| 10 | **Peso** por extensión → ratio de compresión real por perfil | ⏳ nuevo |
| 11 | Bytes exactos libres → cierra el cálculo de lotes de §4.5 | 671 GiB libres · `/` 294 GiB libres |

### 11.1 Bloque ampliado — lo que aún falta (solo lectura)

El sondeo del `/dev/sr0` ya está hecho (bloque 6 ✅, ver §5.2). Falta **localizar instaladores**, **peso por perfil**, **basura de Nextcloud** y **qué está ya quemado**. Pega esto:

```bash
Q=/mnt/DATOS/quemar

echo "===== C. INSTALADORES (.iso/.msi/.exe/.img) — DÓNDE ESTÁN ====="
find /mnt/DATOS -type f \( -iname '*.iso' -o -iname '*.msi' -o -iname '*.exe' -o -iname '*.img' \) \
  -printf '%h\n' | sed 's#/mnt/DATOS/##; s#/.*##' | sort | uniq -c | sort -rn
echo "--- los 20 más grandes:"
find /mnt/DATOS -type f \( -iname '*.iso' -o -iname '*.msi' -o -iname '*.exe' -o -iname '*.img' \) \
  -printf '%12s  %p\n' | sort -rn | head -20

echo; echo "===== D. PESO POR EXTENSIÓN Y POR PERFIL ====="
for d in "$Q"/*/; do
  echo "----- $(basename "$d")"
  find "$d" -type f -printf '%s %f\n' \
   | awk '{n=$2; if(n ~ /\./) sub(/.*\./,"",n); else n="(sin)"; n=tolower(n); b[n]+=$1; c[n]++}
          END{for(k in b) printf "%14.1f MB %9d .%s\n", b[k]/1048576, c[k], k}' \
   | sort -rn | head -10
done

echo; echo "===== E. BASURA DE NEXTCLOUD (papelera + versiones) ====="
find "$Q" -type d \( -name files_trashbin -o -name files_versions \) -print
du -sch $(find "$Q" -type d \( -name files_trashbin -o -name files_versions \) 2>/dev/null) 2>/dev/null | tail -1

echo; echo "===== F. DUPLICADOS Y QUÉ YA ESTÁ QUEMADO ====="
echo "archivos repetidos (NO borra): $(fdupes -r "$Q" 2>/dev/null | wc -l)"
echo "--- .rar existentes (volúmenes ya hechos):"
find "$Q" -type f -iname '*.rar' -printf '%12s  %TY-%Tm-%Td  %p\n' | sort -rn | head
echo "--- carpetas tipo quemado/salidos/discos:"
find /mnt/DATOS -maxdepth 3 -type d \( -iname '*quem*' -o -iname '*salier*' -o -iname '*dvd*' -o -iname '*disco*' \) 2>/dev/null

echo; echo "===== G. TAMAÑO DE LAS CARPETAS EXTRA (§4.7) ====="
du -sh /mnt/DATOS/calibre /mnt/DATOS/libros /mnt/DATOS/mas /mnt/DATOS/roms /mnt/DATOS/.Trash-1000 2>/dev/null
```

| Bloque | Qué resuelve | Estado |
|---|---|---|
| **C** | Localizar los **instaladores** `.iso/.msi/.exe` → decide `borrar_instaladores` por carpeta (§6.3) | ⏳ |
| **D** | **Peso real** (bytes) por extensión y perfil → ratio de compresión y nº de discos | ⏳ |
| **E** | Cuánto ocupa la **papelera/versiones** de Nextcloud → cuánto se ahorra al no respaldarlas | ⏳ |
| **F** | **Duplicados** (cuánto se ahorra `fdupes`) y qué `.rar` ya existen | ⏳ |
| **G** | Tamaño de `calibre/libros/mas/roms/.Trash-1000` → decidir si entran (§4.7) | ⏳ |

### Decisiones que necesito de ti (mientras tanto)

1. **Nomenclatura (P7)** — propongo: todo en MAYÚSCULAS, un solo nivel bajo `quemar/`, un nombre por respaldo. ¿Lo hago?
2. **Canal de aviso (P3)** — ✅ **RESUELTO**: `msmtp` + Gmail (§7.5). Solo falta instalarlo en `servidor-produccion` y decidir **a qué correo(s)** llega el aviso.
3. **Servidor 14 (P4)** — ✅ **casi resuelto**: SSH a `10.0.0.14:/mnt/bak` (§4.8). Solo falta aclarar de dónde salen `RESNAS` (39 usuarios), `RESNEXTCLOUD` (2) y `USUARIOS` — en `/mnt/bak` hay `RESNAS`, `RESNC` y `RESNEXTCLOUD`, pero **no `USUARIOS`**.
4. **Medios (P5)** — qué respaldos van a CD / DVD / BD25 / BD50.
5. **Basura (P6) — ahora POR PERFIL** (tu idea del JSON). Preguntas concretas:
   - `tmp`: ¿se borra siempre? Propongo **sí**, salvo perfiles que lo pidan.
   - `.iso / .msi / .exe`: **borrar en carpetas de usuarios** (`USUARIOS`, descargas) pero **conservar en carpetas de instaladores**. → ✅ **Ruta hallada:** `/mnt/bak/INSTALADORES` en el Servidor 14 (perfil propio, §4.8).
   - `jpg / png`: hoy solo `publico` los borra. ¿Se mantiene?
   - `files_trashbin` / `files_versions` (papelera/versiones de Nextcloud): ¿siempre fuera?
   - Ojo: la carpeta **`ISO`** de los scripts **no es de imágenes de disco** sino **documentos ISO 9000** → nunca tratarla como basura.
6. **Carpetas extra en `/mnt/DATOS`** (§4.7) — `calibre`, `libros`, `mas`, `roms`: ¿entran al respaldo? ¿La papelera `.Trash-1000` se vacía?
7. **Capacidad del Blu-ray** — dado tu historial, ¿arrancamos **conservador (242 piezas, ~5 % libre)** o **lleno (250, 2,1 %)** y grabando a 4x–6x?
8. **RAR vs 7z** — recomiendo **RAR** por `-rr` (recupera un volumen dañado, clave en disco óptico). `7z` está instalado pero su equivalente no es tan bueno. ¿Confirmamos RAR (o compramos licencia, porque es *trial*)?
9. **Borrado de la fuente / orden de ejecución** — recomiendo la **secuencia ascendente con borrado por trabajo** (§4.5, §7.4):
   - **(A) Ascendente + borrar por trabajo** *(recomendado)*: comprimir un perfil → `rar t` → borrar **ese** perfil → siguiente. **Siempre cabe** y respeta **C5**.
   - **(B) `-df`**: borra al comprimir, más rápido, pero **sin verificación previa** → volado con un volumen dañado.
   - **(C) No borrar hasta el final**: **sí cabe** si el ratio ≤ ~0,92 (caso esperado), pero **falla con datos incompresibles**.

---

## Apéndice A — Detalle por script (revisión completa de los 26)

Leyenda: **T** = borra `files_trashbin` · **D** = `fdupes -rdN` · **basura** = lista de extensiones · **F** = además borra `jpg/png` · **V** = limpia vacíos · **`-v`** = tamaño de volumen legado.

| # | script | ruta objetivo | T | D | basura | F | V | `-v` |
|---|---|---:|:-:|:-:|:-:|:-:|:-:|:-:|
| 1 | `usuario-a` | `quemar/usuario-a` | ✓ | ✓ | larga | | ✓ | 694M |
| 2 | `BAK` | `quemar/BAK` | ✓ | ✓ | larga | | ✓ | 694M |
| 3 | `caratulas` | `quemar/CARATULAS` | ✓ | ✓ | larga | | ✓ | 694M |
| 4 | `usuario-b` | `quemar/usuario-b` | ✓ | ✓ | larga | | ✓ | 694M |
| 5 | `usuario-c` | `quemar/usuario-c` | ✓ | ✓ | larga | | ✓ | 694M |
| 6 | `nextcloud` | `quemar/RESNEXTCLOUD` | ✓ | ✓ | larga | | ✓ | 694M |
| 7 | `rescalipso` | `quemar/RESCALIPSO` ✅*existe* | ✓ | ✓ | larga | | ✓ | 694M |
| 8 | `resintranet` | `2026/RESINTRANET` | ✓ | ✓ | larga | | ✓ | 694M |
| 9 | `resmail2` | `2026/RESMAIL` | ✓ | ✓ | larga | | ✓ | 694M |
| 10 | `resnextcloud` | `quemar/RESNEXTCLOUD` | ✓ | ✓ | larga | | ✓ | 694M |
| 11 | `resodoo` | `quemar/RESODOO` ✅*existe* | ✓ | ✓ | larga | | ✓ | 694M |
| 12 | `restakeout` | `quemar/RESTAKEOUT` | ✓ | ✓ | larga | | ✓ | 694M |
| 13 | `resvm` | `quemar/RESVM` | ✓ | ✓ | larga | | ✓ | 694M |
| 14 | `resweb` | `quemar/RESWEB` | ✓ | ✓ | larga | | ✓ | 694M |
| 15 | `usuario-d` | `quemar/usuario-d` | ✓ | ✓ | larga | | ✓ | 694M |
| 16 | `usuario-e` | `quemar/usuario-e` | ✓ | ✓ | larga | | ✓ | 694M |
| 17 | `usuarios` | `quemar/usuarios` ✅*existe* | ✓ | ✓ | larga | | ✓ | 694M |
| 18 | `webcalipso` | `quemar/RESINTRANET` ✅*existe* | | ✓ | corta | | ✓ | 694M |
| 19 | `home` | `2026/RESNAS/home` | | ✓ | corta | | ✓ | 688M |
| 20 | `netsuite` | `2026/RESNETSUITE` | | ✓ | corta | | ✓ | 688M |
| 21 | `privado` | `2026/RESNAS/PRIVADO` | | ✓ | corta | | ✓ | 687M |
| 22 | `publico` | `2026/RESNAS/publico` | | ✓ | corta | **✓** | ✓ | 687M |
| 23 | `electron` | `2026/RESNAS/electron` | | | ninguna | | ✓ | 687M |
| 24 | `ISO` | `2026/RESNAS/ISO` (docs ISO 9000) | | | ninguna | | ✓ | 688M |
| 25 | `resmail` | `2026/RESMAIL` | | | ninguna | | ✓ | 688M |
| 26 | `dele` | *(lista de menú comentada, no comprime)* | | | — | | | — |

**Lo que revela la matriz:**

- **Solo 4 scripts apuntan a rutas vivas:** `rescalipso`, `resodoo`, `webcalipso`→RESINTRANET, `usuarios`. Los otros **21 apuntan a rutas muertas** (`2026/…` o `RESWEB/…` que ya no existen).
- **Tres duplicados/conflictos de objetivo:**
  - **RESNEXTCLOUD** ← `nextcloud.sh` **y** `resnextcloud.sh` (idénticos).
  - **RESINTRANET** ← `resintranet.sh` (larga) **y** `webcalipso.sh` (corta).
  - **2026/RESMAIL** ← `resmail.sh` (sin basura) **y** `resmail2.sh` (larga).
- **Tres `-v` distintos sin criterio:** `694M` (×18), `688M` (×4), `687M` (×3).
- **`tmp`** aparece solo en la lista **larga**; `.iso/.img/.exe/.msi` también solo en la larga (y `.msi/.exe` en la corta).
- **`publico` es el único** que borra fotos. **`electron` e `ISO` no limpian nada** (solo comprimen).

**Variantes de la lista de basura (línea 13 equivalentes):**

- **Larga (15 ext.)** — `usuario-a, BAK, caratulas, usuario-b, usuario-c, nextcloud, rescalipso, resintranet, resmail2, resnextcloud, resodoo, restakeout, resvm, resweb, usuario-d, usuario-e, usuarios`:
  `*.gif *.pst .msi .dbx .tmp .iso .img .exe .mpg *.mp3 *.wma *.wmv *.mp4 *.avi *.mov`
- **Corta (9 ext.)** — `home, netsuite, privado, webcalipso`:
  `*.gif .msi .exe .mpg *.mp3 *.mp4 *.avi *.mov`
- **Con imágenes (11 ext.)** — `publico`: `*.jpg *.png *.gif .msi .exe .mpg *.mp3 *.mp4 *.avi *.mov`
- **Sin basura** — `dele, electron, ISO, resmail`

**Sufijos que NO funcionan (falta `*`):** `.msi .dbx .tmp .iso .img .exe .mpg`
**Sufijos que sí funcionan:** `*.gif *.pst *.mp3 *.wma *.wmv *.mp4 *.avi *.mov` (+ `*.jpg *.png` en `publico`)

---

## Apéndice B — Referencias

- Documentación oficial de RAR: `-v<size>[k|b|f|m|M|g|G]` — «megabytes - `m`, millions of bytes - `M`».
  `rar.txt` (WinRAR) — `-v` p. 2162-2184 · `-df` p. 880-883 · `-rr[N]` p. 1848 · `-ms` p. 1449 · `-vp` p. 2285
  <https://github.com/Aerovin/winrar/blob/master/rar.txt>
- WinRAR — *Archive name and parameters dialog* (unidades de tamaño):
  <https://documentation.help/WinRAR/HELPGetArcGeneral.htm>
- WinRAR — *Alphabetic switches list*: <https://documentation.help/WinRAR/HELPSwitches.htm>
- RAR: los switches **no distinguen mayúsculas** (`-R` == `-r`), pero **el sufijo de tamaño sí** (`m` != `M`).

---

## Apéndice C — Tarjeta de referencia (lo ya confirmado)

**Datos del servidor — `servidor-produccion` (= «servidor 45», IP 10.0.0.45), 2026-10-06:**

```
/mnt/DATOS/quemar/   =  RESCALIPSO · RESDOCKER · RESINTRANET · RESMAIL
                        RESNETSUITE · RESODOO · USUARIOS      (7, nada más)
/mnt/DATOS/ además:     calibre · libros · mas · roms · .Trash-1000   (§4.7 — por decidir)
/dev/sdb  1,8T · 1,1T usado · 671G libre (62%) en /mnt/DATOS   (ext3, bloque 4096)
Grabadora: HL-DT-ST BD-RE WH16NS40 (fw 1.00) en /dev/sr0
OS: Ubuntu 24.04.5 · kernel 6.8.0-146 · bash 5.2.21 · rar 6.02 (trial)
```

**Números que se usan una y otra vez:**

| Concepto | Valor |
|---|---|
| `-v694M` | 694 000 000 B (M = millones, no MiB) |
| `-v694m` | 727 711 744 B → **no cabe en un CD** |
| CD-R 80 min (real) | **737 280 000 B** (360 000 × 2048) |
| DVD-R SL (real) | **4 707 319 808 B** (2 298 496 × 2048) |
| BD-R SL (real, medido) | **25 025 314 816 B** (12 219 392 × 2048) = 23,28 GiB ✅ |
| BD-R SL formateado `00h(3000)` | **24 220 008 448 B** (11 826 176 × 2048) |
| Regla de aire (universal) | **`V = (100 − p) MB`** → `p` = % de aire |
| **`-v` elegido (BD+DVD+CD)** | **`-v98M`** → **250 / 242 · 47 / 7 piezas** |
| Aire `-v98M` en BD lleno | **525 MB = 2,10 %** |
| Aire `-v98M` en BD conserv. | 242 piezas → **1 309 MB = 5,23 %** |
| `-v97M` / `-v95M` (BD) | 250 piezas · 775 MB / 1 275 MB de aire |
| **Recomendado arrancar** | capacidad BD = **24 220 008 448** → **242 piezas** |
| **Velocidad de grabado** | **4x–6x** (NO 12x) por ser medio CMC barato |
| ⚠️ Peligroso | llenar al 100 % → **falla al final** (sin *spare area*, confirmado) |
| Overhead del directorio ISO en BD | ~10 MB con 250 archivos → irrelevante |
| **Secuencia de compresión** | **de MENOR a MAYOR**, borrando cada trabajo al terminar (§4.5) |
| Espacio | origen **724,9 GiB** · libres **671 GiB** · peor caso (ratio 1) **cabe** con orden ascendente |

**Comprobación rápida de `-v` y capacidad:**
```bash
# ¿qué vale realmente mi -v?
python3 -c "print(98*1000*1000, 98*1024*1024)"       # M  vs  m

# verificar -v98M en los TRES soportes (p = % de aire), con capacidades REALES
python3 -c "
med=[('BD-R',25_025_314_816),('DVD-R',4_707_319_808),('CD-R',737_280_000)]
V,p=98,2
for name,C in med:
    B=C-C*p//100; n=B//(V*10**6); air=C-n*V*10**6
    print(f'{name:6} {n:>4} piezas  aire {air/1e6:>6.0f} MB = {100*air/C:.2f} %')"

# caso conservador BD (capacidad formateada 00h sobre un disco de 23,28 GiB)
python3 -c "
C=24_220_008_448; V=98*10**6
n=(C-C*2//100)//V; print(f'BD conservador -> {n} piezas, dejas {(C-n*V)/1e6:.0f} MB libres')"
```

El bloque de diagnóstico completo está en **§11**.
