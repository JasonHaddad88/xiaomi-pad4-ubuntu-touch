# Clover DTB with PSCI OS-initiated idle (installed 2026-11-05)

`sda660-xiaomi-clover-osi.dtb` (md5 `2203a1086efbbe23a1418538e903c6ab`) is
the installed r100 DTB (md5 `09cbe8593dcb380def237a495b1265e1`) with only the
idle description changed:

1. Corrected PSCI parameters, from clover's Android `qcom,lpm-levels`: core
   retention `0x00000002` (was `0x40000002`); L2 dynamic retention / retention /
   power collapse `0x41000023/33/43` (was `0x400000f2/f3/f4`).
2. A hierarchical PSCI topology: `power-domain-cpu-*` per core under
   `power-domain-cluster-perf` / `-pwr`; cluster states as
   `domain-idle-state`; CPUs keep only their two core states with
   `power-domains = <&CPU_PD>, <&apc_cprh N>` and names `"psci", "cpr"`.

How it was made from the installed DTB:

```sh
dtc -I dtb -O dts -o r100.dts r100.dtb
# step 1: the eight arm,psci-suspend-param values (see ../README.md)
python3 make-osi-dts.py idle-android.dts osi.dts    # step 2
dtc -I dts -O dtb -o osi.dtb osi.dts
```

## Installed how

```sh
cp -p /boot/dtbs/qcom/sda660-xiaomi-clover.dtb{,.r100-orig}   # backup
cp -p /boot/boot.img{,.r100-orig}                              # backup
install -m 0644 osi.dtb /boot/dtbs/qcom/sda660-xiaomi-clover.dtb
mkinitfs        # rebuilds boot.img and flashes boot (flash_kernel_on_update)
```

New `boot.img` md5 `2e67904b830712944933fb3b7166636c`, equal to the partition.
Its kernel is byte-identical to r100's (Image.gz md5
`3e5c432a94ef5d93a845b290554f6793`). The command line is unchanged; the
initramfs was regenerated.

The kernel package is pinned, so no update overwrites this file. If the kernel
is ever rebuilt, carry these DT changes into the source; otherwise the new
package's DTB brings back the rejected states (the guard service then covers
it).

## Undo

```sh
sudo cp -p /boot/dtbs/qcom/sda660-xiaomi-clover.dtb.r100-orig /boot/dtbs/qcom/sda660-xiaomi-clover.dtb
sudo mkinitfs
```

or from fastboot: `fastboot flash boot backups/gpu-opp-2026-11-02/installed-r100-boot.img`.
