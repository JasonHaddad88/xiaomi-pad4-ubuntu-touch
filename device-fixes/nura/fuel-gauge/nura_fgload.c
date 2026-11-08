// SPDX-License-Identifier: GPL-2.0-only
/*
 * nura_fgload: battery profile loader for the PM660 fuel gauge (clover).
 *
 * The bootloader leaves a generic ~2.9 Ah profile in the FG SRAM. Android's
 * qpnp-fg-gen3 (qcom,fg-force-load-profile) replaced it with the profile of
 * the fitted pack. This module ports that sequence for testing:
 *
 *   echo check   > /sys/kernel/debug/nura_fgload/control   read-only report
 *   echo load    > /sys/kernel/debug/nura_fgload/control   load zql5018 6000 mAh
 *   echo restore > /sys/kernel/debug/nura_fgload/control   put the bootloader
 *                                                          profile back
 *   cat /sys/kernel/debug/nura_fgload/sram                 words 0..127
 *
 * Load sequence (qpnp-fg-gen3.c profile_load_work):
 *   clear RESTART_GO, write 224 profile bytes from word 24 right after a
 *   SOC_UPDATE interrupt (atomic), restart the FG (set GO, wait SOC_READY,
 *   clear GO), set the integrity byte, then fg_bp_params_config (float
 *   voltage, vbatt_full). SRAM access uses IMA single mode, as on PM660.
 */
#include <linux/completion.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/irq.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>
#include <linux/seq_file.h>
#include <linux/string.h>
#include <linux/uaccess.h>

/* BATT_SOC (FG base) */
#define BATT_SOC_MONOTONIC_SOC	0x09
#define BATT_SOC_RESTART	0x48
#define RESTART_GO_BIT		BIT(0)
/* batt_soc interrupt index (Android DT order) */
#define IRQ_SOC_UPDATE		0
#define IRQ_SOC_READY		1

/* MEM_IF (FG base + 0x400) */
#define MEM_IF_MEM_INTF_CFG	0x50
#define MEM_IF_IMA_CTL		0x51
#define MEM_IF_IMA_CFG		0x52
#define MEM_IF_IMA_OPR_STS	0x54
#define MEM_IF_IMA_EXP_STS	0x55
#define MEM_IF_IMA_HW_STS	0x56
#define MEM_IF_FG_BEAT_COUNT	0x57
#define MEM_IF_IMA_ERR_STS	0x5f
#define MEM_IF_IMA_BYTE_EN	0x60
#define MEM_IF_ADDR_LSB		0x61
#define MEM_IF_ADDR_MSB		0x62
#define MEM_IF_WR_DATA0		0x63
#define MEM_IF_WR_DATA3		0x66
#define MEM_IF_RD_DATA0		0x67
#define MEM_IF_RD_DATA3		0x6a

#define MEM_ACCESS_REQ_BIT	BIT(7)
#define IACS_SLCT_BIT		BIT(5)
#define IMA_WR_EN_BIT		BIT(6)
#define IMA_CTL_MASK		GENMASK(7, 6)
#define IACS_CLR_BIT		BIT(2)
#define STATIC_CLK_EN_BIT	BIT(4)
#define IACS_RDY_BIT		BIT(1)
#define IMA_EXP_ERR_MASK	(BIT(0) | BIT(1) | BIT(3) | BIT(4) | BIT(5) | BIT(7))
#define BEAT_COUNT_MASK		GENMASK(3, 0)

#define NUM_WORDS		128
#define RETRIES			3

/* SRAM layout (qpnp-fg-gen3.c, pmi8998 v2 params) */
#define PROFILE_LOAD_WORD	24
#define PROFILE_LEN		224
#define PROFILE_COMP_LEN	148
#define PROFILE_INTEGRITY_WORD	79
#define PROFILE_INTEGRITY_OFF	3
#define PROFILE_LOAD_BIT	BIT(0)
#define BOOTLOADER_LOAD_BIT	BIT(1)
#define HLOS_RESTART_BIT	BIT(3)
#define NOM_CAP_WORD		58
#define VBATT_FULL_WORD		7	/* 2 bytes, 244.141 uV/LSB */
#define FLOAT_VOLT_WORD		16	/* byte 2, (mV - 2000) / 15.625 */
#define FLOAT_VOLT_OFF		2

