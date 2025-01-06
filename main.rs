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
    const DEFAULT_DIVISOR: u16 = 12; // 115200 / DEFAULT_BAUD (9600);
    const DIVISOR_LATCH_LOW: u16 = 0;
    const DIVISOR_LATCH_HIGH: u16 = 1;
    const DIVISOR_LATCH_BIT: u8 = 1 << 7;

    // COM1 / ttyS0 / QEMU serial0
    let port: SerialPort = SerialPort::Com1;

    outb(0x03, port_command(port, Command::LineControl));
    outb(0x00, port_command(port, Command::InterruptEnable));
    outb(0x00, port_command(port, Command::InterruptIdFifoControl));
    outb(0x03, port_command(port, Command::ModemControl));

    let control = inb(port_command(port, Command::LineControl));
    outb(control | DIVISOR_LATCH_BIT, port_command(port, Command::LineControl));
    outb((DEFAULT_DIVISOR & 0xff) as u8, port as u16 + DIVISOR_LATCH_LOW);
    outb(((DEFAULT_DIVISOR >> 8) & 0xff) as u8, port as u16 + DIVISOR_LATCH_HIGH);
    outb(control & (!DIVISOR_LATCH_BIT), port_command(port, Command::LineControl));

    // test
    outb(b't', port as u16);
    outb(b'e', port as u16);
    outb(b's', port as u16);
    outb(b't', port as u16);
}

fn port_command(port: SerialPort, command: Command) -> u16 {
    port as u16 + command as u16
}

fn outb(value: u8, port: u16) {
    unsafe {
        asm!(
            "out dx, al",
            in("dx") port,
            in("al") value,
        );
    };
}

fn inb(port: u16) -> u8 {
    let out: u8;
    unsafe {
        asm!("inb dx",
             in("dx") port,
            out("al") out,
        )
    };
    out
}

#[repr(u16)]
#[derive(Copy, Clone, Debug)]
enum SerialPort {
    Com1 = 0x3f8,
    Com2 = 0x2f8,
    Com3 = 0x3e8,
    Com4 = 0x2e8,
    Com5 = 0x5f8,
    Com6 = 0x4f8,
    Com7 = 0x5e8,
    Com8 = 0x4e8,
}

#[repr(u16)]
#[derive(Copy, Clone, Debug)]
enum Command {
    WriteRead = 0,
    InterruptEnable = 1,
    InterruptIdFifoControl = 2,
    LineControl = 3,
    ModemControl = 4,
    LineStatus = 5,
    ModemStatus = 6,
}
