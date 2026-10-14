# 💾 OrganizarBackups

**ES:** Sistema de respaldo, compresión, verificación y quema a discos (Blu-ray / DVD / CD) desde la terminal. Sustituye un enjambre de ~26 scripts `.sh` casi idénticos por **un único `backup.sh`** con menú interactivo, perfiles, filtros, ejecución en segundo plano y avisos por correo.

**EN:** A backup, compression, verification and optical-disc burning system (Blu-ray / DVD / CD) that runs from the terminal. It replaces ~26 near-identical loose `.sh` scripts with **a single `backup.sh`** featuring an interactive menu, profiles, filters, background execution and email notifications.

---

## 🇪🇸 Español

### ✨ ¿Qué hace?

Toma los datos de un directorio de trabajo (`quemar/`), los limpia, los empaqueta en volúmenes (`rar`/`7z`), **verifica su integridad** (`sha256`), y deja el resultado listo para quemar en un medio óptico. Además puede **traer** los datos desde un servidor de origen por SSH (*pull*) antes de procesarlos.

| | |
|:---|:---|
| **Entrada** | `/mnt/DATOS/quemar/<PERFIL>/` (datos puestos a mano o traídos por *pull*) |
| **Salida** | sets `.rar`/`.7z` troceados (p. ej. 98 M) listos para **k3b** |
| **Medio objetivo** | BD25 / BD50 / DVD / CD (configurable por perfil) |

### 🧩 Módulos

| Fichero | Descripción |
|:---|:---|
| `sistema/backup.sh` | Punto de entrada: menú interactivo y comandos no interactivos. |
| `sistema/lib/comunes.sh` | Utilidades, formato humano, barra de progreso, modos globales. |
| `sistema/lib/config.sh` | Lectura/escritura validada de `perfiles.json` (`jq`). |
| `sistema/lib/perfiles.sh` | Alta/baja de perfiles y descubrimiento de carpetas. |
| `sistema/lib/pull.sh` | Copia desde el servidor de origen por `rsync`/SSH, con filtros. |
| `sistema/lib/fases.sh` | Limpiar → empaquetar/trocear → verificar → borrar. |
| `sistema/lib/background.sh` | Ejecución en segundo plano (*frente/fondo*) y estado `avance`. |
| `sistema/lib/manifiesto.sh` | Recibo CSV de lo procesado en el ciclo. |
| `sistema/lib/notify.sh` | Avisos por correo (`msmtp`). |

### ⚙️ Características

- **Perfiles data-driven**: todo se define en `perfiles.json`; añadir o quitar carpetas sin tocar el código.
- **Modos globales**: `SECO/REAL` (simular o ejecutar de verdad) y `FRENTE/FONDO` (primer plano o segundo plano).
- **Filtros `incluir`/`excluir`** por perfil, aplicados tanto al *pull* como al empaquetado.
- **Dos estrategias de troceo**: por volumen (`rar -v98M`) o **por archivo** (parte cada fichero grande; el original se borra solo si el troceado verifica).
- **Borrado seguro**: nunca se borra nada sin verificar antes; todo es **reanudable**.
- **Segundo plano** con *locks* separados (pull y procesar no se estorban) y comando `avance`.
- **Avisos por correo** al terminar o al fallar.

### 🛠 Requisitos

- **Bash** 4+ y utilidades base (`find`, `stat`, `du`, `df`, `sha256sum`, `flock`, `setsid`)
- **`jq`** (imprescindible: lee `perfiles.json`)
- **`rar`** y **`7z`** (`p7zip-full`)
- **`rsync`** y **`openssh-client`** (para el *pull* por SSH)
- *(Opcional)* **`msmtp`** para los avisos por correo
- *(Opcional)* **`fdupes`** para detección de duplicados
- *(Opcional)* **`k3b`** (u otra herramienta) para el quemado final

### 🚀 Cómo empezar

```bash
git clone git@github.com:cristobalmontenegro/organizar-backups.git
cd organizar-backups

# revisa/edita los perfiles antes de nada
$EDITOR sistema/perfiles.json

# lanza el menú (recomendado empezar en modo SECO)
cd sistema
chmod +x backup.sh
./backup.sh
```

Flujo típico (menú):

1. **Preflight** — comprobar espacio libre.
2. **Pull** desde el servidor de origen (si el perfil lo tiene definido).
3. **Procesar** — limpiar + empaquetar + verificar.
4. **Manifiesto** y **quemar** con k3b.

> Empieza siempre en modo **SECO** para ver qué haría sin tocar nada; cuando el plan te cuadre, cambia a **REAL**.

### 📁 Estructura

```text
.
├── sistema/
│   ├── backup.sh            # menú y comandos
│   ├── lib/                 # módulos (ver tabla arriba)
│   ├── perfiles.json        # definición de perfiles (editable)
│   ├── diagnostico/         # script de diagnóstico de la máquina
│   └── pruebas/             # datos sintéticos + stubs para test local
├── notificaciones/          # msmtp + plantilla de correo + instalador
├── legado/                  # los 26 scripts antiguos (solo referencia histórica)
├── test-h12.sh              # batería de pruebas (procesado por unidad)
├── test-filtros.sh          # batería de pruebas (filtros incluir/excluir)
├── MANUAL.md                # manual de usuario (uso diario)
├── DISENO.md                # documento de diseño (por qué se hizo así)
└── LICENSE
```

