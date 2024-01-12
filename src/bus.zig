const std = @import("std");
const assert = std.debug.assert;

const CPU_RAM_CAPACITY: usize = 0x800;
const CARTRIDGE_CAPACITY: usize = 0xBFE0;

pub fn isMemory(comptime T: type) bool {
    return @hasDecl(T, "readByte") and @hasDecl(T, "writeByte");
}

comptime {
    assert(isMemory(CpuBus)); // CpuBus should be a `memory`
}
pub const CpuBus = struct {
    ram: [CPU_RAM_CAPACITY]u8,
    cartridge_space: [CARTRIDGE_CAPACITY]u8,

    const Self = @This();

    pub fn init(self: *Self) void {
        self.ram = [_]u8{0} ** CPU_RAM_CAPACITY;
        self.cartridge_space = [_]u8{0} ** CARTRIDGE_CAPACITY;
    }

    pub fn readByte(self: Self, addr: u16) ?u8 {
        return switch (addr) {
            // actural ram location
            0x0000...0x07FF => self.ram[addr],

            // ram mirroring
            0x0800...0x0FFF => self.ram[addr - 0x0800],
            0x1000...0x17FF => self.ram[addr - 0x1000],
            0x1800...0x1FFF => self.ram[addr - 0x1800],

            // cartridge space
            0x4020...0xFFFF => self.cartridge_space[addr - 0x4020],
            else => null,
        };
    }

    pub fn writeByte(self: *Self, addr: u16, val: u8) void {
        return switch (addr) {
            // actural ram location
            0x0000...0x07FF => self.ram[addr] = val,

            // ram mirroring
            0x0800...0x0FFF => self.ram[addr - 0x0800] = val,
            0x1000...0x17FF => self.ram[addr - 0x1000] = val,
            0x1800...0x1FFF => self.ram[addr - 0x1800] = val,

            // cartridge space
            0x4020...0xFFFF => self.cartridge_space[addr - 0x4020] = val,
            else => {},
        };
    }
};
