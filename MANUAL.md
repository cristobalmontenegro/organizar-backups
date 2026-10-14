# Manual de usuario — `backup.sh`

Manual de **uso diario** del sistema de respaldo de `servidor-produccion`.

- Complementa al `DISENO.md` (documento de **diseño**: hallazgos, arquitectura, changelog).
- Este manual responde a «**¿cómo hago X?**»; el DISENO responde a «**¿por qué se hizo así?**».

| | |
|---|---|
| **Sistema desplegado en** | `servidor-produccion` → `~/sistema/backup.sh` |
| **Máquina que ejecuta** | `usuario@servidor-produccion` (servidor 45) |
| **Datos que respalda** | `/mnt/DATOS/quemar/<PERFIL>/` |
| **Origen (copia pull)** | Servidor 14 → `10.0.0.14:/mnt/bak/` |
| **Salida** | sets `.rar`/`.7z` troceados a 98 M para quemar en Blu-ray (BD25) |
| **Última actualización** | 2026-10-13 |

> **Regla de oro:** el sistema arranca siempre en **modo SECO** (dry-run). Nada toca
> disco hasta que tú activas el **modo REAL**. Si dudas, mira la cabecera: siempre
> muestra la línea `ejecución: SECO (dry-run…)` o `REAL (¡EJECUTA DE VERDAD!)`.

---

## Índice

