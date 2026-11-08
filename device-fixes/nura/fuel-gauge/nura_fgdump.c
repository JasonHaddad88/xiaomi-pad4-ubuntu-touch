// SPDX-License-Identifier: GPL-2.0-only
/*
 * nura_fgdump: read-only dump of the PMI8998/PM660 fuel gauge SRAM.
 *
 * Debug aid for clover: shows whether a battery profile is loaded in the
 * gauge (profile at SRAM word 24, 224 bytes; integrity byte at word 79,
 * byte 3) without the mainline pmi8998_fg driver having to grow SRAM
 * support first. It never writes SRAM: it uses the IMA (interleaved memory
 * access) read sequence of the downstream fg-memif.c, single-word mode.
 *
 * debugfs: /sys/kernel/debug/nura_fgdump/sram   words 0..127, one per line
 */
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>
#include <linux/seq_file.h>

#define MEM_IF_INT_RT_STS	0x10
#define MEM_IF_MEM_INTF_CFG	0x50
#define MEM_IF_IMA_CTL		0x51
#define MEM_IF_IMA_OPR_STS	0x54
#define MEM_IF_IMA_EXP_STS	0x55
#define MEM_IF_FG_BEAT_COUNT	0x57
#define MEM_IF_IMA_ERR_STS	0x5f
#define MEM_IF_ADDR_LSB		0x61
#define MEM_IF_RD_DATA0		0x67

#define MEM_ACCESS_REQ_BIT	BIT(7)
#define IACS_SLCT_BIT		BIT(5)
#define IMA_CTL_MASK		GENMASK(7, 6)
#define IACS_RDY_BIT		BIT(1)
#define BEAT_COUNT_MASK		GENMASK(3, 0)

#define NUM_WORDS		128
#define RETRIES			5

static struct regmap *map;
static u16 mem_if;
static struct dentry *dir;
static DEFINE_MUTEX(lock);

static int rd(u16 reg, u8 *val)
{
	unsigned int v;
	int rc = regmap_read(map, mem_if + reg, &v);

	*val = v;
	return rc;
}

static int wait_iacs_ready(void)
{
	int tries = 250;
	u8 sts = 0;
	int rc;

	usleep_range(30, 35);
	while (tries--) {
		rc = rd(MEM_IF_IMA_OPR_STS, &sts);
		if (rc)
			return rc;
		if (sts & IACS_RDY_BIT)
			return 0;
		usleep_range(5000, 7000);
	}
	pr_err("nura_fgdump: IACS_RDY not set, opr_sts 0x%02x\n", sts);
	return -EBUSY;
}

/* One SRAM word, IMA single mode, read only. */
static int read_word(u8 word, u8 *buf)
{
	u8 addr[2] = { word, 0 }, beat0, beat1, exp, err;
	int rc, rc2, i, tries;

	for (tries = 0; tries < RETRIES; tries++) {
		u8 cfg;

		/* someone else (the FG driver) mid-transaction? wait, as downstream does */
		for (i = 0; i < 5; i++) {
			rc = rd(MEM_IF_MEM_INTF_CFG, &cfg);
			if (rc)
				return rc;
			if (!(cfg & MEM_ACCESS_REQ_BIT))
				break;
			usleep_range(4000, 4100);
		}
		if (cfg & MEM_ACCESS_REQ_BIT)
			return -EBUSY;

		rc = regmap_update_bits(map, mem_if + MEM_IF_MEM_INTF_CFG,
					MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT,
					MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT);
		if (rc)
			return rc;
		/* read access, single (not burst) mode */
		rc = regmap_update_bits(map, mem_if + MEM_IF_IMA_CTL, IMA_CTL_MASK, 0);
		if (!rc)
			rc = wait_iacs_ready();
		if (!rc)
			rc = regmap_bulk_write(map, mem_if + MEM_IF_ADDR_LSB, addr, 2);
		if (!rc)
			rc = wait_iacs_ready();
		if (!rc)
			rc = rd(MEM_IF_FG_BEAT_COUNT, &beat0);
		for (i = 0; !rc && i < 4; i++)
			rc = rd(MEM_IF_RD_DATA0 + i, &buf[i]);
		if (!rc)
			rc = rd(MEM_IF_IMA_EXP_STS, &exp);
		if (!rc)
			rc = rd(MEM_IF_IMA_ERR_STS, &err);
		if (!rc)
			rc = wait_iacs_ready();
		if (!rc)
			rc = rd(MEM_IF_FG_BEAT_COUNT, &beat1);

		/* always release IMA access */
		rc2 = regmap_update_bits(map, mem_if + MEM_IF_MEM_INTF_CFG,
					 MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT, 0);
		if (rc)
			return rc;
		if (rc2)
			return rc2;
		if (exp || err) {
			pr_warn("nura_fgdump: word %u IMA exp 0x%02x err 0x%02x\n",
				word, exp, err);
			return -EIO;
		}
		if ((beat0 & BEAT_COUNT_MASK) == (beat1 & BEAT_COUNT_MASK))
			return 0;
	}
	return -EAGAIN;
}

static int sram_show(struct seq_file *s, void *unused)
{
	u8 buf[4];
	int w, rc;

	mutex_lock(&lock);
	for (w = 0; w < NUM_WORDS; w++) {
		rc = read_word(w, buf);
		if (rc) {
			seq_printf(s, "word %3d: error %d\n", w, rc);
			break;
		}
		seq_printf(s, "word %3d: %02x %02x %02x %02x\n",
			   w, buf[0], buf[1], buf[2], buf[3]);
	}
	mutex_unlock(&lock);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(sram);

static int __init nura_fgdump_init(void)
{
	struct device_node *np;
	struct platform_device *pdev;
	const __be32 *reg;

	np = of_find_compatible_node(NULL, NULL, "qcom,pmi8998-fg");
	if (!np)
		return -ENODEV;
	reg = of_get_address(np, 0, NULL, NULL);
	pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!reg || !pdev)
		return -ENODEV;
	map = dev_get_regmap(pdev->dev.parent, NULL);
	put_device(&pdev->dev);
	if (!map)
		return -ENODEV;
	/* FG peripherals: BATT_SOC at base, MEM_IF at base + 0x400 */
	mem_if = be32_to_cpu(*reg) + 0x400;
	pr_info("nura_fgdump: MEM_IF at 0x%04x\n", mem_if);

	dir = debugfs_create_dir("nura_fgdump", NULL);
	debugfs_create_file("sram", 0400, dir, NULL, &sram_fops);
	return 0;
}

static void __exit nura_fgdump_exit(void)
{
	debugfs_remove_recursive(dir);
}

module_init(nura_fgdump_init);
module_exit(nura_fgdump_exit);
MODULE_DESCRIPTION("Read-only fuel gauge SRAM dump (clover debug)");
MODULE_LICENSE("GPL");