#define SOC_UPDATE_WAIT_MS	1500
#define SOC_READY_WAIT_MS	2000

#include "nura_fgload_data.h"

/* zql5018: qcom,max-voltage-uv 4400000 -> (4400 - 2000) * 1000 / 15625 = 153 */
#define ZQL_FLOAT_VOLT		0x99
/* zql5018: qcom,fg-cc-cv-threshold-mv 4390 -> 4390000 * 1000 / 244141 = 17981 */
#define ZQL_VBATT_FULL0		0x3d
#define ZQL_VBATT_FULL1		0x46

static struct regmap *map;
static struct device_node *fg_np;
static u16 fg_base, mem_if;
static struct dentry *dir;
static DEFINE_MUTEX(lock);
static DECLARE_COMPLETION(soc_update);
static DECLARE_COMPLETION(soc_ready);

static int rd(u16 reg, u8 *val)
{
	unsigned int v = 0;
	int rc = regmap_read(map, reg, &v);

	*val = v;
	return rc;
}

static int wr(u16 reg, u8 val)
{
	return regmap_write(map, reg, val);
}

static int mwr(u16 reg, u8 mask, u8 val)
{
	return regmap_update_bits(map, reg, mask, val);
}

/* fg_run_iacs_clear_sequence() */
static int iacs_clear_sequence(void)
{
	u8 hw_sts = 0, exp_sts = 0, val;
	int rc, tries = 250;

	rc = mwr(mem_if + MEM_IF_IMA_CFG, IACS_CLR_BIT | STATIC_CLK_EN_BIT,
		 IACS_CLR_BIT | STATIC_CLK_EN_BIT);
	if (!rc)
		rc = mwr(mem_if + MEM_IF_IMA_CTL, IMA_CTL_MASK, 0);
	if (!rc)
		rc = mwr(mem_if + MEM_IF_MEM_INTF_CFG,
			 MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT,
			 MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT);
	if (rc)
		return rc;
	usleep_range(35, 40);
	while (1) {
		rc = wr(mem_if + MEM_IF_ADDR_MSB, 0);
		if (!rc)
			rc = wr(mem_if + MEM_IF_WR_DATA3, 0);
		if (!rc)
			rc = rd(mem_if + MEM_IF_RD_DATA3, &val);
		if (rc)
			return rc;
		usleep_range(35, 40);
		rc = rd(mem_if + MEM_IF_IMA_HW_STS, &hw_sts);
		if (rc)
			return rc;
		if (hw_sts != 0)
			continue;
		rc = rd(mem_if + MEM_IF_IMA_EXP_STS, &exp_sts);
		if (rc)
			return rc;
		if (exp_sts == 0 || !(--tries))
			break;
	}
	if (!tries)
		pr_err("nura_fgload: IACS clear failed, hw_sts 0x%02x exp_sts 0x%02x\n",
		       hw_sts, exp_sts);
	rc = mwr(mem_if + MEM_IF_IMA_CFG, IACS_CLR_BIT, 0);
	if (rc)
		return rc;
	udelay(5);
	rc = mwr(mem_if + MEM_IF_MEM_INTF_CFG,
		 MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT, 0);
	usleep_range(35, 40);
	pr_info("nura_fgload: IACS clear sequence run\n");
	return rc;
}

/* fg_clear_ima_errors_if_any(chip, false): -EAGAIN after clearing an error */
static int clear_ima_errors(void)
{
	u8 exp_sts, hw_sts, err_sts;
	int rc;

	rc = rd(mem_if + MEM_IF_IMA_EXP_STS, &exp_sts);
	if (!rc)
		rc = rd(mem_if + MEM_IF_IMA_HW_STS, &hw_sts);
	if (!rc)
		rc = rd(mem_if + MEM_IF_IMA_ERR_STS, &err_sts);
	if (rc)
		return rc;
	if (exp_sts & IMA_EXP_ERR_MASK) {
		pr_err("nura_fgload: IMA exception exp 0x%02x hw 0x%02x err 0x%02x\n",
		       exp_sts, hw_sts, err_sts);
		rc = iacs_clear_sequence();
		return rc ? rc : -EAGAIN;
	}
	return 0;
}

