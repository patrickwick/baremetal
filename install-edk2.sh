#!/bin/bash
#
# Build OVMF from EDK2
# Prerequisits:
# apt install build-essential uuid-dev iasl git nasm python-is-python3 libx11-dev libxext-dev
#
# Docs: https://github.com/tianocore/edk2/blob/stable/202408/OvmfPkg/README

set -e

EDK2_DIR=edk2
EDK2_CONFIG=edk2_config

if [[ ! -d "${EDK2_DIR}" ]]; then
	git clone \
		https://github.com/tianocore/edk2.git \
		--recursive \
		--branch stable/202408 \
		--depth 1 \
		${EDK2_DIR}
fi

cd ${EDK2_DIR}
source ./edksetup.sh

# base tools
make -j$(nproc) --directory ./BaseTools
export EDK_TOOLS_PATH=$(pwd)/BaseTools
cp ../${EDK2_CONFIG}/target.txt ./Conf/target.txt

# X64
build --conf=./Conf \
	--platform=OvmfPkg/OvmfPkgX64.dsc \
	--arch=X64 \
	--tagname=CLANGDWARF

# RISCV64
build --conf=./Conf \
	--platform=OvmfPkg/RiscVVirt/RiscVVirtQemu.dsc \
	--arch=RISCV64 \
	--tagname=CLANGDWARF
