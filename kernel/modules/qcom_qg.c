// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2024, Danila Tikhonov <danila@jiaxyga.com>
 */

#include <linux/iio/consumer.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/nvmem-consumer.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>
#include <linux/power_supply.h>
#include <linux/regmap.h>
#include <linux/jiffies.h>
#include <linux/timekeeping.h>
#include <linux/mutex.h>
#include <linux/workqueue.h>
#include <linux/devm-helpers.h>

/* BATT offsets */
#define QG_S2_NORMAL_AVG_V_DATA0_REG	0x80 /* 2-byte 0x80-0x81 */
#define QG_S2_NORMAL_AVG_I_DATA0_REG	0x82 /* 2-byte 0x82-0x83 */
#define QG_LAST_ADC_V_DATA0_REG		0xc0 /* 2-byte 0xc0-0xc1 */
#define QG_LAST_ADC_I_DATA0_REG		0xc2 /* 2-byte 0xc2-0xc3 */

/* SRAM offsets */
#define QG_SDAM_OCV_OFFSET		0x4c /* 4-byte 0x4c-0x4f */
#define QG_SDAM_LEARNED_CAPACITY_OFFSET	0x68 /* 2-byte 0x68-0x69 */

struct qcom_qg_chip {
	struct device *dev;
	struct regmap *regmap;
	unsigned int base;

	struct iio_channel *batt_therm_chan;

	struct nvmem_device *sdam;

	struct power_supply *batt_psy;
	struct power_supply_battery_info *batt_info;

	/* Smoothed state of charge in per mille; -1 = no reading yet */
	int soc_permille;
	u64 sample_ms;
	s64 charge_uams;
	s64 full_uams;
	unsigned int low_voltage_samples;
	struct mutex soc_lock;
	struct delayed_work notify_work;
};

/*
 * Open-circuit voltage -> state of charge of a Li-ion cell charged to 4.4 V.
 * Fallback only for the preserved recovery DT without a battery profile.
 * The normal boot uses Xiaomi's identified Sunwoda profile from DT.
 * Points in microvolts and per mille,
 * linearly interpolated in between.
 */
struct qg_ocv_point {
	int ocv_uv;
	int soc_permille;
};

static const struct qg_ocv_point qg_ocv_curve[] = {
	{ 3400000,    0 }, { 3500000,   30 }, { 3570000,   70 },
	{ 3620000,  120 }, { 3660000,  180 }, { 3700000,  250 },
	{ 3730000,  320 }, { 3760000,  390 }, { 3800000,  460 },
	{ 3850000,  530 }, { 3900000,  600 }, { 3960000,  670 },
	{ 4020000,  740 }, { 4080000,  810 }, { 4150000,  880 },
	{ 4230000,  940 }, { 4310000,  980 }, { 4400000, 1000 },
};

/* Plausibility window for a single cell */
#define QG_VOLT_SANE_MIN_UV	2500000
#define QG_VOLT_SANE_MAX_UV	4600000

/* Current above which the cell counts as charging or discharging */
#define QG_CURRENT_IDLE_UA		50000

static int qg_lookup_soc(int ocv_uv)
{
	const struct qg_ocv_point *c = qg_ocv_curve;
	int n = ARRAY_SIZE(qg_ocv_curve);
	int i, dv, ds;

	if (ocv_uv <= c[0].ocv_uv)
		return c[0].soc_permille;
	if (ocv_uv >= c[n - 1].ocv_uv)
		return c[n - 1].soc_permille;

	for (i = 1; i < n; i++) {
		if (ocv_uv < c[i].ocv_uv) {
			dv = c[i].ocv_uv - c[i - 1].ocv_uv;
			ds = c[i].soc_permille - c[i - 1].soc_permille;
			return c[i - 1].soc_permille +
				       DIV_ROUND_CLOSEST((ocv_uv - c[i - 1].ocv_uv) * ds, dv);
		}
	}
	return c[n - 1].soc_permille;
}

static int qcom_qg_get_current(struct qcom_qg_chip *chip, u8 offset, int *val)
{
	s16 temp;
	u8 readval[2];
	int ret;

	ret = regmap_bulk_read(chip->regmap, chip->base + offset, readval, 2);
	if (ret) {
		dev_err(chip->dev, "Failed to read current: %d\n", ret);
		return ret;
	}

	temp = (s16)(readval[1] << 8 | readval[0]);
	*val = div_s64((s64)temp * 152588, 1000);

	/*
	 * PSY API expects charging batteries to report a positive current, which is inverted
	 * to what the PMIC reports.
	 */
	*val = -*val;

	return 0;
}