static int wait_iacs_ready(void)
{
	int tries = 250, rc;
	u8 sts = 0;

	usleep_range(30, 35);
	while (1) {
		rc = rd(mem_if + MEM_IF_IMA_OPR_STS, &sts);
		if (rc)
			return rc;
		if (sts & IACS_RDY_BIT)
			return 0;
		if (!(--tries))
			break;
		usleep_range(5000, 7000);
	}
	pr_err("nura_fgload: IACS_RDY not set, opr_sts 0x%02x\n", sts);
	rc = clear_ima_errors();
	return rc ? rc : -EBUSY;
}

static int set_address(u8 word)
{
	u8 addr[2] = { word, 0 };

	return regmap_bulk_write(map, mem_if + MEM_IF_ADDR_LSB, addr, 2);
}

/* fg_interleaved_mem_config(): request IMA, single mode */
static int ima_config(u8 word, bool write)
{
	int i, rc;
	u8 cfg = 0;

	for (i = 0; i < 5; i++) {
		rc = rd(mem_if + MEM_IF_MEM_INTF_CFG, &cfg);
		if (rc)
			return rc;
		if (!(cfg & MEM_ACCESS_REQ_BIT))
			break;
		usleep_range(4000, 4100);
	}
	if (cfg & MEM_ACCESS_REQ_BIT)
		return -EBUSY;
	rc = mwr(mem_if + MEM_IF_MEM_INTF_CFG, MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT,
		 MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT);
	if (!rc)
		rc = mwr(mem_if + MEM_IF_IMA_CTL, IMA_CTL_MASK,
			 write ? IMA_WR_EN_BIT : 0);
	if (!rc)
		rc = wait_iacs_ready();
	if (!rc)
		rc = set_address(word);
	if (!rc && !write)
		rc = wait_iacs_ready();
	return rc;
}

static int ima_release(void)
{
	return mwr(mem_if + MEM_IF_MEM_INTF_CFG,
		   MEM_ACCESS_REQ_BIT | IACS_SLCT_BIT, 0);
}

/* fg_interleaved_mem_read(), single mode, one word per transaction */
static int sram_read(u8 word, u8 off, u8 *val, int len)
{
	u8 beat0 = 0, beat1 = 0, buf[4];
	int rc, rc2, i, n, tries;

	while (len > 0) {
		rc = -EAGAIN;
		for (tries = 0; tries < 5 && rc; tries++) {
			rc = ima_config(word, false);
			if (!rc)
				rc = rd(mem_if + MEM_IF_FG_BEAT_COUNT, &beat0);
			for (i = 0; !rc && i < 4; i++)
				rc = rd(mem_if + MEM_IF_RD_DATA0 + i, &buf[i]);
			if (!rc)
				rc = clear_ima_errors();
			if (!rc)
				rc = rd(mem_if + MEM_IF_FG_BEAT_COUNT, &beat1);
			rc2 = ima_release();
			if (!rc)
				rc = rc2;
			if (!rc && (beat0 & BEAT_COUNT_MASK) != (beat1 & BEAT_COUNT_MASK))
				rc = -EAGAIN;
		}
		if (rc)
			return rc;
		n = min(4 - off, len);
		memcpy(val, buf + off, n);
		val += n;
		len -= n;
		off = 0;
		word++;
	}
	return 0;
}

