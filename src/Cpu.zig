const std = @import("std");

const CpuBus = @import("./bus.zig").CpuBus;
const Allocator = std.mem.Allocator;

// NOTE: reference: https://www.nesdev.org/wiki/Status_flags
//
//  7  bit  0
//  ---- ----
//  NV1B DIZC
//  |||| ||||
//  |||| |||+- Carry
//  |||| ||+-- Zero
//  |||| |+--- Interrupt Disable
//  |||| +---- Decimal
//  |||+------ (No CPU effect; see: the B flag)
//  ||+------- (No CPU effect; always pushed as 1)
//  |+-------- Overflow
//  +--------- Negative

pub const StatusReg = packed struct {
    C: bool = false,
    Z: bool = false,
    I: bool = false,
    D: bool = false,
    B: bool = false,
    Unused: bool = true,
    V: bool = false,
    N: bool = false,
};

allocator: Allocator,
reg_a: u8,
reg_x: u8,
reg_y: u8,
pc: u16,
sp: u8,
status: StatusReg,
bus: *CpuBus,

const Self = @This();

pub fn init(allocator: Allocator) !Self {
    var self: Self = undefined;

    self.allocator = allocator;
    self.reg_a = 0;
    self.reg_x = 0;
    self.reg_y = 0;
    self.pc = 0;
    self.sp = 0;
    self.status = StatusReg{};
    self.bus = try allocator.create(CpuBus);

    self.bus.init();

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.destroy(self.bus);
}
