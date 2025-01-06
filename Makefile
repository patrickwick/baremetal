BUILD_DIR=build
ISO=${BUILD_DIR}/entry.iso

BOOT_OBJ=${BUILD_DIR}/boot_x86_64.o
MAIN_OBJ=${BUILD_DIR}/main.o
BIN=${BUILD_DIR}/iso/boot/entry.bin

LD=ld
LD_FLAGS+=-n
LD_FLAGS+=--nmagic
LD_FLAGS+=-O0
LD_FLAGS+=-static
LD_FLAGS+=-z noexecstack
LD_FLAGS+=-nostdlib
LD_FLAGS+=--verbose

ASM=nasm
ASM_FLAGS=-f elf64
ASM_FLAGS+=-g

RUSTC=rustc
# NOTE: SSE is allowed, the boot loader already enables it
RUSTC_FLAGS+=--target x86_64-unknown-none
RUSTC_FLAGS+=-C debuginfo=2
RUSTC_FLAGS+=-C opt-level=0
RUSTC_FLAGS+=-C no-redzone=true
RUSTC_FLAGS+=-C panic=abort

QEMU=qemu-system-x86_64
QEMU_FLAGS+=-cpu max
QEMU_FLAGS+=-m 1280000k
# Q35 mainboard for ACPI with PCIe entries
QEMU_FLAGS+=-machine q35
QEMU_FLAGS+=-cpu Broadwell
QEMU_FLAGS+=-netdev user,id=n2
QEMU_FLAGS+=-device virtio-net-pci,netdev=n2,id=n2-dev,mac=de:ad:de:ad:af:fe
QEMU_FLAGS+=-device virtio-rng-pci
QEMU_FLAGS+=-vga virtio
QEMU_FLAGS+=-serial stdio
QEMU_FLAGS+=-usb
# virtio block device
 QEMU_FLAGS+=-drive file=${BUILD_DIR}/virtio.qcow2,if=virtio
# single cpu
QEMU_FLAGS+=-smp 1

# debug
QEMU_FLAGS+=-no-reboot
QEMU_FLAGS+=--gdb tcp::1234
QEMU_FLAGS+=-d guest_errors,cpu_reset,unimp,mmu,page,strace,nochain,plugin,pcall
QEMU_FLAGS+=-D ${BUILD_DIR}/qemu_log.txt

# dump network packets
QEMU_FLAGS+=-object filter-dump,id=n2,netdev=n2,file=./build/virtio_network.dump

QEMU_FIRMWARE=./edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF.fd

all: qemu

help: ## Prints help for targets with comments
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

firmware: ${QEMU_FIRMWARE} ## Build firmware
${QEMU_FIRMWARE}:
	./install-edk2.sh

${BUILD_DIR}:
	mkdir -p ${BUILD_DIR}
	qemu-img create -f qcow2 ${BUILD_DIR}/virtio.qcow2 256M

${BOOT_OBJ}: boot/boot_x86_64.asm ${BUILD_DIR}
	${ASM} ${ASM_FLAGS} -o ${BOOT_OBJ} boot/boot_x86_64.asm

.PHONY: ${MAIN_OBJ}
${MAIN_OBJ}: ${BUILD_DIR}
	${RUSTC} --emit obj ${RUSTC_FLAGS} -o ${MAIN_OBJ} ./main.rs

${ISO}: ${MAIN_OBJ} ${BOOT_OBJ} ${BUILD_DIR}
	# NOTE: must use iso/boot subdirectory due to grub-mkrescue / xorriso magic
	mkdir -p ${BUILD_DIR}/iso/boot/grub
	cp boot/grub.cfg ${BUILD_DIR}/iso/boot/grub
	${LD} ${LD_FLAGS} -o ${BIN} --script boot/linker.ld ${MAIN_OBJ} ${BOOT_OBJ}
	grub-mkrescue -v -o ${ISO} ${BUILD_DIR}/iso

.PHONY: qemu
qemu: ${ISO} ${QEMU_FIRMWARE} ## Run Qemu emulation
	${QEMU} ${QEMU_FLAGS} \
		-accel kvm \
		--bios ${QEMU_FIRMWARE} \
		-cdrom ${ISO}

# without acceleration, pause on startup
.PHONY: debug
debug: ${ISO} ${QEMU_FIRMWARE} ## Debug in Qemu without acceleration. Pause on start
	${QEMU} ${QEMU_FLAGS} \
		-S \
		--bios ${QEMU_FIRMWARE} \
		-cdrom ${ISO}

.PHONY: gdb
gdb: ## Arrach Gdb to the current Qemu session
	# NOTE: must use hb for hardware breakpoints in entry code
	gdb ${BIN} \
		-ex "hb main::panic" \
		-ex "set disassembly-flavor intel" \
		-ex "set disassemble-next-line on" \
		-ex "target remote tcp::1234"

