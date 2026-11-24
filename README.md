# CR-10 v3 — Klipper en Linux Mint + NAS temporal

Backup de toda la configuración de la máquina **`192.168.100.16`** (Lenovo G560e, Linux Mint 22.3,
`levi-Lenovo-G560e`): firmware de la impresora, Samba/NAS, respaldo a Google Drive y la política
de energía. Si el disco o la config se rompe, este repo es lo que hay que restaurar.

## Hardware

| cosa | detalle |
|---|---|
| PC | Lenovo G560e, 2 núcleos Celeron T3500, 7.7 GiB RAM, WiFi (`wlp4s0`) |
| SO | Linux Mint 22.3 (Zena), base Ubuntu 24.04, kernel x86_64 |
| Disco del sistema | `/dev/sda` SSD 120 GB SATA → `/dev/sda3` ext4 montado en `/` (84 GB libres) |
| Disco NAS | `/dev/sdb` SSD 120 GB por USB (puente ASM1153E) → GPT, `/dev/sdb1` ext4 label `NAS120`, 110 GB, montado en `/nas` |
| MCU impresora | BIGTREE **SKR 2** (`stm32f407xx`) por USB, `idVendor=1d50 idProduct=614e` |
| Ruta serial | `/dev/serial/by-id/usb-Klipper_stm32f407xx_3A002E000547393438343535-if00` |
| impresora | Creality CR-10 V3 (300×300×400, `axis_maximum [290,270,400]` en `printer.cfg`) |

## Stack de impresión

| servicio | unidad | puerto | notas |
|---|---|---|---|
| Klipper | `klipper.service` | socket `/tmp/klippy_uds` | arranca con `enable` (está habilitado) |
| Moonraker | `moonraker.service` | 7125 | API REST + WebSocket |
| Nginx + Mainsail | `nginx.service` | 80 | UI web → `http://192.168.100.16` |
| Samba | `smb.service` / `nmb.service` | 139/445 | shares abajo |
| wsdd | `wsdd.service` | UDP 3702 | hace visible el equipo en "Red" de Windows |

Versiones: Klipper `v0.13.0-707-gf604aeee`, Samba `4.19.5-Ubuntu`, rclone `1.75.1`.
Detalle completo en [`VERSIONES.md`](VERSIONES.md).

## NAS / Samba

`nas/smb.conf` define tres shares, todas con usuario/contraseña (Windows 11 bloquea el acceso
anónimo, así que `guest ok = no`):

| share | ruta en el server | disco | acceso |
|---|---|---|---|
| `[nas]` | `/nas` | SSD externo USB | `levi`, lectura y escritura |
| `[interno]` | `/srv/interno` | partición del sistema | `levi`, lectura y escritura |
| `[gcodes]` | `/home/levi/printer_data/gcodes` | sistema | `levi`, **solo lectura** |

Extras ya aplicados:
- `hide unreadable = yes` en `[global]` (esconde `lost+found`).
- `map to guest = bad user` (default de Ubuntu, se mantiene).
- Usuario Samba `levi` creado con `smbpasswd` (la clave no está en este repo).
- Mapeo en Windows: `Z:` → `\\192.168.100.16\nas`, `Y:` → `\\192.168.100.16\interno`, credencial
  guardada en el Administrador de credenciales (`cmdkey /add:192.168.100.16`).

### Que el SSD externo no se pierda al arrancar

`nas/fstab` tiene la línea de montaje por UUID y **`nofail,x-systemd.device-timeout=30s,noatime`**;
`nas/99-nas-ssd.rules` dispara `nas.mount` cuando el disco vuelve a aparecer por USB.
Se probó a propósito **no** usar `x-systemd.automount`: con autofs, Samba guarda el árbol ya
resuelto y `Z:` queda roto hasta reiniciar `smbd`.

> Si se desconecta el SSD en caliente, `/nas` queda desmontado y `Z:` muestra vacío.
> Recuperación: `sudo mount /nas && sudo systemctl restart smbd`.

## Respaldo de Google Drive

