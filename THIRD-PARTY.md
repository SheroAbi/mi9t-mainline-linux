# Third-party components

| Component | Where | Origin | Licence |
|---|---|---|---|
| Linux 7.1.0 | built from source, not vendored | `sm7150-mainline/linux` @ `fd78d179`, branch v7.2 | GPL-2.0 |
| `qcom_qg.c`, `qcom_smbx.c` | `kernel/modules/` | the upstream drivers above, with this project's patches | GPL-2.0 |
| upstream copies of those two | `kernel/upstream-reference/*-before.c` | the same tree, unmodified | GPL-2.0 |
| Xiaomi vendor sources | `kernel/upstream-reference/davinci-vendor-*.c/.h`, `batterydata-*.dtsi`, `pm6150-vendor.dtsi` | `MiCode/Xiaomi_Kernel_OpenSource`, branch `davinci-p-oss` | GPL-2.0 |
| Qualcomm vendor gauge | `kernel/upstream-reference/qcom-qg-vendor.c`, `qg-reg.h` | Qualcomm CAF | BSD-3-Clause / GPL-2.0 dual |
| hexagonrpc 0.5.0 | `hardware-package/usr/local/` (built) | https://github.com/linux-msm/hexagonrpc | see the package copyright file |
| libssc 0.4.4 | `hardware-package/usr/local/` (built) | https://github.com/linux-msm/libssc | see the package copyright file |
| iio-sensor-proxy 3.9 | `hardware-package/usr/local/` (built) | upstream + `hardware-package/patches/iio-startup-race.patch` | GPL-2.0 |
| ALSA UCM profile | `hardware-package/usr/share/alsa/ucm2/` | https://github.com/sm7150-mainline/alsa-ucm-conf | BSD-3-Clause |
| Sensor configuration | `hardware-package/usr/share/qcom/` | the davinci firmware tree | proprietary, redistributable |
| U-Boot 2025.04 (built by `image/build-uboot.sh`) | https://github.com/Gelbpunkt/u-boot @ `70c600c1` | GPL-2.0+ |
| mkbootimg (build tool for U-Boot's boot image) | https://github.com/osm0sis/mkbootimg @ `17cea80b` | Apache-2.0 |
| pd-mapper v1.1 (compiled into the image) | https://github.com/linux-msm/pd-mapper | BSD-3-Clause |
| systemd-boot, the Ubuntu userland | Ubuntu 24.04 archive; Firefox from Mozilla's APT repository | their own licences |

Every URL and SHA-256 sum for the reference sources is in
`kernel/upstream-reference/sources.json`.

The device firmware itself is **not** in this repository. The image build
fetches the pinned tree at
https://github.com/sm7150-mainline/firmware-xiaomi-davinci/tree/7c25d3fe5883f25f8f068e89c6442b4c608835f0
— all 485 files on the device were verified against it.
