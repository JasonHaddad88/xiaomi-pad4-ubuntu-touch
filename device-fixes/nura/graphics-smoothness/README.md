# Interface smoothness on clover (installed 2026-11-13)

## Result

Measured with `bench.py`, a GTK4 list that scrolls itself. Normal governors
(GPU `simple_ondemand`, CPU `schedutil`), run as a normal app.

| Test | Before | After |
|---|---|---|
| Continuous scroll, 8 s (480 frames possible) | 206 frames, 39 ms mean | **476 frames, 16.8 ms mean** |
| 12 flicks after 1.2 s idle (504 frames possible) | 227 frames, 38 ms mean | **471 and 487 frames, about 17.5 ms mean** |

The kernel is unchanged (r101). Nothing packaged was edited: four new files.

## What was wrong

It was not frequency scaling. With the GPU pinned at 588 MHz and every CPU at
its maximum, the same list still ran at about 27 frames per second, and the app
used only 22 % of one core.

A trace of GPU submits and page flips showed the time goes into the GPU jobs:

| GPU job, at 588 MHz | ms per frame |
|---|---|
| GTK4 app, default (tiled rendering, GMEM) | 25.6 |
| GTK4 app, `FD_MESA_DEBUG=sysmem` | 19.5 |
| GTK4 app, `sysmem` + `GSK_GPU_DISABLE=gradients` | **10.5** |
| phoc (compositor), default (GMEM) | **4.3** |
| phoc with `sysmem` | 7.8 |

- One frame has 16.7 ms for the app and the compositor together. 25.6 + 4.3 ms
  cannot fit; 10.5 + 4.3 ms does.
- At 30 frames per second the frames also arrived unevenly: two flips 16.7 ms
  apart, then a 50 ms gap. That looks worse than a steady 30.
- `sysmem` helps the GTK4 apps but hurts phoc, so the two need different
  settings.
- `gradients` stops GTK4 from supersampling gradients. Screenshots with and
  without the new settings look the same.

What remained after that was a hitch at the start of each flick: the CPU
frequency ramps up too slowly from idle. A CPU utilisation floor (`uclamp.min`)
for the compositor, the shell and the apps removes it:

| 12 flicks, new graphics settings | Frames of 504 |
|---|---|
| No floor | 415 to 448 |
| Floor 25 % | 448 |
| Floor 37.5 % | 474 |
| Floor 50 % | 487 |
| Everything pinned at maximum | 494 |

## Tried, no gain

- **GPU minimum frequency** (160, 266, 370 MHz): no gain; 160 MHz was worse.
- **Large pages for GPU buffers** (`shmem_enabled=always`): no change in GPU
  job time. Set back to `never`.
- **Other `GSK_GPU_DISABLE` flags** (`occlusion`, `uber`, `clear,blit`,
  `mipmap`, `repeat`, `to-image`): no change. `merge` doubles the job time.
- **`GSK_RENDERER=cairo`:** slower (51 ms per frame).
- **`FD_MESA_DEBUG`** without `noblit`, with `gmem`, with `nobin`: no gain;
  `nobin` is slower.
- **The memory bus:** not starved. The interconnect is at maximum and a core
  copies 5.3 GB/s.

One open oddity: GPU job time scales with frequency from 160 to 465 MHz, but
the 588 MHz step is 2.3 times faster than 465 MHz for the app (1.26 expected).
Below 588 MHz the list runs at 5 to 13 frames per second.

## Installed files

| File on the tablet | Purpose | md5 |
|---|---|---|
| `/etc/profile.d/zz-nura-graphics.sh` | sets the app settings below the wrapper; points `PHOSH_SESSION_BIN` at the wrapper | `5ad7a8d295946e1899c40fe663fa1691` |
| `/usr/local/bin/nura-session` | wrapper around `gnome-session`; marks the shell and apps with `NURA_SESSION=1` | `15a09b992e3d07dd84761786d26b2901` |
| `/usr/local/sbin/nura-ui-boost` | writes `cpu.uclamp.min` for phoc's session scope, `session.slice` (50 %) and `app.slice` (37.5 %) | `b96930ef5be6328604a4163226774648` |
| `/etc/systemd/system/nura-ui-boost.service`, `.timer` | runs the script 25 s after boot and every 60 s | |

How the settings reach the right processes:

- `phosh-session` starts `phoc -E "$PHOSH_SESSION_BIN --session=phosh"`. phoc
  itself keeps `FD_MESA_DEBUG=noblit` from the packaged
  `sdm660-adreno-quirks.sh`.
- `nura-session` exports `NURA_SESSION=1` and runs `gnome-session`.
- `gnome-session` reads `/etc/profile` again, which would reset
  `FD_MESA_DEBUG`. So the profile script, not the wrapper, sets
  `FD_MESA_DEBUG=noblit,sysmem` and `GSK_GPU_DISABLE=gradients` when
  `NURA_SESSION` is set.
- The profile script only points at the wrapper if the wrapper is executable,
  so a missing wrapper cannot break the login.
- A cgroup's `cpu.uclamp.min` is capped by its parents, so the script sets the
  whole chain from `user.slice` down. systemd does not manage that attribute.
  The session scope gets a new name at every login, hence the timer.

## Undo

```sh
sudo rm /etc/profile.d/zz-nura-graphics.sh /usr/local/bin/nura-session
sudo systemctl disable --now nura-ui-boost.timer
sudo rm /usr/local/sbin/nura-ui-boost /etc/systemd/system/nura-ui-boost.service /etc/systemd/system/nura-ui-boost.timer
sudo reboot
```

## Cost and limits

- **Power:** the floor only acts while an interface task is running, and then
  the CPU runs at 1.1 to 1.8 GHz or more instead of ramping up from 300 MHz.
  Idle and suspend are unaffected. Not yet measured on battery.
- **Headroom:** app plus compositor now use about 15 of the 16.7 ms per frame
  at 588 MHz. Heavier pages than the test list will still drop frames.
- **Scope:** the settings reach GTK4 apps started from the shell. GTK3 apps
  and Flatpak apps were not measured.
- **The Software app** has its own stalls (icon decoding); those are separate.

## Measuring again

- `bench.py [bursts] [label] [burst seconds]`: run it in the session; it prints
  one JSON line. With no burst length it does 0.7 s flicks after 1.2 s idle.
- `gpuscale.sh <ENV> <MHz...>`: pins the GPU frequency, runs the bench and
  prints the GPU time per job for the app and for phoc from the
  `msm_gpu_submit` and `msm_gpu_submit_retired` trace events.
- Never read `/sys/kernel/debug/dri/*/gpu` on this tablet: it froze it on
  2026-11-12.
