# Libertine on clover — how to run desktop Linux apps, and how to fix it yourself

Written for this device (Xiaomi Mi Pad 4, Ubuntu Touch 24.04 / noble, Halium 9). Everything here was
verified on the tablet, including the failures.

## The mental model

Libertine is **not** a VM or an emulator. It is a second Ubuntu root filesystem in a folder. Apps from
it run as ordinary processes on the same kernel, isolated with `bubblewrap` (`bwrap`), and their X11
windows are displayed into Lomiri through XMir.

```
Lomiri (the phone UI)
  └─ libertine-launch  →  bwrap sandbox  →  /usr/bin/vlc   (a real arm64 ELF binary)
                            ↑ "/" inside the sandbox is the container folder, not the system
```

Consequences worth internalising:

- **Fast**, because nothing is emulated — same CPU, same kernel.
- **No GPU access** inside the container, so rendering is software. Fine for Remmina, office, 2D.
  Not fine for 3D or smooth 1080p video.
- **Touch becomes mouse emulation.** Desktop toolbars at 283 ppi are fiddly with a finger; a USB-C
  keyboard/mouse changes the experience completely.
- **The container cannot damage the system.** Worst case, destroy and recreate it.

## Where everything lives

| path | what it is |
|---|---|
| `~/.cache/libertine-container/clover/rootfs` | the entire Ubuntu 24.04 filesystem (its own `/usr`, `/etc`, `apt`) |
| `~/.local/share/libertine-container/user-data/clover` | the container's **private home** |
| `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Music`, `~/Videos` | bind-mounted **into** the container |

**The practical rule:** container apps only see files in those five folders. A file elsewhere in your
home is invisible to VLC or Remmina. (The `ct` helper deliberately breaks this rule — see below.)

`clover` is just the container's id — the name chosen when it was created.

## Everyday commands

```bash
# what containers exist, and what apps are in one
libertine-container-manager list
libertine-container-manager list-apps -i clover

# install / remove software
libertine-container-manager install-package -i clover -p remmina
libertine-container-manager remove-package  -i clover -p vlc

# run something by hand (useful for seeing error output)
libertine-launch -i clover vlc

# start over: removes the container only, nothing else on the device
libertine-container-manager destroy -i clover
```

Creating one from scratch (this is what was run here):

```bash
libertine-container-manager create -i clover -n "Desktop Apps" -t chroot
```

`-t chroot` matters. The alternative, `-t lxd`, needs LXD which is not available on this port. Chroot
type works everywhere.

**App IDs are mechanical:** `clover_vlc_0.0` = `<container>_<desktop-file-name>_<version>`. That is
the identifier Lomiri uses to launch it.

## The three real failures, and what they teach

### 1. Installed apps do not appear in the app drawer

They were installed and registered correctly the whole time. **Lomiri enumerates apps at session
start**, and it had been running 24 minutes before the container was created
(`lomiri started 20:51:46` vs `container created 21:15:07`). It simply never looked again.

**Fix: reboot** (or restart the session). Before concluding anything is broken, compare those two
timestamps:

```bash
ps -o lstart= -p $(pgrep -x lomiri | head -1)
stat -c %y ~/.cache/libertine-container/clover
```

### 2. `E: Unable to correct problems, you have held broken packages`

Seen when installing calibre. It looks like a missing repository; it is not. UBports pins
**everything** from its own repo above the Ubuntu archive:

```
Package: *
Pin: origin repo.ubports.com
Pin-Priority: 2000
```

UBports ships **Qt 6.8.2**, while archive apps such as calibre require `qt6-base-abi (= 6.4.2)`. With
UBports always winning, that dependency can never be satisfied.

**Fix — pin Qt back down, inside the container only:**

```bash
sudo tee ~/.cache/libertine-container/clover/rootfs/etc/apt/preferences.d/99-qt6.pref <<'EOF'
Package: libqt6* qt6-*
Pin: origin repo.ubports.com
Pin-Priority: 100
EOF
```

Expect this with any archive Qt6 application. It does not affect the phone UI — only the container.

### 3. Firefox and Chromium cannot be installed at all

On Ubuntu 24.04 both are **snap transitional packages**:

```
firefox:  Candidate: 1:1snap1-0ubuntu5
          Description: Transitional package - firefox -> firefox snap
```

Snaps require systemd, which the container does not have (there is no `snap` binary in it). Mozilla's
own apt repo is no help either — it has **no arm64** (`binary-arm64/Packages.gz` → HTTP 404).

**Browsers that genuinely work** (real `.deb`s, arm64, no third-party repo):

| package | engine | note |
|---|---|---|
| `epiphany-browser` | WebKitGTK | lightest, most touch-tolerant |
| `falkon` | Qt WebEngine | closest to a conventional desktop browser |
| `qutebrowser` | Qt WebEngine | keyboard-driven |
| `konqueror` | KDE | heavy |

Brave also works, because it is the one mainstream browser still publishing arm64 `.deb`s — but it
needs its own apt repo added inside the container, and Chromium's sandbox needs `--no-sandbox` in a
chroot, which is a real security trade-off.

## The `ct` helper — container tools in the terminal

Installed at `~/.local/bin/ct` (already on `PATH`). Why it exists: the Ubuntu Touch rootfs is
read-only with ~1.3 GB free, **and its apt has no Ubuntu package indexes** — only the UBports repo,
about 3,385 package names. That is why `sudo apt install git` on the host fails with
`Unable to locate package git`: a missing index, not a missing repo, and `/var/lib/apt/lists` sits on
the read-only filesystem. The container, by contrast, has the whole archive and 38 GB to play with.

```bash
ct                       # a bash shell inside the container
ct git status            # git, operating on your real files, in the current directory
ct sudo apt install tmux # install anything from the Ubuntu archive
```

It is Libertine's own `bwrap` invocation with **one deliberate change**:

```bash
exec bwrap \
  --bind "$C" /                                  # container folder becomes /
  --dev-bind /dev /dev                           # real devices
  --proc /proc  --ro-bind /sys /sys
  --tmpfs /run                                   # fresh /run, not the host's
  --ro-bind /etc/resolv.conf /etc/resolv.conf    # so DNS works
  --bind "$HOME" "$HOME"                         # ← THE CHANGE: real home, not the private one
  --chdir "$D" \
  fakeroot "$@"
```

Libertine binds the container's *private* home, which is correct for GUI apps but useless for a
shell — `git` would commit into a sandbox nobody else can see. Binding the real `$HOME` makes the
container's toolchain work on actual files. `fakeroot` is needed because the container's `apt`
expects to be root.

## Gotchas

- **One apt operation at a time.** Two `install-package` runs collide on the dpkg lock. If one is
  interrupted, repair with:
  ```bash
  sudo chroot ~/.cache/libertine-container/clover/rootfs dpkg --configure -a
  ```
- **`gcc`/`make` are not installed** by default. `ct sudo apt install build-essential` (~200 MB) adds
  a full toolchain — the host has no compiler at all, so this is the way to build anything on-device.
- **Size:** base container ~1.3 GB; with Remmina + VLC ~1.9 GB. It lives on `/userdata`, so it
  survives OS updates, unlike anything installed into the read-only rootfs.
- **Watch what apt says it will use** before big installs (`After this operation, X will be used`).
  Calibre wanted 898 MB and 255 packages, largely because it drags in Qt6, Python and a compiler.

## Undo everything

```bash
libertine-container-manager destroy -i clover
rm ~/.local/bin/ct
```

That reclaims the space and leaves no trace on the system.
