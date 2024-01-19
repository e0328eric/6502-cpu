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

pub const FlagReg = packed struct {
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
const STACK_RESET: u8 = 0xFD;

allocator: Allocator,
reg_a: u8,
reg_x: u8,
reg_y: u8,
pc: u16,
sp: u8,
flags: FlagReg,
bus: *CpuBus,

const Self = @This();

pub fn init(allocator: Allocator) !Self {
    var self: Self = undefined;

    self.allocator = allocator;
    self.reg_a = 0;
    self.reg_x = 0;
    self.reg_y = 0;
    self.pc = 0;
    self.sp = STACK_RESET;
    self.flags = FlagReg{};
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
    self.sp = STACK_RESET;
    self.flags.I = true;
    self.pc = self.bus.read16Bit(0xFFFC);
}

pub fn loadAndRun(self: *Self, program: []const u8) !void {
    try self.loadProgram(program);
    self.reset();

    while (true) {
        const opcode = self.bus.readByte(self.pc);
        self.pc += 1;

        // TODO: make an interrupt request and remove this line
        if (opcode == 0x00) break; // BRK instruction

        self.runOnce(opcode);
    }
}

const SetFlagInfo = union(enum) {
    is_carried: bool,
    zeroed_data: u8,
    neged_data: u8,
    overflowed_data: struct {
        a: u8,
        b: u8,
        result: u8,
    },
};

inline fn isReg(comptime reg: u8) bool {
    return reg == 'a' or reg == 'x' or reg == 'y';
}

fn setFlag(
    self: *Self,
    comptime flag: u8,
    info: SetFlagInfo,
) void {
    switch (flag) {
        'C' => self.flags.C = info.is_carried,
        'Z' => if (info.zeroed_data == 0) {
            self.flags.Z = true;
        } else {
            self.flags.Z = false;
        },
        'I' => undefined,
        'D' => undefined,
        'B' => undefined,
        'V' => {
            const is_overflowed = ((info.overflowed_data.a ^ info.overflowed_data.result) &
                (info.overflowed_data.b ^ info.overflowed_data.result)) >> 7 == 1;
            self.flags.V = is_overflowed;
        },
        'N' => if (info.neged_data & 0x80 != 0) {
            self.flags.N = true;
        } else {
            self.flags.N = false;
        },
        else => @compileError("Invalid `flag` was found"),
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

fn getOperandAddress(self: Self, comptime mode: AddressingMode) u16 {
    return switch (mode) {
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
        else => @compileError("`NoneAddressing` is not supported in this function."),
    };
}

inline fn incPc(self: *Self, comptime addr_mode: AddressingMode) void {
    switch (addr_mode) {
        .NoneAddressing => {},
        .Immediate => self.pc += 1,
        .ZeroPage => self.pc += 1,
        .ZeroPageX => self.pc += 1,
        .ZeroPageY => self.pc += 1,
        .Absolute => self.pc += 2,
        .AbsoluteX => self.pc += 2,
        .AbsoluteY => self.pc += 2,
        .IndirectX => self.pc += 1,
        .IndirectY => self.pc += 1,
    }
}

fn runOnce(self: *Self, opcode: u8) void {
    switch (opcode) {
        // NOP instruction
        0xEA => {},

        // BRK instruction
        // TODO: make an interrupt request
        0x00 => {
            self.flags.B = true;
            return;
        },

        // setting flag instrictions
        0x38 => self.flags.C = true, // SEC
        0xF8 => self.flags.D = true, // SED
        0x78 => self.flags.I = true, // SEI

        // increment value

        // ADC instruction
        0x69 => self.adc(.Immediate),
        0x65 => self.adc(.ZeroPage),
        0x75 => self.adc(.ZeroPageX),
        0x6D => self.adc(.Absolute),
        0x7D => self.adc(.AbsoluteX),
        0x79 => self.adc(.AbsoluteY),
        0x61 => self.adc(.IndirectX),
        0x71 => self.adc(.IndirectY),

        // SBC instruction
        0xE9 => self.sbc(.Immediate),
        0xE5 => self.sbc(.ZeroPage),
        0xF5 => self.sbc(.ZeroPageX),
        0xED => self.sbc(.Absolute),
        0xFD => self.sbc(.AbsoluteX),
        0xF9 => self.sbc(.AbsoluteY),
        0xE1 => self.sbc(.IndirectX),
        0xF1 => self.sbc(.IndirectY),

        // AND instruction
        0x29 => self.bitOpInst('&', .Immediate),
        0x25 => self.bitOpInst('&', .ZeroPage),
        0x35 => self.bitOpInst('&', .ZeroPageX),
        0x2D => self.bitOpInst('&', .Absolute),
        0x3D => self.bitOpInst('&', .AbsoluteX),
        0x39 => self.bitOpInst('&', .AbsoluteY),
        0x21 => self.bitOpInst('&', .IndirectX),
        0x31 => self.bitOpInst('&', .IndirectY),

        // ORA instruction
        0x09 => self.bitOpInst('|', .Immediate),
        0x05 => self.bitOpInst('|', .ZeroPage),
        0x15 => self.bitOpInst('|', .ZeroPageX),
        0x0D => self.bitOpInst('|', .Absolute),
        0x1D => self.bitOpInst('|', .AbsoluteX),
        0x19 => self.bitOpInst('|', .AbsoluteY),
        0x01 => self.bitOpInst('|', .IndirectX),
        0x11 => self.bitOpInst('|', .IndirectY),

        // EOR instruction
        0x49 => self.bitOpInst('^', .Immediate),
        0x45 => self.bitOpInst('^', .ZeroPage),
        0x55 => self.bitOpInst('^', .ZeroPageX),
        0x4D => self.bitOpInst('^', .Absolute),
        0x5D => self.bitOpInst('^', .AbsoluteX),
        0x59 => self.bitOpInst('^', .AbsoluteY),
        0x41 => self.bitOpInst('^', .IndirectX),
        0x51 => self.bitOpInst('^', .IndirectY),

        // ASL instruction
        0x0A => self.asl(.NoneAddressing),
        0x06 => self.asl(.ZeroPage),
        0x16 => self.asl(.ZeroPageX),
        0x0E => self.asl(.Absolute),
        0x1E => self.asl(.AbsoluteX),

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

        // transfer instructions
        0xAA => self.transferInst('a', 'x'), // TAX
        0xA8 => self.transferInst('a', 'y'), // TAY
        0xBA => self.transferInst('s', 'x'), // TSX
        0x8A => self.transferInst('x', 'a'), // TXA
        0x9A => self.transferInst('x', 's'), // TXS
        0x98 => self.transferInst('y', 'a'), // TYA

        else => @panic("not yet implemented"),
    }
}

fn adc(self: *Self, comptime addr_mode: AddressingMode) void {
    const addr = self.getOperandAddress(addr_mode);

    const old_reg_a = self.reg_a;
    const memory_data = self.bus.readByte(addr);

    const add_with_overflow = blk: {
        const tmp1 = @addWithOverflow(old_reg_a, memory_data);
        const tmp2 = @addWithOverflow(tmp1[0], @as(u8, @intFromBool(self.flags.C)));
        break :blk .{ tmp2[0], @as(bool, @bitCast(tmp1[1] | tmp2[1])) };
    };

    self.reg_a = add_with_overflow[0];

    self.setFlag('Z', .{ .zeroed_data = self.reg_a });
    self.setFlag('N', .{ .neged_data = self.reg_a });
    self.setFlag('C', .{ .is_carried = add_with_overflow[1] });
    self.setFlag('V', .{ .overflowed_data = .{
        .a = old_reg_a,
        .b = memory_data,
        .result = add_with_overflow[0],
    } });

    self.incPc(addr_mode);
}

// NOTE: see https://web.archive.org/web/20200129081101/http://users.telenet.be:80/kim1-6502/6502/proman.html#222
// 6502 manual page 15
fn sbc(self: *Self, comptime addr_mode: AddressingMode) void {
    const addr = self.getOperandAddress(addr_mode);

    const old_reg_a = self.reg_a;
    const memory_data = self.bus.readByte(addr);

    const sub_with_overflow = blk: {
        const tmp1 = @addWithOverflow(old_reg_a, ~memory_data);
        const tmp2 = @addWithOverflow(tmp1[0], @as(u8, @intFromBool(self.flags.C)));
        break :blk .{ tmp2[0], @as(bool, @bitCast(tmp1[1] | tmp2[1])) };
    };

    self.reg_a = sub_with_overflow[0];

    self.setFlag('Z', .{ .zeroed_data = self.reg_a });
    self.setFlag('N', .{ .neged_data = self.reg_a });
    self.setFlag('C', .{ .is_carried = sub_with_overflow[1] });
    self.setFlag('V', .{ .overflowed_data = .{
        .a = old_reg_a,
        .b = ~memory_data,
        .result = sub_with_overflow[0],
    } });

    self.incPc(addr_mode);
}

fn bitOpInst(
    self: *Self,
    comptime op_type: u8,
    comptime addr_mode: AddressingMode,
) void {
    const addr = self.getOperandAddress(addr_mode);

    switch (op_type) {
        '&' => self.reg_a &= self.bus.readByte(addr),
        '|' => self.reg_a |= self.bus.readByte(addr),
        '^' => self.reg_a ^= self.bus.readByte(addr),
        else => @compileError("`op_type` should be either '&', '|', or '^'."),
    }

    self.setFlag('Z', .{ .zeroed_data = self.reg_a });
    self.setFlag('N', .{ .neged_data = self.reg_a });

    self.incPc(addr_mode);
}

fn asl(self: *Self, comptime addr_mode: AddressingMode) void {
    var shled_data: struct { u8, u1 } = undefined;
    if (addr_mode == .NoneAddressing) {
        shled_data = @shlWithOverflow(self.reg_a, 1);
        self.reg_a = shled_data[0];
    } else {
        const addr = self.getOperandAddress(addr_mode);

        shled_data = @shlWithOverflow(self.bus.readByte(addr), 1);
        self.bus.writeByte(addr, shled_data[0]);
    }
    self.setFlag('Z', .{ .zeroed_data = shled_data[0] });
    self.setFlag('N', .{ .neged_data = shled_data[0] });
    self.setFlag('C', .{ .is_carried = shled_data[1] == 1 });

    self.incPc(addr_mode);
}

fn ldInst(self: *Self, comptime reg: u8, comptime addr_mode: AddressingMode) void {
    if (!isReg(reg)) {
        @compileError("`reg` should be either `a`, `x`, or `y`.");
    }

    const reg_name = "reg_" ++ [_]u8{reg};
    const addr = self.getOperandAddress(addr_mode);
    @field(self, reg_name) = self.bus.readByte(addr);

    self.setFlag('Z', .{ .zeroed_data = @field(self, reg_name) });
    self.setFlag('N', .{ .neged_data = @field(self, reg_name) });

    self.incPc(addr_mode);
}

fn stInst(self: *Self, comptime reg: u8, comptime addr_mode: AddressingMode) void {
    if (!isReg(reg)) {
        @compileError("`reg` should be either `a`, `x`, or `y`.");
    }

    const reg_name = "reg_" ++ [_]u8{reg};
    const addr = self.getOperandAddress(addr_mode);
    self.bus.writeByte(addr, @field(self, reg_name));

    self.incPc(addr_mode);
}

fn transferInst(self: *Self, comptime from_reg: u8, comptime into_reg: u8) void {
    if (!isReg(from_reg) and from_reg != 's') {
        @compileError("`from_reg` should be either `a`, `x`, `y` or 's'.");
    }
    if (!isReg(into_reg) and into_reg != 's') {
        @compileError("`into_reg` should be either `a`, `x`, `y` or 's'.");
    }
    if (from_reg == into_reg) {
        @compileError("`from_reg` and `into_reg` should be different.");
    }

    const from_reg_name = if (from_reg == 's') "sp" else "reg_" ++ [_]u8{from_reg};
    const into_reg_name = if (into_reg == 's') "sp" else "reg_" ++ [_]u8{into_reg};

    @field(self, into_reg_name) = @field(self, from_reg_name);

    if (into_reg != 's') {
        self.setFlag('Z', .{ .zeroed_data = @field(self, into_reg_name) });
        self.setFlag('N', .{ .neged_data = @field(self, into_reg_name) });
    }
}
