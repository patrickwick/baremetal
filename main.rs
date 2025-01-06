#![no_main]
#![no_std]

use core::arch::asm;

fn halt() -> ! {
    loop {
        unsafe { asm!("cli", "hlt") };
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    halt();
}

#[no_mangle]
pub extern "C" fn main() -> ! {
    // Bootloader passes the multiboot2 address via rax
    let mut multiboot2_info_physical_address: u64;
    unsafe {
        asm!(
            "mov {address}, rax",
            address = out(reg) multiboot2_info_physical_address
        );
    }

    initialize_essentials(multiboot2_info_physical_address);

    halt();
}

// Initialize serial output and exception interrupts ASAP
fn initialize_essentials(_multiboot2_info_physical_address: u64) {
    // TODO: NYI
}
