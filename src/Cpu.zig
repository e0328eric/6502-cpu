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
    I: bool = true,
    D: bool = false,
    B: bool = true,
    Unused: bool = true,
    V: bool = false,
    N: bool = false,
};

const STACK_TOP: u16 = 0x0100;

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
    self.sp = 0xFD;
    self.status = StatusReg{};
    self.bus = try allocator.create(CpuBus);
    self.bus.init();

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.destroy(self.bus);
}

pub fn loadProgram(self: Self, program: []const u8) !void {
    try self.bus.loadProgram(program);
    self.bus.write16Bit(0xFFFC, 0x8000);
}

pub fn reset(self: *Self) void {
    self.sp -%= 3;
    self.status.I = true;
    self.pc = self.bus.read16Bit(0xFFFC);
}

pub fn loadAndRun(self: *Self, program: []const u8) !void {
    try self.loadProgram(program);
    self.reset();

    while (true) {
        const opcode = self.bus.readByte(self.pc) orelse return error.InvalidProgCounter;
        self.pc += 1;

        self.runOnce(opcode);
    }
}

const SetFlagInfo = struct {
    reg: u8,
    flag: u8,
};

inline fn isReg(comptime reg: u8) bool {
    return reg == 'a' or reg == 'x' or reg == 'y';
}

fn setFlag(self: *Self, comptime info: SetFlagInfo) void {
    if (!isReg(info.reg)) {
        @compileError("`info.reg` should be either `a`, `x`, or `y`.");
    }
    const reg_name = "reg_" ++ [_]u8{info.reg};

    switch (info.flag) {
        'C' => undefined,
        'Z' => if (@field(self, reg_name) == 0) {
            self.status.Z = true;
        } else {
            self.status.Z = false;
        },
        'I' => undefined,
        'D' => undefined,
        'B' => undefined,
        'V' => undefined,
        'N' => if (@field(self, reg_name) & 0x80 != 0) {
            self.status.N = true;
        } else {
            self.status.N = false;
        },
        else => @compileError("Invalid `info.flag` was found"),
    }
}

const AddressingMode = enum(u8) {
    NoneAddressing = 0,
    Immediate,
    ZeroPage,
    ZeroPageX,
    ZeroPageY,
    Absolute,
    AbsoluteX,
    AbsoluteY,
    IndirectX,
    IndirectY,
};

fn getOperandAddress(self: Self, mode: AddressingMode) u16 {
    return switch (mode) {
        .NoneAddressing => null,
        .Immediate => self.pc,
        .ZeroPage => @as(u16, self.bus.readByte(self.pc)),
        .Absolute => self.bus.read16Bit(self.pc),
        .ZeroPageX => blk: {
            const pos = self.bus.readByte(self.pc);
            break :blk @as(u16, pos +% self.reg_x);
        },
        .ZeroPageY => blk: {
            const pos = self.bus.readByte(self.pc);
            break :blk @as(u16, pos +% self.reg_y);
        },
        .AbsoluteX => blk: {
            const pos = self.bus.read16Bit(self.pc);
            break :blk pos +% @as(u16, self.reg_x);
        },
        .AbsoluteY => blk: {
            const pos = self.bus.read16Bit(self.pc);
            break :blk pos +% @as(u16, self.reg_y);
        },
        .IndirectX => blk: {
            const pos = self.bus.readByte(self.pc);

            const hi = hi: {
                const hi_pos = @as(u16, pos +% self.reg_x +% 1);
                break :hi self.bus.read16Bit(hi_pos);
            };
            const lo = lo: {
                const lo_pos = @as(u16, pos +% self.reg_x);
                break :lo self.bus.read16Bit(lo_pos);
            };

            break :blk hi << 8 | lo;
        },
        .IndirectY => blk: {
            const hi = self.bus.readByte(self.pc +% 1);
            const lo = self.bus.readByte(self.pc);

            break :blk (@as(u16, hi) << 8 | @as(u16, lo)) +% @as(u16, self.reg_y);
        },
    };
}

