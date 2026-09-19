# Build environment setup

Two sides:
- **Windows** — `adb`/`fastboot` for talking to & flashing the tablet (USB lives here).
- **WSL2 (Ubuntu)** — the actual Halium/Android build (needs Linux + ext4 + ~150–250 GB).

> Verified on this machine: virtualization is on (`HypervisorPresent: True`), so WSL2 works with
> **no BIOS changes**. 24 cores / 31 GB RAM — plenty.

---

## A. Windows side — adb & fastboot  (Task #2)

Install Google's platform-tools (done together with Claude):
```powershell
winget install --id Google.PlatformTools -e
```
Then, with the tablet connected and **USB debugging** enabled (Developer options):
```powershell
adb devices          # should list the device (authorize the RSA prompt on the tablet)
adb reboot bootloader
fastboot devices     # should list the device in bootloader mode
fastboot getvar all  # dumps partition/variant info (capture this)
```

> ⚠ **2026-06-04 — fastboot driver gap on this PC.** In bootloader mode the tablet shows up as
> `USB\VID_18D1&PID_D00D` with **no driver** (`CM_PROB_FAILED_INSTALL`), so `fastboot` can't see it,
> and no signed driver on hand lists `D00D`. One-time elevated fix (bind **WinUSB** via Zadig):
> see [fastboot-driver-windows.md](fastboot-driver-windows.md) (**Task #7**). adb/Android mode is unaffected,
> so this does **not** block the WSL build (Phases 1–2) — only flashing (Phase 3).

## B. WSL2 + Ubuntu  (Task #4)

**1. Install (elevated PowerShell — "Run as administrator"):**
```powershell
wsl --install -d Ubuntu
```
Reboot if prompted. On first launch, create your UNIX username/password.

**2. Update + base tools (inside Ubuntu):**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git git-lfs curl wget python3 python-is-python3 \
  bc bison build-essential ccache flex g++-multilib gcc-multilib \
  lib32ncurses-dev lib32z1-dev libncurses5 libssl-dev \
  unzip zip rsync openjdk-8-jdk-headless android-sdk-libsparse-utils
```
> The Halium toolchain is picky about host libs; we may use the **Halium build container**
> (Docker) instead so the host distro doesn't matter. We'll decide when we hit Phase 1.

**3. `repo` tool:**
```bash
mkdir -p ~/.bin && curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+x ~/.bin/repo && echo 'export PATH=~/.bin:$PATH' >> ~/.bashrc
```

**4. Work in the Linux home, NOT `/mnt/c`:**
Building on `/mnt/c` (Windows drive) is slow and breaks on case-sensitivity. Use e.g. `~/halium`.
WSL2's ext4 disk grows automatically; ensure ~250 GB free on the Windows drive backing it.

**5. Git identity:**
```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

## C. Flashing across the WSL2/Windows boundary
WSL2 has no native USB passthrough. Two options:
- **Simple:** build in WSL2 → copy `*.img` to Windows → flash with Windows `fastboot`.
- **Integrated:** attach the USB device to WSL2 with [`usbipd-win`](https://github.com/dorssel/usbipd-win)
  (`winget install usbipd`), then `usbipd attach --busid <id> --wsl`.

We'll default to the **simple** option for first boots.

---

### Checklist
- [ ] `adb devices` lists the tablet
- [ ] `fastboot devices` lists it in bootloader
- [ ] WSL2 Ubuntu installed; `repo` on PATH; build deps installed
- [ ] ~250 GB free for the source tree
