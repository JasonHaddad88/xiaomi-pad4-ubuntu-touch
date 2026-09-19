# Fixing the Windows fastboot driver (clover `18D1:D00D`)

## Symptom
In **bootloader / fastboot mode**, the tablet enumerates as `USB\VID_18D1&PID_D00D`
("Android Bootloader Interface") and shows **`CM_PROB_FAILED_INSTALL`** in Device Manager — so
`fastboot devices` is empty and no `fastboot` command works. (adb in normal Android mode is
unaffected and works fine.)

## Why
`D00D` is the generic ID Xiaomi's bootloader presents, and **no signed driver on hand lists it**:
- Google USB Driver r13 (downloaded to `tools/google-usb-driver/`) — lists many `18D1` PIDs but **not** `D00D`.
- Motorola `android_winusb.inf` already in the Windows driver store (`oem14.inf`) — Motorola VIDs only.

So there's nothing for Windows to auto-bind; you can't just "install the driver." You bind a **WinUSB**
driver to that specific interface. This is a **one-time, elevated** action and is **not needed until we
flash (Phase 3)** — the WSL build phases never touch fastboot.

## Fix A — Zadig  (recommended; staged at `tools/zadig-2.9.exe`)
1. Put the tablet in bootloader mode: `adb reboot bootloader` (from Android), or hold Power + Vol-Down.
2. Run **`tools/zadig-2.9.exe` as Administrator**.
3. Menu **Options → List All Devices**.
4. In the dropdown pick the entry whose USB ID is **`18D1 D00D`** ("Android" / "Android Bootloader Interface").
5. Set the target driver to **WinUSB** → **Replace Driver**.
6. Verify: `fastboot devices` lists `XXXXXXXX`, then capture:
   `fastboot getvar all`, `fastboot getvar unlocked`, `fastboot oem device-info`.

The binding persists, so future fastboot sessions just work.

## Fix B — patch the Google INF  (no extra tool, but needs signature-enforcement off)
1. Copy `tools/google-usb-driver/usb_driver/android_winusb.inf`; under `[Google.NTamd64]` add:
   `%SingleBootLoaderInterface% = USB_Install, USB\VID_18D1&PID_D00D`
2. Reboot Windows into **Disable driver signature enforcement** (Shift→Restart → Troubleshoot →
   Advanced options → Startup Settings → 7). Editing the INF breaks its signed catalog, hence this step.
3. Device Manager → the "Android" error device → **Update driver → Browse** → point at the patched folder.

## Notes
- The definitive **bootloader-unlock** check lives here too: `fastboot getvar unlocked` → expect
  `unlocked: yes`. Live PE13 props report "locked", but that's almost certainly Play-Integrity spoofing
  (an *unofficial* PE13 can't boot on a genuinely locked bootloader).
- Also yields the **physical partition sizes** (`fastboot getvar all`) that PE13's user build won't let
  a normal adb shell read.
- Tracked as **Task #7** (blocks **Task #1**). Only affects fastboot mode — adb/Android mode is fine.
