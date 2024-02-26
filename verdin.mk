################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
COMPILE_NS_USER   ?= 64
override COMPILE_NS_KERNEL := 64
COMPILE_S_USER    ?= 64
COMPILE_S_KERNEL  ?= 64

MEASURED_BOOT_FTPM ?= y

BR2_TARGET_GENERIC_GETTY_PORT = ttymxc0
################################################################################
# Includes
################################################################################
include common.mk

################################################################################
# Paths to git projects and various binaries
################################################################################
OUT_PATH		?= $(ROOT)/out
TF_A_PATH		?= $(ROOT)/trusted-firmware-a
UBOOT_PATH		?= $(ROOT)/u-boot
OPTEE_PATH		?= $(ROOT)/optee_os
FTPM_PATH		?= $(ROOT)/ms-tpm-20-ref/Samples/ARM32-FirmwareTPM/optee_ta

UBOOT_BIN		?= $(UBOOT_PATH)/flash.bin
OPTEE_BIN		?= $(OPTEE_PATH)/out/arm/core/tee-raw.bin

DDR_URL			?= https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/firmware-imx-8.1.1.bin
DDR_PATH		?= $(ROOT)/ddr-firmware

ATF_LOAD_ADDR		?= 0x920000
TEE_LOAD_ADDR		?= 0xbe000000

EDK2_TOOLCHAIN		?= GCC5
EDK2_BUILD		?= RELEASE
EDK2_ARCH		?= AARCH64
EDK2_BIN		?= $(ROOT)/Build/MmStandaloneRpmb/RELEASE_GCC5/FV/BL32_AP_MM.fd

################################################################################
# Targets
################################################################################
.PHONY: all
all: u-boot
	cp ../u-boot/flash.bin .

.PHONY: clean
clean: u-boot-clean ftpm-clean arm-tf-clean optee-os-clean

################################################################################
# Toolchain
################################################################################
include toolchain.mk

################################################################################
# U-Boot
################################################################################
.PHONY: u-boot-config
u-boot-config:
	cp kconfigs/u-boot_verdin.conf $(UBOOT_PATH)/configs/verdin-imx8mm_defconfig
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) verdin-imx8mm_defconfig

.PHONY: u-boot-menuconfig
u-boot-menuconfig: u-boot-config
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) menuconfig
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) savedefconfig
	cp $(UBOOT_PATH)/defconfig kconfigs/u-boot_verdin.conf

.PHONY: u-boot
u-boot: u-boot-config arm-tf optee-os ddr-firmware
	# Copy BL31 binary from TF-A
	cp $(TF_A_PATH)/build/imx8mm/release/bl31.bin $(UBOOT_PATH)
	# Prepare proper tee.bin
	cp $(OPTEE_BIN) $(UBOOT_PATH)/tee.bin
	# Copy DDR4 firmware
	cp $(DDR_PATH)/firmware-imx-8.1.1/firmware/ddr/synopsys/lpddr4*.bin \
		$(UBOOT_PATH)
	# Build U-Boot and final ready-to-flash flash.bin image
	$(MAKE) -C $(UBOOT_PATH) \
		BL31=bl31.bin \
		TEE=tee.bin \
		CROSS_COMPILE="$(AARCH64_CROSS_COMPILE)" flash.bin

.PHONY: u-boot-clean
u-boot-clean:
	cd $(UBOOT_PATH) && git clean -xdf

################################################################################
# DDR4 Firmware
################################################################################
.PHONY: ddr-firmware
ddr-firmware:
	# DDR is exported to the $PWD only, so cd to $(DDR_PATH)
	# before unpacking
	if [ ! -d "$(DDR_PATH)" ]; then \
		mkdir -p $(DDR_PATH) && \
		wget $(DDR_URL) -O $(DDR_PATH)/firmware.bin && \
		chmod +x $(DDR_PATH)/firmware.bin && \
		cd $(DDR_PATH) && \
		$(DDR_PATH)/firmware.bin --auto-accept && \
		cd $(ROOT)/build; \
	fi;

.PHONY: ddr-firmware-clean
ddr-firmware-clean:
	rm -rf $(DDR_PATH)

################################################################################
# ARM Trusted Firmware
################################################################################
.PHONY: arm-tf
arm-tf:
	$(MAKE) -C $(TF_A_PATH) \
		PLAT=imx8mm \
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		IMX_BOOT_UART_BASE=0x30860000 \
		SPD=opteed \
		DEBUG=0 \
		EVENT_LOG_LEVEL=1 \
		MEASURED_BOOT=1 \
		TRUSTED_BOARD_BOOT=1 \
		MBEDTLS_DIR=$(ROOT)/mbedtls \
		MBOOT_EL_HASH_ALG=sha256 \
		bl31

.PHONY: arm-tf-clean
arm-tf-clean:
	cd $(TF_A_PATH) && git clean -xdf

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += PLATFORM=imx \
	PLATFORM_FLAVOR=mx8mmevk \
	CFG_UART_BASE=0x30860000 \
	CFG_DDR_SIZE=0x80000000 \
	CFG_CORE_LARGE_PHYS_ADDR=n \
	CFG_CORE_ARM64_PA_BITS=32 \
	CFG_TZDRAM_START=0xbe000000 \
	CFG_DT=n \
	CFG_EXTERNAL_DT=n \
	CFG_CORE_DYN_SHM=y \
	CFG_REE_FS=n \
	CFG_EARLY_TA=y \
	EARLY_TA_PATHS="$(FTPM_PATH)/out/fTPM/bc50d971-d4c9-42c4-82cb-343fb7f37896.stripped.elf \
	                $(OPTEE_OS_PATH)/out/arm/ta/avb/023f8f1a-292a-432b-8fc4-de8471358067.elf" \
	CFG_STMM_PATH=$(EDK2_BIN) \
	CFG_RPMB_FS=y \
	CFG_RPMB_FS_DEV_ID=0 \
	CFG_CRYPTO_DRIVER=y \
	CFG_NXP_CAAM=y \
	CFG_NXP_CAAM_RNG_DRV=y \
	CFG_WITH_SOFTWARE_PRNG=n \
	CFG_RPMB_WRITE_KEY=y \
	CFG_RPMB_TESTKEY=n \
	CFG_CORE_HEAP_SIZE=0x80000 \
	CFG_TEE_RAM_VA_SIZE=0x400000
	#CFG_CORE_TPM_EVENT_LOG=y \

OPTEE_OS_CLEAN_COMMON_FLAGS += PLATFORM=imx-mx8mmevk

.PHONY: optee-os
optee-os: optee-os-common

.PHONY: optee-os-clean
optee-os-clean: edk2-clean-common optee-os-clean-common