/* fg_interleaved_mem_write() + __fg_interleaved_mem_write(), single mode */
static int __sram_write(u8 word, u8 off, const u8 *val, int len)
{
	u8 byte_en, beat0 = 0, beat1 = 0;
	int rc, rc2, i, n;

	rc = ima_config(word, true);
	if (!rc)
		rc = rd(mem_if + MEM_IF_FG_BEAT_COUNT, &beat0);
	while (!rc && len > 0) {
		n = min(4 - off, len);
		byte_en = 0;
		for (i = off; i < off + n; i++)
			byte_en |= BIT(i);
		rc = wr(mem_if + MEM_IF_IMA_BYTE_EN, byte_en);
		if (!rc)
			rc = regmap_bulk_write(map, mem_if + MEM_IF_WR_DATA0 + off,
					       val, n);
		/* WR_DATA3 starts the transaction; dummy if it is not enabled */
		if (!rc && !(byte_en & BIT(3)))
			rc = wr(mem_if + MEM_IF_WR_DATA3, 0);
		if (!rc)
			rc = clear_ima_errors();
		if (rc)
			break;
		val += n;
		len -= n;
		off = 0;
		if (len) {
			word++;
			rc = set_address(word);
		}
		if (!rc)
			rc = wait_iacs_ready();
	}
	if (!rc) {
		rc = rd(mem_if + MEM_IF_FG_BEAT_COUNT, &beat1);
		if (!rc && (beat0 & BEAT_COUNT_MASK) != (beat1 & BEAT_COUNT_MASK))
			pr_warn("nura_fgload: beat count changed during write (%x/%x)\n",
				beat0, beat1);
	}
	rc2 = ima_release();
	return rc ? rc : rc2;
}

static int sram_write(u8 word, u8 off, const u8 *val, int len)
{
	int rc = -EAGAIN, tries;

	for (tries = 0; tries < RETRIES && rc; tries++) {
		rc = __sram_write(word, off, val, len);
		if (rc)
			pr_warn("nura_fgload: write word %u try %d rc %d\n",
				word, tries, rc);
	}
	return rc;
}

/* ---- batt_soc interrupts, mapped only for the duration of a load ---- */

static irqreturn_t soc_update_irq(int irq, void *data)
{
	complete(&soc_update);
	return IRQ_HANDLED;
}

static irqreturn_t soc_ready_irq(int irq, void *data)
{
	complete(&soc_ready);
	return IRQ_HANDLED;
}

/*
 * The mainline DT lists only soc-delta (batt_soc irq 3). Take its specifier
 * and change the irq index to reach the other batt_soc interrupts.
 */
static int get_batt_soc_irq(int index, irq_handler_t fn, const char *name)
{
	struct of_phandle_args args;
	unsigned int virq;
	int rc;

	rc = of_irq_parse_one(fg_np, 0, &args);
	if (rc)
		return rc;
	if (args.args_count != 4 || args.args[1] != (fg_base >> 8)) {
		pr_err("nura_fgload: unexpected irq specifier (%d cells, periph 0x%x)\n",
		       args.args_count, args.args_count > 1 ? args.args[1] : 0);
		of_node_put(args.np);
		return -EINVAL;
	}
	args.args[2] = index;
	args.args[3] = IRQ_TYPE_EDGE_RISING;
	virq = irq_create_of_mapping(&args);
	of_node_put(args.np);
	if (!virq)
		return -EINVAL;
	rc = request_threaded_irq(virq, NULL, fn, IRQF_ONESHOT, name, NULL);
	if (rc) {
		irq_dispose_mapping(virq);
		return rc;
	}
	return virq;
}

static void put_batt_soc_irq(int virq)
{
	if (virq > 0) {
		free_irq(virq, NULL);
		irq_dispose_mapping(virq);
	}
}

/* ---- reporting ---- */

