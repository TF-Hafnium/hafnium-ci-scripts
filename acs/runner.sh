#!/bin/bash
#
# Copyright (c) 2022 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Run ACS test suite.

set -ex

mkdir ${WORKSPACE}/logs
SP_SEL1_LOGS=${WORKSPACE}/logs/SP_SEL1
SP_SEL0_LOGS=${WORKSPACE}/logs/SP_SEL0

# Runs FVP with ACS test suite.
# Arguments:
# $1 -> contains the fip binary.
# $2 -> logs file name
run_fvp() {
	local FIP=$1
	local LOGS=$2

	${WORKSPACE}/../fvp/Base_RevC_AEMvA_pkg/models/Linux64_GCC-9.3/FVP_Base_RevC-2xAEMvA \
	-C pctl.startup=0.0.0.0 \
	-C cluster0.NUM_CORES=4 \
	-C cluster1.NUM_CORES=4 \
	-C bp.secure_memory=1 \
	-C bp.secureflashloader.fname=${WORKSPACE}/trusted-firmware-a/build/fvp/debug/bl1.bin \
	-C bp.flashloader0.fname=${FIP} \
	-C cluster0.has_arm_v8-5=1 \
	-C cluster1.has_arm_v8-5=1 \
	-C pci.pci_smmuv3.mmu.SMMU_AIDR=2 \
	-C pci.pci_smmuv3.mmu.SMMU_IDR0=0x0046123B \
	-C pci.pci_smmuv3.mmu.SMMU_IDR1=0x00600002 \
	-C pci.pci_smmuv3.mmu.SMMU_IDR3=0x1714 \
	-C pci.pci_smmuv3.mmu.SMMU_IDR5=0xFFFF0472 \
	-C pci.pci_smmuv3.mmu.SMMU_S_IDR1=0xA0000002 \
	-C pci.pci_smmuv3.mmu.SMMU_S_IDR2=0 \
	-C pci.pci_smmuv3.mmu.SMMU_S_IDR3=0 \
	-C cluster0.has_branch_target_exception=1 \
	-C cluster1.has_branch_target_exception=1 \
	-C cluster0.has_pointer_authentication=2 \
	-C cluster1.has_pointer_authentication=2 \
	-C bp.dram_metadata.is_enabled=1 \
	-C cluster0.memory_tagging_support_level=2 \
	-C cluster1.memory_tagging_support_level=2 \
	-C gic_distributor.ARE-fixed-to-one=1 \
	-C cluster0.gicv3.extended-interrupt-range-support=1 \
	-C cluster1.gicv3.extended-interrupt-range-support=1 \
	-C gic_distributor.extended-ppi-count=64 \
	-C gic_distributor.extended-spi-count=1024 \
	-C bp.pl011_uart0.out_file=${LOGS}-uart0.log \
	-C bp.pl011_uart1.out_file=${LOGS}-uart1.log \
	-C bp.pl011_uart2.out_file=${LOGS}-uart2.log \
	-C bp.vis.disable_visualisation=true \
	-C bp.terminal_0.start_telnet=false \
	-C bp.terminal_1.start_telnet=false \
	-C bp.terminal_2.start_telnet=false \
	-C bp.terminal_3.start_telnet=false \
	-C bp.pl011_uart2.shutdown_tag="END OF ACS"
}

run_fvp ${WORKSPACE}/fip_sp_sel1.bin $SP_SEL1_LOGS
run_fvp ${WORKSPACE}/fip_sp_sel0.bin $SP_SEL0_LOGS