`scripts/gdrive-backup.sh` (instalado en `/usr/local/bin/`) copia las carpetas elegidas del Drive a
`/nas/respaldos/gdrive/<carpeta>`, incremental (`--update`) y excluyendo `**/node_modules/**` y
`**/.git/**` (por la API de Google, miles de archivos chicos cuestan minutos).

`scripts/gdrive-status.sh` (en `/usr/local/bin/gdrive-status.sh`) informa qué está bajando,
porcentaje por carpeta, archivos en vuelo (lee los `.partial` abiertos de rclone), cola pendiente,
velocidad medida sobre el disco y espacio restante.

El token OAuth vive en `/home/levi/.config/rclone/rclone.conf` del server — **nunca subir a git**.

Carpetas respaldadas: `pablo`, `carpetazo`, `Brenda`, `FIEL_VIAL941013337_20250918104913`,
`Documentos`, `usb verde`, `4Geeks Academy Clases ESPAÑOL - latam-pt-44` (~49.8 GB, 2.453 archivos).

## Energía (que no se duerma nunca)

- `nas/logind.conf`: `HandleLidSwitch=ignore`, `HandleLidSwitchExternalPower=ignore`,
  `HandleLidSwitchDocked=ignore`, `IdleAction=ignore`, `IdleActionSec=0`.
- Objetivos enmascarados (imposible de suspender/hibernar, verificado):
  ```
  sudo systemctl mask sleep.target suspend.target hibernate.target \
       hybrid-sleep.target suspend-then-hibernate.target
  ```
- XFCE (`xfconf`, canal `xfce4-power-manager`): `lid-action-on-ac=0`, `lid-action-on-battery=0`,
  `inactivity-on-ac=0`, `inactivity-on-battery=0`, `dpms-enabled=false`.

## Windows de apoyo

`windows/` trae los `.bat` de doble clic: uno dispara el respaldo por SSH y el otro muestra el
estado. Ambos piden la contraseña SSH del server; no guardan credenciales en disco.

## Cómo restaurar en otra máquina

```bash
sudo apt install -y samba wsdd rclone git
# 1) impresora: clonar klipper/moonraker + entornos, o usar kiauh
# 2) copiar configs
sudo cp printer/config/printer.cfg ~/printer_data/config/
sudo cp printer/config/moonraker.conf ~/printer_data/config/
sudo cp systemd/klipper.service systemd/moonraker.service /etc/systemd/system/
# 3) NAS
sudo cp nas/smb.conf /etc/samba/smb.conf
sudo cp nas/99-nas-ssd.rules /etc/udev/rules.d/
sudo cp systemd/wsdd.service /etc/systemd/system/
# agregar la linea de /nas a /etc/fstab (ajustar UUID al disco nuevo)
sudo systemctl daemon-reload && sudo systemctl enable --now smbd nmbd wsdd klipper moonraker nginx
sudo smbpasswd -a levi
# 4) Drive: rclone config (remote "gdrive") y volver a autorizar
```

## Pendientes conocidos

1. **client_id propio de Google Cloud**: el remote usa el client_id compartido de rclone
   (proyecto `202264815644`), que Google está jubilando en 2026 y ya nos dio
   `403 Quota exceeded ... Requests per minute`. Hay que crear uno propio y agregar
   `client_id` / `client_secret` al remote `gdrive`.
2. **338 archivos de `Documentos`** faltan en el NAS (565/903) por un desconectado en caliente del
   SSD; se recuperan re-corriendo el respaldo cuando la API responda.
3. La cuota reportada por Drive (`usageInDrive = 1.35 GB` de 15 GB) no concuerda con los ~50 GB
   respaldados: revisar si esas carpetas viven en un Shared Drive.
4. `printer.cfg` tiene backups históricos en `printer/config/historial/`; el más viejo data de
   2026-09-28.

## Qué NO va en este repo

`~/.config/rclone/rclone.conf` (token OAuth), `/etc/shadow`, `passdb.tdb`, la contraseña Samba,
`moonraker_data/db.json` (API keys) y los logs de `klippy.log`.