static void report(const char *when)
{
	u8 prof[PROFILE_LEN], vf[2], fv, soc = 0;
	const char *who;
	int rc;

	rc = sram_read(PROFILE_LOAD_WORD, 0, prof, PROFILE_LEN);
	if (!rc)
		rc = sram_read(VBATT_FULL_WORD, 0, vf, 2);
	if (!rc)
		rc = sram_read(FLOAT_VOLT_WORD, FLOAT_VOLT_OFF, &fv, 1);
	if (rc) {
		pr_err("nura_fgload: %s: SRAM read failed %d\n", when, rc);
		return;
	}
	rd(fg_base + BATT_SOC_MONOTONIC_SOC, &soc);
	if (!memcmp(prof, zql5018_profile, PROFILE_COMP_LEN))
		who = "zql5018 (6000 mAh)";
	else if (!memcmp(prof, bootloader_profile, PROFILE_COMP_LEN))
		who = "bootloader (2879 mAh)";
	else
		who = "UNKNOWN";
	pr_info("nura_fgload: %s: profile %s, nom_cap %u mAh, integrity 0x%02x, vbatt_full %u mV (raw %02x%02x), float %u mV (raw %02x), msoc %u/255\n",
		when, who,
		prof[(NOM_CAP_WORD - PROFILE_LOAD_WORD) * 4] |
		prof[(NOM_CAP_WORD - PROFILE_LOAD_WORD) * 4 + 1] << 8,
		prof[PROFILE_LEN - 1],
		(unsigned int)(((vf[0] | vf[1] << 8) & 0x7fff) * 244141ULL / 1000000),
		vf[1], vf[0], 2000 + fv * 15625 / 1000, fv, soc);
}

/* ---- profile load (profile_load_work) ---- */

static int load_profile(const u8 *profile, u8 integrity, u8 vf0, u8 vf1, u8 fv,
			const char *name)
{
	u8 vf[2] = { vf0, vf1 }, chk[PROFILE_LEN], val;
	int upd_irq, rdy_irq, rc, i;
	long t;

	report("before");

	upd_irq = get_batt_soc_irq(IRQ_SOC_UPDATE, soc_update_irq, "nura-soc-update");
	if (upd_irq < 0) {
		pr_err("nura_fgload: soc-update irq: %d, nothing written\n", upd_irq);
		return upd_irq;
	}
	rdy_irq = get_batt_soc_irq(IRQ_SOC_READY, soc_ready_irq, "nura-soc-ready");
	if (rdy_irq < 0) {
		pr_err("nura_fgload: soc-ready irq: %d, nothing written\n", rdy_irq);
		put_batt_soc_irq(upd_irq);
		return rdy_irq;
	}

	/* atomic: start right after an FG cycle (SOC_UPDATE, every ~1.47 s) */
	reinit_completion(&soc_update);
	t = wait_for_completion_timeout(&soc_update,
					msecs_to_jiffies(SOC_UPDATE_WAIT_MS));
	if (!t)
		t = wait_for_completion_timeout(&soc_update,
						msecs_to_jiffies(SOC_UPDATE_WAIT_MS));
	if (!t) {
		pr_err("nura_fgload: no SOC_UPDATE interrupt, nothing written\n");
		rc = -ETIMEDOUT;
		goto out;
	}

	pr_info("nura_fgload: loading %s profile\n", name);
	rc = mwr(fg_base + BATT_SOC_RESTART, RESTART_GO_BIT, 0);
	if (rc)
		goto out;
	rc = sram_write(PROFILE_LOAD_WORD, 0, profile, PROFILE_LEN);
	if (rc) {
		pr_err("nura_fgload: profile write failed %d\n", rc);
		goto out;
	}
	rc = sram_read(PROFILE_LOAD_WORD, 0, chk, PROFILE_LEN);
	if (!rc) {
		for (i = 0; i < PROFILE_LEN; i++)
			if (chk[i] != profile[i])
				break;
		if (i < PROFILE_LEN) {
			pr_err("nura_fgload: read-back differs at byte %d (%02x != %02x), FG not restarted\n",
			       i, chk[i], profile[i]);
			rc = -EIO;
		}
	}
	if (rc)
		goto out;
	pr_info("nura_fgload: profile written and verified, restarting FG\n");

	/* __fg_restart() */
	reinit_completion(&soc_ready);
	rc = mwr(fg_base + BATT_SOC_RESTART, RESTART_GO_BIT, RESTART_GO_BIT);
	if (rc)
		goto out;
	t = wait_for_completion_timeout(&soc_ready,
					msecs_to_jiffies(SOC_READY_WAIT_MS));
	if (!t)
		pr_err("nura_fgload: wait for SOC_READY timed out\n");
	else
		pr_info("nura_fgload: SOC_READY after restart\n");
	rc = mwr(fg_base + BATT_SOC_RESTART, RESTART_GO_BIT, 0);
	if (rc)
		goto out;

	val = integrity;
	rc = sram_write(PROFILE_INTEGRITY_WORD, PROFILE_INTEGRITY_OFF, &val, 1);
	if (rc)
		goto out;
	/* fg_bp_params_config() */
	rc = sram_write(FLOAT_VOLT_WORD, FLOAT_VOLT_OFF, &fv, 1);
	if (!rc)
		rc = sram_write(VBATT_FULL_WORD, 0, vf, 2);
out:
	put_batt_soc_irq(rdy_irq);
	put_batt_soc_irq(upd_irq);
	pr_info("nura_fgload: %s load finished, rc %d\n", name, rc);
	report("after");
	return rc;
}