static int qcom_qg_get_voltage(struct qcom_qg_chip *chip, u8 offset, int *val)
{
	int ret, temp;
	u8 readval[2];

	ret = regmap_bulk_read(chip->regmap, chip->base + offset, readval, 2);
	if (ret) {
		dev_err(chip->dev, "Failed to read voltage: %d\n", ret);
		return ret;
	}

	temp = readval[1] << 8 | readval[0];
	*val = div_u64((u64)temp * 194637, 1000);

	return 0;
}

/*
 * Seed from the hardware power-on OCV and the identified pack's DT profile.
 * Thereafter integrate signed battery current over elapsed time. Charging
 * voltage must not be reinterpreted as newly acquired charge on every poll.
 * This is sampled-current estimation, not a hardware coulomb counter; full
 * termination is the calibration anchor and long-cycle accuracy needs testing.
 */
static int qcom_qg_get_status(struct qcom_qg_chip *chip, int *val);

static int qcom_qg_get_capacity(struct qcom_qg_chip *chip, int *val)
{
	u64 now = ktime_to_ms(ktime_get_boottime()), elapsed;
	int ret, voltage, current_ua, ocv, temp, soc, status;
	int resistance = 118; /* validated SDAM Rbat, milliohms */
	u8 learned[2];
	int full_uah;

	if (chip->soc_permille >= 0 && now - chip->sample_ms < 1000)
		goto report;
	ret = qcom_qg_get_voltage(chip, QG_S2_NORMAL_AVG_V_DATA0_REG, &voltage);
	if (ret || voltage < QG_VOLT_SANE_MIN_UV || voltage > QG_VOLT_SANE_MAX_UV)
		ret = qcom_qg_get_voltage(chip, QG_LAST_ADC_V_DATA0_REG, &voltage);
	if (ret)
		return ret;
	if (voltage < QG_VOLT_SANE_MIN_UV || voltage > QG_VOLT_SANE_MAX_UV)
		return -EAGAIN;
	ret = qcom_qg_get_current(chip, QG_S2_NORMAL_AVG_I_DATA0_REG, &current_ua);
	if (ret)
		return ret;
	if (abs(current_ua) > 10000000)
		return -EAGAIN;

	if (chip->soc_permille < 0) {
		full_uah = chip->batt_info->charge_full_design_uah;
		ret = nvmem_device_read(chip->sdam, QG_SDAM_LEARNED_CAPACITY_OFFSET,
				       sizeof(learned), learned);
		if (ret >= 0) {
			int measured = (learned[0] | learned[1] << 8) * 1000;
			if (measured >= full_uah / 2 && measured <= full_uah * 105 / 100)
				full_uah = measured;
		}
		if (full_uah <= 0 || full_uah > 10000000)
			return -EINVAL;
		chip->full_uams = (s64)full_uah * 3600000;
		ocv = voltage - div_s64((s64)current_ua * resistance, 1000);
		/* Power-on measurements are useful only during this boot's startup. */
		if (now < 120000) {
			int pon_v, pon_i;
			if (!qcom_qg_get_voltage(chip, 0x70, &pon_v) &&
			    !qcom_qg_get_current(chip, 0x72, &pon_i) &&
			    pon_v >= 3000000 && pon_v <= 4450000 && abs(pon_i) < 200000)
				ocv = pon_v - div_s64((s64)pon_i * resistance, 1000);
		}
		ret = iio_read_channel_processed(chip->batt_therm_chan, &temp);
		if (ret < 0)
			return ret;
		soc = power_supply_batinfo_ocv2cap(chip->batt_info, ocv, temp / 1000);
		if (soc < 0)
			soc = DIV_ROUND_CLOSEST(qg_lookup_soc(ocv), 10);
		soc = clamp(soc, 0, 99);
		chip->charge_uams = div_s64(chip->full_uams * soc, 100);
		chip->soc_permille = soc * 10;
		dev_info(chip->dev, "SOC initialized from OCV %duV at %dC: %d%%, %duAh\n",
			 ocv, temp / 1000, soc, full_uah);
	} else {
		elapsed = now - chip->sample_ms;
		/* Keep arithmetic bounded after unusual multi-day suspend intervals. */
		elapsed = min_t(u64, elapsed, 24ULL * 60 * 60 * 1000);
		chip->charge_uams += (s64)current_ua * (s64)elapsed;
		chip->charge_uams = clamp_t(s64, chip->charge_uams, 0, chip->full_uams);
	}

	ret = qcom_qg_get_status(chip, &status);
	if (!ret && status == POWER_SUPPLY_STATUS_FULL && voltage >= 4300000)
		chip->charge_uams = chip->full_uams;
	else if (!ret && status == POWER_SUPPLY_STATUS_CHARGING)
		chip->charge_uams = min(chip->charge_uams, div_s64(chip->full_uams * 99, 100));

	/* Do not conceal a depleted cell behind a drifting software estimate. */
	if (voltage < 3300000 && current_ua < 0)
		chip->low_voltage_samples++;
	else
		chip->low_voltage_samples = 0;
	if (chip->low_voltage_samples >= 3)
		chip->charge_uams = 0;
	chip->sample_ms = now;
report:
	*val = clamp_t(s64, div64_s64(chip->charge_uams * 100 + chip->full_uams / 2,
				   chip->full_uams), 0, 100);
	return 0;
}