### 📚 Documentación

| Documento | Para qué |
|:---|:---|
| **[`MANUAL.md`](MANUAL.md)** | Uso diario: menú, comandos, configuración, flujo, problemas frecuentes. |
| **[`DISENO.md`](DISENO.md)** | Diseño del sistema: hallazgos, arquitectura, decisiones y *changelog*. |

### ⚠️ Notas

- Los perfiles incluidos son **ejemplos genéricos**: adáptalos a tus rutas, hosts y usuarios reales.
- El borrado se hace **solo** con rutas exactas y tras verificar; aun así, prueba primero en **SECO**.
- `legado/` se incluye únicamente como referencia histórica; **no** se usa en tiempo de ejecución.

---

## 🇬🇧 English

### ✨ What does it do?

It takes data from a working directory (`quemar/`), cleans it up, packs it into volumes (`rar`/`7z`), **verifies its integrity** (`sha256`), and leaves the result ready to be burned to an optical medium. It can also **pull** the data from a source server over SSH before processing it.

| | |
|:---|:---|
| **Input** | `/mnt/DATOS/quemar/<PROFILE>/` (placed by hand or pulled over SSH) |
| **Output** | chunked `.rar`/`.7z` sets (e.g. 98 M) ready for **k3b** |
| **Target media** | BD25 / BD50 / DVD / CD (configurable per profile) |

### ⚙️ Features

- **Data-driven profiles**: everything lives in `perfiles.json`; add or remove folders without touching the code.
- **Global modes**: `DRY/RUN` (simulate vs. actually run) and `FOREGROUND/BACKGROUND`.
- **`include`/`exclude` filters** per profile, applied to both *pull* and packing.
- **Two chunking strategies**: by volume (`rar -v98M`) or **per file** (splits each big file; the original is deleted only if the split verifies).
- **Safe deletion**: nothing is ever deleted before verification; everything is **resumable**.
- **Background jobs** with separate *locks* (pull and processing don't get in each other's way) plus an `avance` status command.
- **Email notifications** on success or failure.

### 🛠 Requirements

- **Bash** 4+ and base utilities (`find`, `stat`, `du`, `df`, `sha256sum`, `flock`, `setsid`)
- **`jq`** (required: reads `perfiles.json`)
- **`rar`** and **`7z`** (`p7zip-full`)
- **`rsync`** and **`openssh-client`** (for the SSH pull)
- *(Optional)* **`msmtp`** for email notifications
- *(Optional)* **`fdupes`** for duplicate detection
- *(Optional)* **`k3b`** (or another tool) for the final burn

### 🚀 Getting started

```bash
git clone git@github.com:cristobalmontenegro/organizar-backups.git
cd organizar-backups

# review/edit the profiles first
$EDITOR sistema/perfiles.json

# launch the menu (start in DRY mode)
cd sistema
chmod +x backup.sh
./backup.sh
```

Typical flow (menu): **Preflight** → **Pull** → **Process** (clean + pack + verify) → **Manifest** → burn with k3b.

> Always start in **DRY** mode to preview what it would do; switch to **RUN** once you're happy.

### 📁 Layout

```text
.
├── sistema/
│   ├── backup.sh            # menu and commands
│   ├── lib/                 # modules (see table above)
│   ├── perfiles.json        # profile definitions (editable)
│   ├── diagnostico/         # machine diagnostic script
│   └── pruebas/             # synthetic data + stubs for local tests
├── notificaciones/          # msmtp + mail template + installer
├── legado/                  # the original 26 scripts (historical reference only)
├── test-h12.sh              # test suite (per-unit processing)
├── test-filtros.sh          # test suite (include/exclude filters)
├── MANUAL.md                # user manual (daily use)
├── DISENO.md                # design document (rationale)
└── LICENSE
```

### 📚 Documentation

| Document | Purpose |
|:---|:---|
| **[`MANUAL.md`](MANUAL.md)** | Daily use: menu, commands, configuration, flow, FAQ. |
| **[`DISENO.md`](DISENO.md)** | System design: findings, architecture, decisions and changelog. |

### ⚠️ Notes

- The bundled profiles are **generic examples**: adapt them to your own paths, hosts and users.
- Deletion is done **only** with exact paths and after verification; still, test in **DRY** mode first.
- `legado/` is included as historical reference only; it is **not** used at runtime.

---

## ☕ Apóyame / Support me

**ES:** Si esta herramienta te resultó útil, puedes invitarme un café. ¡Gracias!
**EN:** If this tool was useful, you can buy me a coffee. Thanks!

<a href="https://ko-fi.com/cristobalmontenegro" target="_blank">
  <img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi6.png?v=6" border="0" alt="Buy Me a Coffee at ko-fi.com" />
</a>

## 📄 Licencia / License

**ES:** Publicado bajo la licencia MIT. **EN:** Released under the MIT License.

Consulta [`LICENSE`](LICENSE) · See [`LICENSE`](LICENSE).
