const std = @import("std");
const CpuBus = @import("pixeka").bus.CpuBus;

const testing_allocator = std.testing.allocator;
const expect = std.testing.expect;

test "read and write (cpubus)" {
    const bus = try testing_allocator.create(CpuBus);
    defer testing_allocator.destroy(bus);

    // IO with ram
    bus.writeByte(0x0001, 0xFD);
    var read_byte_in_ram = bus.readByte(0x0001);
    try expect(read_byte_in_ram == 0xFD);

    bus.writeByte(0x0123, 0xA8);
    read_byte_in_ram = bus.readByte(0x0123);
    try expect(read_byte_in_ram == 0xA8);

    bus.write16Bit(0x0122, 0xABCD);
    const read_byte_in_ram_16bit = bus.read16Bit(0x0122);
    read_byte_in_ram = bus.readByte(0x0123);
    try expect(read_byte_in_ram_16bit == 0xABCD);
    try expect(read_byte_in_ram == 0xAB);

    // IO with cartridge
    bus.writeByte(0x8012, 0xFD);
    var read_byte_in_cartridge = bus.readByte(0x8012);
    try expect(read_byte_in_cartridge == 0xFD);

    bus.writeByte(0x9A23, 0xA8);
    read_byte_in_cartridge = bus.readByte(0x9A23);
    try expect(read_byte_in_cartridge == 0xA8);

    bus.write16Bit(0x9A22, 0xABCD);
    const read_byte_in_cartridge_16bit = bus.read16Bit(0x9A22);
    read_byte_in_cartridge = bus.readByte(0x9A23);
    try expect(read_byte_in_cartridge_16bit == 0xABCD);
    try expect(read_byte_in_cartridge == 0xAB);
}
