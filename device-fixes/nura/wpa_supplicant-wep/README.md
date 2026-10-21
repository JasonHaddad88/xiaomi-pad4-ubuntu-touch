# wpa_supplicant with WEP re-enabled, for Nura on clover

The owner's home network (`Blink7183AD`) is **WEP-only** — the router offers nothing else.
Alpine's `wpa_supplicant` cannot connect to it, so on a stock Nura install the tablet is
locked out of the only network at its location. This package fixes that.

## Why the stock package cannot do it

`wpa_supplicant` 2.10 moved WEP behind a build-time option and **turned it off by default**.
It is not a runtime setting: with `CONFIG_WEP` unset the WEP key-management code is not
compiled in at all. NetworkManager detects this through the capability list the daemon
advertises on D-Bus and refuses the profile before it ever reaches the radio:

```
Connection activation failed: no suitable device found for this connection
(wpa_supplicant does not support WEP encryption)
```

Nothing in NetworkManager, `nmcli`, or the connection profile can work around that. The
daemon has to be rebuilt.

### A trap worth recording

`strings /usr/bin/wpa_supplicant | grep wep_key0` **returns matches even when WEP is
compiled out**, because the config-file parser's key table and its format strings survive
regardless. During this work that output was twice mistaken for proof of support. It is not
evidence of anything. The only trustworthy test is an actual association — see *Verifying*
below.

## Building

Alpine's `wpa_supplicant` lives in `main`, which pmaports does not carry, so it is staged as
a local override in the pmaports tree:

```sh
cd ~/.local/var/pmbootstrap/cache_git/pmaports
mkdir -p temp/wpa_supplicant && cd temp/wpa_supplicant
# the 10 files of main/wpa_supplicant from the aports mirror:
#   APKBUILD config wpa_cli.{confd,initd,sh} wpa_supplicant.{confd,initd} and the 3 patches
```

Then the two edits (both captured in this directory):

1. append the block in `config.wep-addition` to `config` — that is just `CONFIG_WEP=y`
   plus the explanation of why;
2. set `pkgrel=99` in `APKBUILD`, so the local build outranks the repository package and
   `apk` will not quietly replace it on the next upgrade.

Build with:

```sh
pmbootstrap --no-cross build wpa_supplicant
```

**`--no-cross` is required, and it is a global flag — it goes before `build`, not after.**
Without it the cross build dies in link-time optimisation:

```
cc: fatal error: '-fuse-linker-plugin', but liblto_plugin.so not found
```

`crossdirect` runs the host compiler against target sysroot libraries, and the host's LTO
plugin is not loadable in that mix. `--no-crossdirect` is **not** a valid flag; `--no-cross`
is the one that exists.

## Installing

The four built packages are in [`apk/`](apk/) with checksums. Only the first two are needed;
Nura uses systemd, so `-openrc` is inert.

```sh
# from the host, over the network
scp apk/wpa_supplicant-2.11-r99.apk apk/wpa_supplicant-systemd-2.11-r99.apk user@<tablet>:/tmp/
# on the tablet
sudo apk add --allow-untrusted /tmp/wpa_supplicant-2.11-r99.apk \
                               /tmp/wpa_supplicant-systemd-2.11-r99.apk
sudo systemctl restart wpa_supplicant
```

Confirm with `apk info -vv | grep '^wpa_supplicant'` — both should read `2.11-r99`.

## Verifying

Only a real association proves anything. Activating the WEP profile moves the tablet off
whatever network your shell is arriving on, so run it as a self-healing script rather than
interactively — on failure it must put you back:

```sh
nmcli connection up home          # the WEP profile
sleep 10
if nmcli -t -f DEVICE,CONNECTION device | grep -q '^wlan0:home$'; then
    echo WEP_OK
else
    nmcli connection up "<your hotspot>"   # keep the shell alive
fi
```

**Losing the shell is the success signal.** If WEP works the tablet leaves the hotspot and
never comes back; if it fails, the fallback reconnects it and reports the error. Probe from
the host for longer than `nmcli connection up`'s own ~90 s timeout plus the fallback, or a
still-blocked `nmcli` looks identical to success.

Verified on 22 October 2026: the tablet associated with `Blink7183AD` and held the
connection, with working DNS and browsing.

## Keeping it

`pkgrel=99` is what stops an upgrade clobbering this. If Alpine ever ships a 2.12 the local
package stays pinned at 2.11 — rebuild against the new version rather than letting `apk`
pull the WEP-less one in.

## A caution about the network itself

WEP is broken encryption; a passer-by can recover the key in minutes. This package exists
because the network is the one available at the device's location, not because WEP is safe.
Replacing the router with anything offering WPA2 removes the need for all of the above.
