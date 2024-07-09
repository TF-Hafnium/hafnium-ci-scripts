#!/bin/bash
#
# Copyright (c) 2022 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Build ACS test suite.

cd ${WORKSPACE}/ff-a-acs
mkdir build
cd build
echo "Building ACS test suite."

cmake ../ -G"Unix Makefiles" \
	-DCROSS_COMPILE=aarch64-none-elf- \
	-DTARGET=tgt_tfa_fvp \
	-DPLATFORM_FFA_V_ALL=1 \
	-DPLATFORM_NS_HYPERVISOR_PRESENT=0 \
	-DPLATFORM_SP_EL=1 \
	-DENABLE_BTI=ON \
	-DCMAKE_BUILD_TYPE=Debug \
	-DSUITE=all
make

# Build Hafnium
export PATH=${WORKSPACE}/hafnium/prebuilts/linux-x64/dtc:$PATH

cd ${WORKSPACE}/hafnium
echo "Building Hafnium."
make PLATFORM=secure_aem_v8a_fvp_vhe

# Build TF-A
cd ${WORKSPACE}/trusted-firmware-a
echo "Building TF-A."
make CROSS_COMPILE=aarch64-none-elf- PLAT=fvp DEBUG=1 \
	BL33=${WORKSPACE}/ff-a-acs/build/output/vm1.bin \
	BL32=${WORKSPACE}/hafnium/out/reference/secure_aem_v8a_fvp_vhe_clang/hafnium.bin \
	SP_LAYOUT_FILE=${WORKSPACE}/ff-a-acs/platform/manifest/tgt_tfa_fvp/sp_layout.json \
	ARM_SPMC_MANIFEST_DTS=${WORKSPACE}/ff-a-acs/platform/manifest/tgt_tfa_fvp/fvp_spmc_manifest.dts \
	ARM_ARCH_MAJOR=8 \
	ARM_ARCH_MINOR=5 \
	BRANCH_PROTECTION=1 \
	GIC_EXT_INTID=1 \
	PLAT_TEST_SPM=1 \
	ENABLE_FEAT_MTE2=1 \
	SPD=spmd \
	ARM_BL2_SP_LIST_DTS=${WORKSPACE}/trusted-firmware-a/build/fvp/debug/sp_list_fragment.dts \
	all fip -j8

echo "Finished building all targets."
cd ${WORKSPACE}
