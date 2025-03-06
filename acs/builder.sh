#!/bin/bash
#
# Copyright (c) 2022 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

set -ex

# Build TF-A project.
# Argument $1 provides the sp layout file to be used.
# Argument $2 provides the spmc manifest to be used.
build_tfa() {
	local SP_LAYOUT=$1
	local SPMC_MANIFEST=$2

	echo "Building TF-A."
	make -C ${WORKSPACE}/trusted-firmware-a \
		CROSS_COMPILE=aarch64-none-elf- \
		PLAT=fvp \
		DEBUG=1 \
		BL33=${WORKSPACE}/ff-a-acs/build/output/vm1.bin \
		BL32=${WORKSPACE}/hafnium/out/reference/secure_aem_v8a_fvp_vhe_clang/hafnium.bin \
		SP_LAYOUT_FILE=${SP_LAYOUT} \
		ARM_SPMC_MANIFEST_DTS=${SPMC_MANIFEST} \
		ARM_ARCH_MAJOR=8 \
		ARM_ARCH_MINOR=5 \
		BRANCH_PROTECTION=1 \
		GIC_EXT_INTID=1 \
		PLAT_TEST_SPM=1 \
		ENABLE_FEAT_MTE2=1 \
		SPD=spmd \
		ENABLE_SPMD_LP=1\
		ARM_BL2_SP_LIST_DTS=${WORKSPACE}/trusted-firmware-a/build/fvp/debug/sp_list_fragment.dts \
		POETRY= \
		all fip -j8
}

# Copy the generated FIP image from TF-A project.
# Argument $1 contains the output file.
copy_tfa_fip() {
	cp ${WORKSPACE}/trusted-firmware-a/build/fvp/debug/fip.bin $1
}

# Builds the ACS suite, assuming the repo has been setup.
# Argument $1 contains the exception level for the SPs, which should be 0 or 1.
build_acs() {
	cd ${WORKSPACE}/ff-a-acs/build
	cmake ../ -G"Unix Makefiles" \
		-DCROSS_COMPILE=aarch64-none-elf- \
		-DTARGET=tgt_tfa_fvp \
		-DPLATFORM_FFA_V_ALL=1 \
		-DPLATFORM_NS_HYPERVISOR_PRESENT=0 \
		-DPLATFORM_SP_EL=$1 \
		-DENABLE_BTI=ON \
		-DCMAKE_BUILD_TYPE=Debug \
		-DSUITE=all
	make
}

# Build Hafnium.
export PATH=${WORKSPACE}/hafnium/prebuilts/linux-x64/dtc:$PATH
echo "Building Hafnium."
make -C ${WORKSPACE}/hafnium PLATFORM=secure_aem_v8a_fvp_vhe

# Setup the ACS test suite.
pushd ${WORKSPACE}/ff-a-acs
mkdir build
popd

FFA_ACS_MANIFEST_FOLDER=${WORKSPACE}/ff-a-acs/platform/manifest/tgt_tfa_fvp

echo "Building ACS test suite (S-EL1 targets)."
build_acs 1
build_tfa ${FFA_ACS_MANIFEST_FOLDER}/sp_layout_v12.json ${FFA_ACS_MANIFEST_FOLDER}/fvp_spmc_manifest.dts
copy_tfa_fip ${WORKSPACE}/fip_sp_sel1.bin

make -C ${WORKSPACE}/trusted-firmware-a realclean

# Clean ACS output folder.
pushd ${WORKSPACE}/ff-a-acs
rm -r build/*
popd

echo "Building ACS test suite (S-EL0 targets)."
build_acs 0
build_tfa ${FFA_ACS_MANIFEST_FOLDER}/sp_layout_el0_v12.json ${FFA_ACS_MANIFEST_FOLDER}/fvp_spmc_manifest_el0.dts
copy_tfa_fip ${WORKSPACE}/fip_sp_sel0.bin

echo "Finished building all targets."
cd ${WORKSPACE}
