# Fuel gauge on clover: the wrong battery profile is loaded

Date: 2026-11-08. Kernel: r101 (unchanged). All steps so far were read-only.

## Symptom

- While charging, the displayed charge runs ahead of the real one.
- Unplugged at 80 %, the reading dropped straight to 65 %.
- The charge-limit/bypass work (r103) was reverted because of this (see
  `device-fixes/nura/charge-control/README.md`).

## What the gauge holds

The PM660 fuel gauge (FG gen3, mainline driver `pmi8998_fg`) keeps a battery
profile in its SRAM:

- the profile: 224 bytes from word 24
- the integrity byte: word 79, byte 3

Mainline has no SRAM access, so a small read-only debug module was written:
`device-fixes/nura/fuel-gauge/nura_fgdump.c`.

- It uses the downstream IMA single-word read sequence and never writes.
- It was built into a debug-only kernel package (r104, not installed).
- It was loaded with `insmod`, dumped words 0–127 without an error, and was
  then removed.

The dump was taken on 2026-11-08 at 96 % on the charger. It is kept locally in
`backups/fg-2026-11-08/sram-dump.txt` (it is not in git) and is the restore
point if the profile is ever rewritten.

### Integrity byte

The integrity byte reads `0x03`: a profile is loaded, and the bootloader loaded
it (`PROFILE_LOAD_BIT | BOOTLOADER_LOAD`).

### Profile comparison

The scripts are `compare-profile.py` and `compare-profile-fields.py`. They
compare the profile in SRAM against the two profiles in the Android device
tree.

| Profile | Nominal capacity (word 58) | First 148 bytes vs SRAM |
|---|---|---|
| In the gauge SRAM (bootloader) | **2879 mAh** | – |
| `zql5018_battery_feimaotui_6000mah` | 5978 mAh | 95 bytes differ |
| `zql6019_battery_8600mah` | 8682 mAh | 91 bytes differ |

The curves have a similar shape, since the high bytes often match. But the
loaded profile belongs to some other battery of roughly half the capacity.

### Battery ID

`pm660-rradc` `in_resistance0_raw` reads 424.

- At 150 µA the reading would be out of range, so the driver uses the 15 µA
  source.
- Resistance = 424 × 2500 mV / (1024 × 15 µA) ≈ **69 kΩ**.

The Android battery data gives:

- `zql5018`: `batt-id-kohm` = 68
- `zql6019`: `batt-id-kohm` = 200

So the battery is the **zql5018 6000 mAh** pack. That matches the mainline DT's
`charge-full-design` of 6010000 µAh.

## Conclusion

On every boot the bootloader loads a generic profile of about 2.9 Ah. Android
then replaced it: its FG node sets `qcom,fg-force-load-profile`, and
`qpnp-fg-gen3` loads the zql5018 profile and restarts the gauge.

Mainline never does that, so the gauge runs on the wrong model.

- While charging, the coulomb count is measured against about half the real
  capacity, so the percentage rises too fast.
- At rest, the voltage-based estimate pulls it back down. That is the
  80 → 65 % drop on unplug.

## Next step: profile loader (needs the owner's go-ahead)

The loader would port the downstream `qpnp-fg-gen3` sequence:

1. Compare the 148-byte region. Skip the load if it already matches zql5018.
2. Clear `RESTART_GO` (`BATT_SOC` base + 0x48).
3. Write 224 bytes with the IMA write sequence.
4. Restart the gauge: set GO, wait for SOC ready, clear GO.
5. Set the integrity byte to `HLOS_RESTART | PROFILE_LOAD` (0x09).

Plan:

- Test with `insmod` first. The kernel package and the installed system stay
  unchanged.
- Re-dump the SRAM after the load, and again after a reboot, to see whether
  the bootloader overwrites the profile each boot.
- Restore: write the saved 224 bytes and integrity byte `0x03` back and
  restart the gauge. A full battery disconnect also makes the bootloader
  reload its own profile.
- Charging safety does not depend on the profile. The charger (`qcom_smbx`)
  sets the float voltage and current limits itself.