/* ---- debugfs ---- */

static int sram_show(struct seq_file *s, void *unused)
{
	u8 buf[4];
	int w, rc;

	mutex_lock(&lock);
	for (w = 0; w < NUM_WORDS; w++) {
		rc = sram_read(w, 0, buf, 4);
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

static ssize_t control_write(struct file *f, const char __user *ubuf,
			     size_t len, loff_t *ppos)
{
	char cmd[16] = {};
	int rc = 0;

	if (len >= sizeof(cmd))
		return -EINVAL;
	if (copy_from_user(cmd, ubuf, len))
		return -EFAULT;

	mutex_lock(&lock);
	if (!strcmp(strim(cmd), "check"))
		report("check");
	else if (!strcmp(strim(cmd), "load"))
		rc = load_profile(zql5018_profile, HLOS_RESTART_BIT | PROFILE_LOAD_BIT,
				  ZQL_VBATT_FULL0, ZQL_VBATT_FULL1, ZQL_FLOAT_VOLT,
				  "zql5018");
	else if (!strcmp(strim(cmd), "restore"))
		rc = load_profile(bootloader_profile,
				  BOOTLOADER_LOAD_BIT | PROFILE_LOAD_BIT,
				  BOOT_VBATT_FULL0, BOOT_VBATT_FULL1, BOOT_FLOAT_VOLT,
				  "bootloader");
	else
		rc = -EINVAL;
	mutex_unlock(&lock);
	return rc ? rc : len;
}

static const struct file_operations control_fops = {
	.owner = THIS_MODULE,
	.write = control_write,
};

static int __init nura_fgload_init(void)
{
	struct platform_device *pdev;
	const __be32 *reg;

	fg_np = of_find_compatible_node(NULL, NULL, "qcom,pmi8998-fg");
	if (!fg_np)
		return -ENODEV;
	reg = of_get_address(fg_np, 0, NULL, NULL);
	pdev = of_find_device_by_node(fg_np);
	if (!reg || !pdev)
		goto err;
	map = dev_get_regmap(pdev->dev.parent, NULL);
	put_device(&pdev->dev);
	if (!map)
		goto err;
	fg_base = be32_to_cpu(*reg);
	mem_if = fg_base + 0x400;
	pr_info("nura_fgload: FG at 0x%04x, MEM_IF at 0x%04x\n", fg_base, mem_if);

	dir = debugfs_create_dir("nura_fgload", NULL);
	debugfs_create_file("sram", 0400, dir, NULL, &sram_fops);
	debugfs_create_file("control", 0200, dir, NULL, &control_fops);
	return 0;
err:
	of_node_put(fg_np);
	return -ENODEV;
}

static void __exit nura_fgload_exit(void)
{
	debugfs_remove_recursive(dir);
	of_node_put(fg_np);
}

module_init(nura_fgload_init);
module_exit(nura_fgload_exit);
MODULE_DESCRIPTION("PM660 fuel gauge battery profile loader (clover test)");
MODULE_LICENSE("GPL");