1. [Qué hace el sistema](#1-qué-hace-el-sistema)
2. [Antes de empezar](#2-antes-de-empezar)
3. [Modos: SECO/REAL y FRENTE/FONDO](#3-modos-secoreal-y-frentefondo)
4. [El menú interactivo](#4-el-menú-interactivo)
5. [Referencia de comandos](#5-referencia-de-comandos)
6. [Conceptos clave](#6-conceptos-clave)
7. [Flujo diario típico](#7-flujo-diario-típico)
8. [El pull desde el Servidor 14](#8-el-pull-desde-el-servidor-14)
9. [Configuración: interruptores y filtros](#9-configuración-interruptores-y-filtros)
10. [Añadir y quitar carpetas a respaldar](#10-añadir-y-quitar-carpetas-a-respaldar)
11. [Segundo plano (pull y procesar) y cron](#11-segundo-plano-pull-y-procesar-y-cron)
12. [Manifiesto, verificación y borrado](#12-manifiesto-verificación-y-borrado)
13. [Avisos por correo](#13-avisos-por-correo)
14. [Problemas frecuentes](#14-problemas-frecuentes)
15. [Glosario](#15-glosario)

---

## 1. Qué hace el sistema

`backup.sh` reemplaza a los 26 scripts antiguos. Para **cada carpeta a respaldar**
(lo que llamamos *perfil*) hace, en este orden:

```
 preflight  → comprueba que hay espacio en disco para la salida estimada
 limpiar    → borra basura según política (papelera, versiones, duplicados, vídeos, música…)
 empaquetar → crea el set comprimido y troceado (piezas de 98 M)
 verificar  → rar t / 7z t + guarda .sha256 del set
 borrar     → borra la fuente ya verificada (deja sólo los sets listos para quemar)
```

Después, **tú quemás los sets a Blu-ray con k3b (manual)**. El sistema no quema.

Lo importante:

- **No pierde datos por diseño:** sólo borra la fuente si el set **verificó** y
  quedó el `.sha256`. Si algo falla, **no borra** y te avisa.
- **Reanudable:** un set con `.sha256` no se vuelve a verificar; se reutiliza.
- **Por unidad:** en perfiles grandes (p. ej. RESMAIL, un juego por buzón) procesa
  **unidad a unidad**: empaqueta → verifica → borra esa unidad → pasa a la
  siguiente. Así el disco se va liberando sobre la marcha (evita el ENOSPC clásico).

---

## 2. Antes de empezar

### Dónde está

```bash
cd ~/sistema          # en servidor-produccion
./backup.sh           # abre el menú interactivo (comando por defecto)
./backup.sh ayuda     # lista todos los comandos
```

### Qué necesita tener instalado

- `jq`, `rsync`, `ssh`, `find`, `sha256sum` (base).
- Un empaquetador: **`rar`** o **`7z`** (se elige solo: `rar` si existe, si no `7z`).
- Opcional para avisos: `msmtp` + `notificaciones/enviar-correo.sh`.

### Ficheros del sistema

| Fichero | Qué es |
|---|---|
| `backup.sh` | Lanzador y menú. |
| `perfiles.json` | Catálogo de **perfiles** (carpetas) y parámetros globales. |
| `lib/*.sh` | Módulos internos (no se editan a mano salvo que sepas lo que haces). |
| `estado/` | `modo` (seco/real), `plano` (frente/fondo), `ciclo`, `bg-procesar.json` / `bg-pull.json` (progreso en vivo). |
| `logs/` | Registros de ejecución. |
| `perfiles.json.bak` | Copia automática antes de cada cambio de configuración. |

> **Nunca edites `perfiles.json` a mano** salvo que sea imprescindible. Hay comandos
> y menús para todo (`configurar`, `perfil-nuevo`, `perfil-quitar`, `descubrir`).
> Si lo editas a mano, el sistema te avisa con **`configurar validar`**.

---

## 3. Modos: SECO/REAL y FRENTE/FONDO

El sistema tiene **dos modos globales independientes**, cada uno en su fichero:

| Modo | Fichero | Valores | Qué significa |
|---|---|---|---|
| **Ejecución** | `estado/modo` | SECO / REAL | ¿dry-run o de verdad? |
| **Plano** | `estado/plano` | FRENTE / FONDO | ¿espera en consola o se va a segundo plano? |

**Ejecución (SECO/REAL):**

| Modo | Qué hace |
|---|---|
| **SECO** (por defecto) | *dry-run*. **Imprime lo que haría, pero no toca nada.** |
| **REAL** | **Ejecuta de verdad**: empaqueta, verifica y **borra la fuente**. |

**Plano (FRENTE/FONDO):**

| Plano | Qué hace |
|---|---|
| **FRENTE** (por defecto) | `pull` y `procesar` **esperan en consola** hasta terminar. |
| **FONDO** | `pull` y `procesar` **se van solos a segundo plano**; puedes seguir usando el menú. |

> El plano sólo afecta a **`pull` y `procesar`** (y a las opciones **4** y **5** del
> menú), que son los que pueden tardar horas. Las fases sueltas (`limpiar`,
> `empaquetar`, `verificar`) siempre van en primer plano.

### Cómo se cambian

- **En el menú:** opción **`0`** abre el submenú de modos (cambia ambos).
  - Pasar a REAL: te pide que escribas la palabra **`real`** (confirmación explícita).
  - Pasar a FONDO: es inmediato (y viceversa).
- **Por comando:**
  - `--real` fuerza REAL **sólo** para esa orden.
  - `--fondo` / `--frente` fuerzan el plano **sólo** para esa orden.

```bash
./backup.sh procesar RESMAIL           # respeta el modo y el plano guardados
./backup.sh procesar RESMAIL --real    # fuerza REAL aunque el modo sea SECO
./backup.sh procesar RESMAIL --fondo   # fuerza segundo plano aunque el plano sea FRENTE
```

> **Consejo:** trabaja siempre primero sin `--real` para ver el plan, y cuando te
> cuadre, repite con `--real`.

---

## 4. El menú interactivo

`./backup.sh` (o `./backup.sh menu`) abre el menú. La cabecera muestra siempre:
ciclo, raíz, espacio libre, medio, volumen, **ejecución** (SECO/REAL) y **plano**
(FRENTE/FONDO).

| Op | Acción | Qué hace |
|:--:|---|---|
| **0** | Modos | Submenú: cambia ejecución (SECO/REAL) y plano (FRENTE/FONDO). |
| **1** | Listar perfiles | Tabla: tamaño, nº de archivos, origen en el S14 y destino. |
| **2** | Preflight | Espacio **libre vs. necesario** (salida estimada) de cada perfil. |
| **3** | Ver origen en el S14 | Muestra de dónde sale la data de un perfil. |
| **4** | Pull desde el S14 | Trae los datos del perfil desde el servidor 14 (sigue el plano). |
| **5** | Procesar | `limpiar + empaquetar + verificar + borrar` (sigue el plano). |
| **6** | Avance | Estado en vivo de los trabajos de fondo (perfil, fase y **%**). |
| **7** | Verificar | Integridad (`sha256`) de los juegos ya empaquetados. |
| **8** | Manifiesto | Recibo CSV de lo quemado en el ciclo. |
| **9** | Configurar | Submenú de interruptores y parámetros. |
| **10** | Carpetas | Añadir/quitar perfiles y **descubrir** carpetas nuevas. |
| **11** | Ayuda | Comandos no interactivos. |
| **X** | Salir | |

> **4 y 5 "van como esté el plano":** en FRENTE esperan delante; en FONDO se lanzan
> solos y vuelves al menú. No hay una opción aparte de "segundo plano".

Muchas opciones abren un **selector de perfil** (`all` = todos). Escribe el número
o el nombre; `Enter`/`X` cancela.

---

## 5. Referencia de comandos

Forma general:

```bash
./backup.sh <comando> [PERFIL|all] [opciones]
```

### Sólo lectura (nunca toca nada)

| Comando | Para qué |
|---|---|
| `listar` | Perfiles, tamaños, origen y destino. |
| `origen <PERFIL>` | De dónde sale la data + destino local. |
| `ciclos` | Ciclo vigente y ruta del manifiesto. |
| `preflight <PERFIL>\|all` | Espacio disponible vs. salida estimada. |

### Fases (respetan modo y plano; `--real` / `--fondo` los fuerzan)

| Comando | Para qué |
|---|---|
| `limpiar <PERFIL> [--real]` | Sólo la limpieza (basura, papelera, duplicados…). |
| `empaquetar <PERFIL> [--real]` | Sólo crear los sets. |
| `pull <PERFIL> [--hoy=AAAA-MM-DD] [--real]` | Traer datos del S14 (sigue el plano). |
| `procesar <PERFIL> [--real]` | **El flujo completo** (sigue el plano). |
| `verificar <PERFIL>` | Re-prueba los juegos ya empaquetados. |

> `pull` y `procesar` siguen el **plano global**: en FRENTE esperan, en FONDO se van
> a segundo plano. `--frente` / `--fondo` lo fuerzan para una orden concreta.

### Segundo plano (locks separados: pull y procesar no se estorban)

| Comando | Para qué |
|---|---|
| `fondo-iniciar <PERFIL> [--real]` | Lanza el **procesado** de fondo (lock + log). |
| `pull-fondo <PERFIL> [--real]` | Lanza el **pull** de fondo. |
| `fondo <PERFIL> [--real]` | Worker del procesado (lo lanza `fondo-iniciar`). |
| `fondo-pull <PERFIL> [--real]` | Worker del pull (lo lanza `pull-fondo`). |
| `avance` | Estado en vivo de **ambos** trabajos (perfil, fase, % o "transfiriendo"). |
| `cron` | Imprime la receta para el `crontab`. |

### Consultas y configuración

| Comando | Para qué |
|---|---|
| `manifiesto [PERFIL\|all]` | MANIFIESTO.csv del ciclo. |
| `configurar ver <PERFIL>` | Tabla de interruptores. |
| `configurar validar` | Comprueba que todos los perfiles están completos. |
| `configurar` | Submenú de edición (guarda con `.bak`). |

### Carpetas

| Comando | Para qué |
|---|---|
| `perfil-nuevo <NOMBRE> [--origen RUTA_S14 \| --manual] [--como PERFIL]` | Añade una carpeta/perfil. |
| `perfil-quitar <PERFIL>` | Quita la **definición** (NUNCA borra datos). |
| `descubrir [listar]` | Lista carpetas sin perfil y (asistente) las añade. |
| `carpetas` | Submenú de carpetas/perfiles. |

### Ejemplos

```bash
./backup.sh listar                          # ver el panorama
./backup.sh preflight all                   # ¿cabe todo?
./backup.sh procesar RESMAIL                # plan (en SECO)
./backup.sh procesar RESMAIL --real         # ejecutar de verdad
./backup.sh pull RESINTRANET --hoy=2026-10-13 --real
./backup.sh pull-fondo RESINTRANET --real   # pull en segundo plano
./backup.sh fondo-iniciar RESINTRANET --real # procesar en segundo plano
./backup.sh avance                          # mirar cómo va (ambos trabajos)
./backup.sh verificar RESODOO               # re-chequear
./backup.sh manifiesto all                  # recibo del ciclo
```

---

## 6. Conceptos clave

### Perfil

Una **carpeta a respaldar**, con nombre en MAYÚSCULAS (`RESMAIL`, `RESINTRANET`…).
Cada perfil define **su propia política** (¿comprimir? ¿borrar vídeos? ¿por usuario?).
El destino es siempre `$RAIZ/<PERFIL>/` (por defecto `/mnt/DATOS/quemar/<PERFIL>/`).

### Contenedor (carpeta fechada)

Con `carpeta_fecha: true`, los datos viven dentro de una subcarpeta **`AAAA-MM-DD/`**:

```
/mnt/DATOS/quemar/RESMAIL/2026-10-13/
```

Esa carpeta es la **unidad de restauración** (y de procesado). Los sets se crean *dentro*.

### Juego / set

El resultado de empaquetar un contenedor (o un usuario, o un buzón):

```
RESMAIL_2026-10-13.rar        ← primera pieza
RESMAIL_2026-10-13.r00        ← siguientes piezas (98 M cada una)
RESMAIL_2026-10-13.sha256     ← huella del set
```

> El **`.sha256`** es el marcador de *«set verificado»*. Su presencia significa:
> ya se probó y está listo para quemar; **no se vuelve a verificar**.

### Unidad

La mínima porción que se procesa de una vez:

- Perfil normal: el contenedor completo.
- `por_usuario: true`: **un usuario** (nunca se mezclan usuarios).
- Buzones (RESMAIL): **un buzón**.

En **REAL**, `procesar` cierra **unidad a unidad**: empaqueta → verifica → **borra esa
unidad** → siguiente. Así se libera disco sobre la marcha.

### Ciclo

Etiqueta del «lote» actual (por defecto, la fecha de hoy). Agrupa los sets en el
manifiesto y en `quemados/<ciclo>/`.

### Manifiesto

`MANIFIESTO.csv`, el **recibo** de todo lo verificado en el ciclo: ciclo, fecha,
perfil, juego, nº de volúmenes, bytes, sha256 y estado (`OK`).

---

## 7. Flujo diario típico

### 7.1 Respaldo local (ya tienes los datos en `quemar/`)

```bash
cd ~/sistema

./backup.sh preflight all        # 1) ¿hay espacio?  (mira la columna ESTADO)
./backup.sh listar               # 2) ¿qué hay?      (origen/destino por perfil)
./backup.sh procesar RESMAIL     # 3) plan en SECO
./backup.sh procesar RESMAIL --real   # 4) ejecutar
./backup.sh manifiesto RESMAIL   # 5) recibo
```

Luego quema los sets de `/mnt/DATOS/quemar/RESMAIL/...` con **k3b**.

### 7.2 Con pull desde el servidor 14

```bash
./backup.sh origen RESMAIL                       # ver de dónde viene
./backup.sh pull RESMAIL --real                  # traer (crea AAAA-MM-DD/)
./backup.sh procesar RESMAIL --real              # limpiar+empaquetar+verificar+borrar
```

> `pull` deja los datos en el contenedor de **hoy**; `procesar` los empaqueta.
> Puedes forzar el contenedor con `--hoy=AAAA-MM-DD`.
> El `pull` puede tardar horas si son varios GB: usa el plano FONDO (opción 0) para
> que se haga solo, o `pull-fondo RESMAIL --real`.

### 7.3 Perfil largo (RESMAIL, RESINTRANET)

La forma cómoda: pon el **plano en FONDO** (menú, opción 0 → 2) y lanza con 4/5
normalmente; se van solos. O directamente por comando:

```bash
./backup.sh pull-fondo RESINTRANET --real   # pull en segundo plano
./backup.sh fondo-iniciar RESINTRANET --real # procesar en segundo plano
./backup.sh avance                           # seguir el % (ambos trabajos)
```

### 7.4 Todo de golpe

```bash
./backup.sh procesar all --real
```

`all` **omite** los perfiles sin datos y los que ya están procesados (con `.sha256`).

---

## 8. El pull desde el Servidor 14

`pull` trae los datos del **Servidor 14** (`10.0.0.14:/mnt/bak/<origen>`)
al destino local, con `rsync`.

- El origen de cada perfil está en `perfiles.json` → clave **`origen_s14`**
  (ruta **relativa** a `/mnt/bak`). Vacío/`null` + `fuente: manual` = no hay pull.
- Excluye automáticamente basura (`pull_excluir` global): `.trash`, `files_trashbin`,
  `lost+found`, `.DS_Store`, `Thumbs.db`, `desktop.ini`…
- Respeta los filtros **`incluir`/`excluir`** del perfil (ver §9).
- Con `carpeta_fecha: true`, deja los datos en `<PERFIL>/AAAA-MM-DD/`.

```bash
./backup.sh pull RESMAIL                 # SECO: muestra el rsync que haría
./backup.sh pull RESMAIL --real          # trae de verdad
./backup.sh pull RESINTRANET --hoy=2026-10-12 --real
```

> **Antes de un pull grande, comprueba `preflight`**: el pull ocupa disco antes de
> empaquetar. Si no cabe, el sistema te lo dirá.

---

## 9. Configuración: interruptores y filtros

### 9.1 Los dos ámbitos

- **De carpeta** (obligatorios, **sin herencia**): cada perfil **debe** definirlos.
  Son: `comprimir`, `empaquetar`, `trocear_grandes`, `carpeta_fecha`, `por_usuario`,
  `borrar_papelera`, `borrar_versiones`, `borrar_duplicados`, `borrar_vacios`,
  `borrar_fotos`, `borrar_videos`, `borrar_musica`, `borrar_instaladores`,
  `borrar`, `conservar`, `store`.
- **Operativos** (heredan de `global`, pueden faltar): `compresion`, `integridad`,
  `volumen`, `aire_porcentaje`, `medio`, `correo`, `verificar_antes_de_borrar`,
  `empaquetador`, `factor_salida`.
- **Opcionales** (filtros, vacíos = sin filtro): `incluir`, `excluir`.

### 9.2 Catálogo de interruptores

| Clave | Qué hace |
|---|---|
| `comprimir` | `false` = **store** (`-m0`): no re-comprime, sólo trocea (ya venía comprimido). |
| `empaquetar` | `true` = crea sets; `false` = no crea sets (tal cual, o troceo por archivo). |
| `trocear_grandes` | `true` = parte en piezas de `<volumen>`. Con `empaquetar=false` → **troceo por archivo**: parte **en el sitio** cada archivo > 98 M (borra el original tras verificar). |
| `carpeta_fecha` | Envuelve en subcarpeta `AAAA-MM-DD` (unidad de restauración). |
| `por_usuario` | Un juego **por usuario**; nunca se mezclan. |
| `borrar_papelera` | Borra `files_trashbin`, `.trash`. |
| `borrar_versiones` | Borra `files_versions` (versiones previas de Nextcloud). |
| `borrar_duplicados` | Deduplica archivos idénticos (dentro del mismo usuario). |
| `borrar_vacios` | Borra carpetas/archivos vacíos. |
| `borrar_fotos` | Borra `.jpg .jpeg .png .heic .webp`. |
| `borrar_videos` | Borra vídeo no empresarial (`.mp4 .avi .mov .mkv …`). |
| `borrar_musica` | Borra música (`.mp3 .wma .wav .flac …`). |
| `borrar_instaladores` | Borra `.iso .msi .exe .img`. |
| `borrar` | Lista de extensiones a eliminar. |
| `conservar` | **Nunca** se borran, aunque estén en `borrar`. |
| `store` | Extensiones que se archivan **sin comprimir** (`-ms`). |

### 9.3 Ver y editar

```bash
./backup.sh configurar ver RESMAIL     # tabla de interruptores
./backup.sh configurar validar         # ¿están completos todos los perfiles?
./backup.sh configurar                 # submenú de edición
```

Submenú `configurar`:

1. Ver la configuración de un perfil
2. Editar un interruptor de un perfil
3. Editar la configuración **global** (operativa)
4. Completar perfil desde la plantilla (sólo lo que falta)
5. Comprobar que todos los perfiles están completos
6. Quitar un interruptor operativo (vuelve a heredar de global)
7. Volver

Cada cambio guarda una copia previa en `perfiles.json.bak`.

### 9.4 Filtros `incluir` / `excluir` (filtrado de subcarpetas)

Sirven para respaldar **sólo una parte** de una carpeta.

- **`excluir`** = «todo **menos** X». Nunca se descarga, ni se empaqueta, ni se
  borra, ni se limpia.
- **`incluir`** = «**sólo** X» (todo lo demás se ignora).
- Los patrones son **glob**, **relativos a la carpeta que se empaqueta**, y se
  aplican en el **primer nivel** del contenedor. Una carpeta que coincide **excluye
  todo su contenido**.

Se respetan en **pull y empaquetado** (y por tanto en borrado/limpieza/troceo).

**Ejemplos**

Sólo el buzón `contabilidad` (y nada más):

```json
"incluir": ["contabilidad"]
```

Todo menos las carpetas de prueba y los `.pst`:

```json
"excluir": ["pruebas", "temp", "*.pst"]
```

> Vacío = comportamiento clásico (se respalda todo, sin filtros). No rompe nada.

---

## 10. Añadir y quitar carpetas a respaldar

**No hace falta editar el JSON a mano.** Tres caminos:

### 10.1 Añadir una carpeta concreta (`perfil-nuevo`)

```bash
# desde el plantilla, con origen en el S14 (activa pull)
./backup.sh perfil-nuevo RESINVENTO --origen INVENTO

# sin pull (datos puestos a mano en $RAIZ/RESINVENTO/)
./backup.sh perfil-nuevo RESINVENTO --manual

# copiando los interruptores de otro perfil que ya funciona
./backup.sh perfil-nuevo RESINVENTO --origen INVENTO --como RESMAIL
```

- El **nombre** debe ser `MAYÚSCULAS`, números y `_` (ej. `RESINVENTO`).
- Con `--origen RUTA`, la ruta es **relativa a `/mnt/bak`** del S14. El sistema
  comprueba (si hay SSH) que exista y te avisa si no.
- **No borra ni crea datos**; sólo añade la definición.

### 10.2 Descubrir carpetas nuevas (`descubrir`)

Lista carpetas que **no tienen perfil** (en el S14 y en local) y, en modo
interactivo, **ofrece crearlas** (asistente):

```bash
./backup.sh descubrir listar    # sólo mostrar
./backup.sh descubrir           # asistente (pregunta carpeta a carpeta)
```

El asistente te pregunta, por cada candidata: ¿crear perfil?, nombre, ¿copiar
interruptores de otro perfil?, y el origen.

### 10.3 Quitar un perfil (`perfil-quitar`)

```bash
./backup.sh perfil-quitar RESVIEJO
```

- Quita **sólo la definición** del JSON. **La carpeta de datos NO se toca.**
- Es reversible volviendo a crearlo con `perfil-nuevo`.

### 10.4 Menú interactivo

`./backup.sh carpetas` (o menú opción **10**) reúne todo lo anterior:
listar, añadir, quitar, descubrir.

---

## 11. Segundo plano (pull y procesar) y cron

Hay **dos trabajos de fondo independientes**: **pull** y **procesar**. Cada uno con
su propio lock, estado y log, así que **no se estorban** entre sí.

Dos formas de lanzarlos:

**a) Poniendo el plano en FONDO** (menú, opción 0 → 2). A partir de ahí, `pull` y
`procesar` (y las opciones 4/5) se van solos.

**b) Por comando, explícito** (para perfiles que tardan mucho: RESMAIL, RESINTRANET):

```bash
./backup.sh pull-fondo   RESINTRANET --real   # pull en segundo plano
./backup.sh fondo-iniciar RESINTRANET --real  # procesar en segundo plano
./backup.sh avance                            # estado de AMBOS trabajos
```

| Trabajo | Lock | Estado | Log |
|---|---|---|---|
| procesar | `estado/bg-procesar.lock` | `estado/bg-procesar.json` | `logs/bg-procesar.log` |
| pull | `estado/bg-pull.lock` | `estado/bg-pull.json` | `logs/bg-pull.log` |

- **`avance`** muestra los dos si están activos: el procesado con barra y **%**;
  el pull como **"transfiriendo…"** (no produce sets que contar).
- **Perfiles de troceo por archivo** (p. ej. RESINTRANET): durante el troceo la barra
  de sets no se movería, así que `avance` muestra en su lugar
  `X de Y archivos grandes (N piezas · Z pendientes)` con la barra real del troceo.
- Fases del % del procesado: `preflight 1 → limpiar 3 → empaquetar 5 → verificar 93 → borrado 97 → fin 100`.
- Si intentas lanzar un trabajo del mismo tipo ya activo, te avisa y lo rechaza.

Receta de `crontab`:

```bash
./backup.sh cron      # imprime la línea lista para pegar en crontab -e
```

---

## 12. Manifiesto, verificación y borrado

### Manifiesto

```bash
./backup.sh manifiesto all            # todo el ciclo
./backup.sh manifiesto RESMAIL
./backup.sh ciclos                    # ciclo vigente + ruta del CSV
```

Ruta: `.../quemados/<ciclo>/MANIFIESTO.csv`. Es el **recibo** para saber qué se
quemó (juego, volúmenes, tamaño, sha256).

### Verificación

```bash
./backup.sh verificar RESMAIL
```

Prueba los sets ya empaquetados (`rar t` / `7z t`) y compara el `.sha256`.
Un set con `.sha256` **no se re-verifica** durante el procesado normal.

### Borrado de la fuente

No hay que invocarlo a mano: `procesar --real` lo hace **unidad a unidad**,
**sólo tras verificar**. Salvaguardas:

- Nunca toca los sets (`<PERFIL>_*`) ni los `.sha256`.
- Nunca borra la raíz del perfil entera (conserva los juegos).
- Si la verificación falla → **no borra** y avisa.

---

## 13. Avisos por correo

Al terminar (o fallar) un `procesar --real`, el sistema envía un correo a los
destinatarios de `global.correo` (por defecto `admin@ejemplo.com`).

- Requiere `msmtp` y `notificaciones/enviar-correo.sh`.
- Sin correo configurado o sin `msmtp`, avisa **en consola** y sigue.
- `RESPALDO_VERBOSE=1` imprime el HTML del aviso cuando no hay correo.

```bash
RESPALDO_VERBOSE=1 ./backup.sh procesar RESMAIL --real
```

---

## 14. Problemas frecuentes

**«NO ALCANZA» en preflight**
No hay espacio para la salida estimada. Libera disco, quema/procesa perfiles ya
listos, o procesa un perfil más pequeño primero.

**«ya procesado, se omite»**
El perfil tiene todos sus sets con `.sha256`. No hay nada que hacer. Para
re-chequear: `./backup.sh verificar <PERFIL>`.

**Un perfil «sin datos»**
`/mnt/DATOS/quemar/<PERFIL>/` no existe o está vacío. Si debe tener datos, revisa
el `origen_s14` y haz `pull`.

**Parece que no hace nada**
Estás en **modo SECO**. Comprueba la cabecera (`ejecución: SECO…`) o pasa a REAL
(menú opción 0, escribiendo `real`).

**Lanzo y vuelve enseguida sin trabajar**
Estás en **plano FONDO**: el trabajo se fue a segundo plano. Míralo con `avance`
(menú opción 6). Si lo querías delante, cambia a FRENTE (opción 0) o usa `--frente`.

**«ya hay un procesar/pull en segundo plano activo»**
Ya hay un trabajo de ese tipo corriendo (pull y procesar son independientes). Mira
`avance` o espera a que termine.

**El pull no trae nada**
Perfil sin `origen_s14` (es manual), ruta mal escrita, o SSH al S14 caído.
Comprueba con `./backup.sh origen <PERFIL>`.

**Quiero ver qué haría sin ejecutar**
Ejecuta sin `--real` (estás en SECO). Todas las fases imprimen su plan.

**Falta un interruptor en un perfil**
`./backup.sh configurar validar` te lo dice; `configurar` → opción **4** lo completa
desde la plantilla.

---

## 15. Glosario

| Término | Significado |
|---|---|
| **Perfil** | Carpeta a respaldar (`RESMAIL`, `RESINTRANET`…). |
| **Contenedor** | Subcarpeta `AAAA-MM-DD/` con los datos de una tanda. |
| **Set / juego** | Piezas `.rar`/`.7z` + `.sha256` de un contenedor. |
| **Unidad** | Lo mínimo que se procesa de una vez (contenedor, usuario o buzón). |
| **`.sha256`** | Marca de «set verificado, listo para quemar». |
| **Store** | Comprimir sin recomprimir (`-m0`): sólo trocear. |
| **Troceo por archivo** | `empaquetar=false` + `trocear_grandes=true`: parte en el sitio cada archivo > 98 M. |
| **Ciclo** | Lote actual (por defecto, la fecha). |
| **Manifiesto** | Recibo CSV de lo verificado/quemado en el ciclo. |
| **Pull** | Copiar datos desde el Servidor 14 al destino local. |
| **Modo SECO / REAL** | Dry-run / ejecución de verdad. |
| **Plano FRENTE / FONDO** | Esperar en consola / irse a segundo plano. |
| **BG (bg-procesar / bg-pull)** | Los dos trabajos de fondo, con lock y estado propios. |
