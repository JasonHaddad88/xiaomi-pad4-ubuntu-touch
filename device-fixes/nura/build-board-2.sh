#!/bin/sh
# Build an ath10k board-2.bin for clover from the tablet's OWN calibration data.
#
# WHY: the chip reports qmi-board-id 0xff, which means "unprogrammed". ath10k
# looks up calibration keyed on that value, finds only an empty placeholder in
# the stock board-2.bin, and reports:
#
#     ath10k_snoc: board_file api 2 bmi_id N/A crc32 00000000
#     ath10k_snoc: invalid MAC address; choosing random
#     ath10k_snoc: failed to set 2g txpower 40: -108
#     ath10k_snoc: firmware crashed! ... device successfully recovered
#
# With no calibration the firmware dies as soon as TX power is set, which is why
# Wi-Fi could scan but never associate.
#
# Installing the vendor BDF as board.bin does NOT work: for WCN3990 ath10k never
# falls back to the api-1 path (its hw_params lacks the board-file fields), so it
# simply logs no board_file line at all. It has to be a real board-2.bin.
#
# The BDF is device-signed and must come off THIS tablet's vendor partition.
# That partition is untouched by both Ubuntu Touch and Nura.
set -e

WORK=${WORK:-./board-build}
mkdir -p "$WORK" && cd "$WORK"

echo "1. take the device's own board data"
echo "   from Ubuntu Touch:  /android/vendor/firmware_mnt/image/bdwlan.bin"
echo "   from Nura:          /run/msm-firmware-loader/mnt/vendor/firmware_mnt/image/bdwlan.bin"
[ -f bdwlan.bin ] || { echo "   put bdwlan.bin here first (19152 bytes, md5 f62287d7861bf68f0f2a425b4d6a3ce3)"; exit 1; }

echo "2. fetch Qualcomm's encoder"
[ -f ath10k-bdencoder ] || curl -fsSLO \
  https://raw.githubusercontent.com/qca/qca-swiss-army-knife/master/tools/scripts/ath10k/ath10k-bdencoder

echo "3. map it to the names ath10k generates for this chip"
cat > board.json <<'JSON'
[
  {
    "names": [
      "bus=snoc,qmi-board-id=ff",
      "bus=snoc,qmi-board-id=ff,qmi-chip-id=30214",
      "bus=snoc,qmi-board-id=255"
    ],
    "data": "bdwlan.bin"
  }
]
JSON

echo "4. build and verify"
python3 -I ath10k-bdencoder --create board.json
python3 -I ath10k-bdencoder --info board-2.bin

echo
echo "Install to, in the Nura rootfs:"
echo "    /lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin"
echo
echo "Expected on the next boot:"
echo "    ath10k_snoc: board_file api 2 bmi_id N/A crc32 380d3b6d"
echo "  (380d3b6d is the CRC of this tablet's BDF; a non-zero value is the point)"