fn runOnce(self: *Self, opcode: u8) void {
    switch (opcode) {
        // NOP instruction
        0xEA => {},

        // LDA instruction
        0xA9 => self.ldInst('a', .Immediate),
        0xA5 => self.ldInst('a', .ZeroPage),
        0xB5 => self.ldInst('a', .ZeroPageX),
        0xAD => self.ldInst('a', .Absolute),
        0xBD => self.ldInst('a', .AbsoluteX),
        0xB9 => self.ldInst('a', .AbsoluteY),
        0xA1 => self.ldInst('a', .IndirectX),
        0xB1 => self.ldInst('a', .IndirectY),

        // LDX instruction
        0xA2 => self.ldInst('x', .Immediate),
        0xA6 => self.ldInst('x', .ZeroPage),
        0xB6 => self.ldInst('x', .ZeroPageY),
        0xAE => self.ldInst('x', .Absolute),
        0xBE => self.ldInst('x', .AbsoluteY),

        // LDY instruction
        0xA0 => self.ldInst('y', .Immediate),
        0xA4 => self.ldInst('y', .ZeroPage),
        0xB4 => self.ldInst('y', .ZeroPageX),
        0xAC => self.ldInst('y', .Absolute),
        0xBC => self.ldInst('y', .AbsoluteX),

        // STA instruction
        0x85 => self.stInst('a', .ZeroPage),
        0x95 => self.stInst('a', .ZeroPageX),
        0x8D => self.stInst('a', .Absolute),
        0x9D => self.stInst('a', .AbsoluteX),
        0x99 => self.stInst('a', .AbsoluteY),
        0x81 => self.stInst('a', .IndirectX),
        0x91 => self.stInst('a', .IndirectY),

        // STX instruction
        0x86 => self.stInst('x', .ZeroPage),
        0x96 => self.stInst('x', .ZeroPageY),
        0x8E => self.stInst('x', .Absolute),

        // STY instruction
        0x84 => self.stInst('y', .ZeroPage),
        0x94 => self.stInst('y', .ZeroPageX),
        0x8C => self.stInst('y', .Absolute),
    }
}

fn ldInst(self: *Self, comptime reg: u8, addr_mode: AddressingMode) void {
    if (!isReg(reg)) {
        @compileError("`reg` should be either `a`, `x`, or `y`.");
    }

    const reg_name = "reg_" ++ [_]u8{reg};
    const addr = self.getOperandAddress(addr_mode);
    @field(self, reg_name) = self.bus.readByte(addr);

    self.setFlag(.{ .reg = reg, .flag = 'Z' });
    self.setFlag(.{ .reg = reg, .flag = 'N' });

    switch (addr_mode) {
        .Immediate => self.pc += 1,
        .ZeroPage => self.pc += 1,
        .ZeroPageX => self.pc += 1,
        .ZeroPageY => self.pc += 1,
        .Absolute => self.pc += 2,
        .AbsoluteX => self.pc += 2,
        .AbsoluteY => self.pc += 2,
        .IndirectX => self.pc += 1,
        .IndirectY => self.pc += 1,
        else => unreachable,
    }
}

fn stInst(self: *Self, comptime reg: u8, addr_mode: AddressingMode) void {
    if (!isReg(reg)) {
        @compileError("`reg` should be either `a`, `x`, or `y`.");
    }

    const reg_name = "reg_" ++ [_]u8{reg};
    const addr = self.getOperandAddress(addr_mode);
    self.bus.writeByte(addr, @field(self, reg_name));

    switch (addr_mode) {
        .ZeroPage => self.pc += 1,
        .ZeroPageX => self.pc += 1,
        .ZeroPageY => self.pc += 1,
        .Absolute => self.pc += 2,
        .AbsoluteX => self.pc += 2,
        .AbsoluteY => self.pc += 2,
        .IndirectX => self.pc += 1,
        .IndirectY => self.pc += 1,
        else => unreachable,
    }
}