static int qcom_qg_get_status(struct qcom_qg_chip *chip, int *val)
{
	struct power_supply *charger;
	union power_supply_propval online, status;
	int current_ua, ret;

	charger = power_supply_get_by_name("pm8150b-charger");
	if (charger) {
		ret = power_supply_get_property(charger, POWER_SUPPLY_PROP_ONLINE, &online);
		if (!ret && online.intval) {
			ret = power_supply_get_property(charger, POWER_SUPPLY_PROP_STATUS, &status);
			power_supply_put(charger);
			if (ret)
				return ret;
			*val = status.intval;
			return 0;
		}
		power_supply_put(charger);
	}
	ret = qcom_qg_get_current(chip, QG_LAST_ADC_I_DATA0_REG, &current_ua);
	if (ret)
		return ret;
	*val = current_ua > QG_CURRENT_IDLE_UA ? POWER_SUPPLY_STATUS_CHARGING :
		POWER_SUPPLY_STATUS_DISCHARGING;
	return 0;
}

static void qcom_qg_notify_work(struct work_struct *work)
{
	struct qcom_qg_chip *chip = container_of(to_delayed_work(work),
					struct qcom_qg_chip, notify_work);
	int capacity;

	mutex_lock(&chip->soc_lock);
	qcom_qg_get_capacity(chip, &capacity);
	mutex_unlock(&chip->soc_lock);
	/* Measurements must reach UPower even when no charger IRQ occurs. */
	power_supply_changed(chip->batt_psy);
	schedule_delayed_work(&chip->notify_work, msecs_to_jiffies(5000));
}

static enum power_supply_property qcom_qg_props[] = {
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_VOLTAGE_MAX_DESIGN,
	POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_VOLTAGE_AVG,
	POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_CURRENT_AVG,
	POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_CHARGE_FULL,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_TEMP,
};

static int qcom_qg_get_property(struct power_supply *psy,
				enum power_supply_property psp,
				union power_supply_propval *val)
{
	struct qcom_qg_chip *chip = power_supply_get_drvdata(psy);
	int ret;

	if (!chip->batt_info)
		return -EAGAIN;

	switch (psp) {
	case POWER_SUPPLY_PROP_STATUS:
		return qcom_qg_get_status(chip, &val->intval);
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		val->intval = POWER_SUPPLY_TECHNOLOGY_LION;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_MAX_DESIGN:
		val->intval = chip->batt_info->voltage_max_design_uv;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN:
		val->intval = chip->batt_info->voltage_min_design_uv;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		ret = qcom_qg_get_voltage(chip,
				QG_LAST_ADC_V_DATA0_REG, &val->intval);
		if (ret)
			return ret;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_AVG:
		ret = qcom_qg_get_voltage(chip,
				QG_S2_NORMAL_AVG_V_DATA0_REG, &val->intval);
		if (ret)
			return ret;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_OCV:
		ret = nvmem_device_read(chip->sdam, QG_SDAM_OCV_OFFSET, 4, &val->intval);
		if (ret < 0)
			return ret;
		break;
	case POWER_SUPPLY_PROP_CURRENT_NOW:
		ret = qcom_qg_get_current(chip,
				QG_LAST_ADC_I_DATA0_REG, &val->intval);
		if (ret)
			return ret;
		break;
	case POWER_SUPPLY_PROP_CURRENT_AVG:
		ret = qcom_qg_get_current(chip,
				QG_S2_NORMAL_AVG_I_DATA0_REG, &val->intval);
		if (ret)
			return ret;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
		val->intval = chip->batt_info->charge_full_design_uah;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL:
		val->intval = 0;
		ret = nvmem_device_read(chip->sdam,
				QG_SDAM_LEARNED_CAPACITY_OFFSET, 2, &val->intval);
		if (ret < 0)
			return ret;
		val->intval *= 1000; /* mAh to uAh */
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		mutex_lock(&chip->soc_lock);
		ret = qcom_qg_get_capacity(chip, &val->intval);
		mutex_unlock(&chip->soc_lock);
		if (ret)
			return ret;
		break;
	case POWER_SUPPLY_PROP_TEMP:
		ret = iio_read_channel_processed
					(chip->batt_therm_chan, &val->intval);
		if (ret < 0)
			return ret;
		val->intval /= 100; /* 1/1000 °C (millidegC) to 1/10 °C */
		break;
	default:
		dev_err(chip->dev, "invalid property: %d\n", psp);
		return -EINVAL;
	}
	return 0;
}

