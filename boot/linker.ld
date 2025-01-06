ENTRY(start)

SECTIONS {
	/* Multiboot2 header needs to be stored at 1 Mib offset */
	. = 1M;
	.multiboot2_section : {
		KEEP(*(.multiboot2_section))
	}

	.text : {
		*(.text)
	}
}