static struct power_supply_desc batt_psy_desc = {
	.name = "qcom_qg",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.properties = qcom_qg_props,
	.num_properties = ARRAY_SIZE(qcom_qg_props),
	.get_property = qcom_qg_get_property,
};

static int qcom_qg_probe(struct platform_device *pdev)
{
	struct qcom_qg_chip *chip;
	struct power_supply_config psy_cfg = {};
	int ret;

	chip = devm_kzalloc(&pdev->dev, sizeof(*chip), GFP_KERNEL);
	if (!chip)
		return -ENOMEM;

	chip->dev = &pdev->dev;
	chip->soc_permille = -1;	/* no reading yet */
	mutex_init(&chip->soc_lock);

	/* Regmap */
	chip->regmap = dev_get_regmap(chip->dev->parent, NULL);
	if (!chip->regmap)
		return dev_err_probe(chip->dev, -ENODEV,
				     "Failed to locate the regmap\n");

	/* Get base address */
	ret = device_property_read_u32(chip->dev, "reg", &chip->base);
	if (ret < 0)
		return dev_err_probe(chip->dev, ret,
				     "Couldn't read base address\n");

	/* ADC for thermal channel */
	chip->batt_therm_chan = devm_iio_channel_get(chip->dev, "batt-therm");
	if (IS_ERR(chip->batt_therm_chan))
		return dev_err_probe(chip->dev, PTR_ERR(chip->batt_therm_chan),
				     "Couldn't get batt-therm IIO channel\n");

	/* NVMEM for SDAM access */
	chip->sdam = devm_nvmem_device_get(chip->dev, NULL);
	if (IS_ERR(chip->sdam))
		return dev_err_probe(chip->dev, PTR_ERR(chip->sdam),
				     "Couldn't get SDAM nvmem device\n");

	psy_cfg.drv_data = chip;
	psy_cfg.fwnode = dev_fwnode(chip->dev);

	/* Power supply */
	chip->batt_psy =
		devm_power_supply_register(chip->dev, &batt_psy_desc, &psy_cfg);
	if (IS_ERR(chip->batt_psy))
		return dev_err_probe(chip->dev, PTR_ERR(chip->batt_psy),
				     "Failed to register power supply\n");

	/* Battery info */
	ret = power_supply_get_battery_info(chip->batt_psy, &chip->batt_info);
	if (ret)
		return dev_err_probe(chip->dev, ret,
				     "Failed to get battery info\n");

	platform_set_drvdata(pdev, chip);
	ret = devm_delayed_work_autocancel(chip->dev, &chip->notify_work,
					  qcom_qg_notify_work);
	if (ret)
		return ret;
	schedule_delayed_work(&chip->notify_work, msecs_to_jiffies(5000));

	return 0;
}

static const struct of_device_id qcom_qg_of_match[] = {
	{ .compatible = "qcom,pm6150-qg", },
	{ /* sentinel */ },
};
MODULE_DEVICE_TABLE(of, qcom_qg_of_match);

static struct platform_driver qcom_qg_driver = {
	.driver = {
		.name = "qcom,qcom_qg",
		.of_match_table = qcom_qg_of_match,
	},
	.probe = qcom_qg_probe,
};

module_platform_driver(qcom_qg_driver);

MODULE_AUTHOR("Danila Tikhonov <danila@jiaxyga.com>");
MODULE_DESCRIPTION("Qualcomm PMIC QGauge (QG) driver");
MODULE_LICENSE("GPL");
