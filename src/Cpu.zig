const std = @import("std");

const CpuBus = @import("./bus.zig").CpuBus;
const ProgramLocation = @import("./bus.zig").ProgramLocation;
const Allocator = std.mem.Allocator;

const STACK_TOP: u16 = 0x0100;
const STACK_RESET: u8 = 0xFD;

// NOTE: reference: https://www.nesdev.org/wiki/Status_flags
//
//  7  bit  0
//  ---- ----
//  NV1B DIZC
//  |||| ||||
//  |||| |||+- Carry
//  |||| ||+-- Zero
//  |||| |+--- Interrupt Disable
//  |||| +---- Decimal (NO Effect in NES)
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

pub fn loadAndRun(self: *Self, comptime dump_reg: bool, program: []const u8) !void {
    return self.loadAndRunAt(.real, dump_reg, program);
}

pub fn loadAndRunAt(
    self: *Self,
    comptime program_location: ProgramLocation,
    comptime dump_reg: bool,
    program: []const u8,
) !void {
    try self.loadProgramAt(program_location, program);
    self.reset();

    while (true) {
        const opcode = self.bus.readByte(self.pc);
        self.pc += 1;

        if (dump_reg) self.dumpCpuStatus();

        // TODO: make an interrupt request and remove this line
        if (opcode == 0x00) break; // BRK instruction

        self.runOnce(opcode);
    }
}

fn loadProgramAt(
    self: Self,
    comptime program_location: ProgramLocation,
    program: []const u8,
) !void {
    try self.bus.loadProgramAt(program_location, program);
    const addr = switch (program_location) {
        .real => 0x8000,
        .@"test" => 0x0600,
    };
    self.bus.write16Bit(0xFFFC, addr);
}

fn reset(self: *Self) void {
    self.sp = STACK_RESET;
    self.flags.I = true;
    self.pc = self.bus.read16Bit(0xFFFC);
}

fn dumpCpuStatus(self: Self) void {
    std.debug.print("=======================\n", .{});
    std.debug.print("<main registers>\na: ${x}, x: ${x}, y: ${x}\n", .{
        self.reg_a,
        self.reg_x,
        self.reg_y,
    });
    std.debug.print("<pointers>\npc: ${x}, sp: ${x}\n", .{
        self.pc,
        self.sp,
    });
    std.debug.print("<flag registers>\n", .{});
    std.debug.print("NV_BDIZC\n{b:0>8}\n", .{@as(u8, @bitCast(self.flags))});
    std.debug.print("=======================\n\n", .{});
}

inline fn isReg(comptime reg: u8) bool {
    return reg == 'a' or reg == 'x' or reg == 'y';
}

inline fn isFlag(comptime flag: u8) bool {
    return switch (flag) {
        'C', 'Z', 'I', 'D', 'B', 'V', 'N' => true,
        else => false,
    };
}

const SetFlagInfo = union(enum) {
    is_carried: bool,
    zeroed_data: u8,
    neged_data: u8,
    is_overflowed: bool,
    calc_overflow: struct {
        a: u8,
        b: u8,
        result: u8,
    },
};

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
        'V' => switch (info) {
            .is_overflowed => |info_data| self.flags.V = info_data,
            .calc_overflow => |info_data| {
                const is_overflowed = ((info_data.a ^ info_data.result) &
                    (info_data.b ^ info_data.result)) >> 7 == 1;
                self.flags.V = is_overflowed;
            },
            else => unreachable, // NOTE: SetFlagInfo should not be taken from IO
        },
        'N' => if (info.neged_data & 0x80 != 0) {
            self.flags.N = true;
        } else {
            self.flags.N = false;
        },
        else => @compileError("invalid `flag` was found."),
    }
}

const AddressingMode = enum(u8) {
    NoneAddressing = 0,
    Immediate,
    Relative,
    ZeroPage,
    ZeroPageX,
    ZeroPageY,
    Absolute,
    AbsoluteX,
    AbsoluteY,
    Indirect,
    IndirectX,
    IndirectY,
};

fn getOperandAddress(self: Self, comptime mode: AddressingMode) u16 {
    return switch (mode) {
        .Immediate, .Relative => self.pc,
        .ZeroPage => @as(u16, self.bus.readByte(self.pc)),
        .ZeroPageX => blk: {
            const pos = self.bus.readByte(self.pc);
            break :blk @as(u16, pos +% self.reg_x);
        },
        .ZeroPageY => blk: {
            const pos = self.bus.readByte(self.pc);
            break :blk @as(u16, pos +% self.reg_y);
        },
        .Absolute => self.bus.read16Bit(self.pc),
        .AbsoluteX => blk: {
            const pos = self.bus.read16Bit(self.pc);
            break :blk pos +% @as(u16, self.reg_x);
        },
        .AbsoluteY => blk: {
            const pos = self.bus.read16Bit(self.pc);
            break :blk pos +% @as(u16, self.reg_y);
        },
        .Indirect => blk: {
            const pos = self.bus.read16Bit(self.pc);
            break :blk self.bus.read16Bit(pos);
        },
        .IndirectX => blk: {
            const pos = self.bus.readByte(self.pc);

            const hi = self.bus.readByte(@as(u16, pos +% self.reg_x +% 1));
            const lo = self.bus.readByte(@as(u16, pos +% self.reg_x));

            break :blk @as(u16, hi) << 8 | @as(u16, lo);
        },
        .IndirectY => blk: {
            const pos = self.bus.readByte(self.pc);

            const hi = self.bus.readByte(@as(u16, pos +% 1));
            const lo = self.bus.readByte(@as(u16, pos));

            break :blk (@as(u16, hi) << 8 | @as(u16, lo)) +% @as(u16, self.reg_y);
        },
        else => @compileError("`NoneAddressing` is not supported in this function."),
    };
}

inline fn incPc(self: *Self, comptime addr_mode: AddressingMode) void {
    switch (addr_mode) {
        .NoneAddressing => {},
        .Absolute, .AbsoluteX, .AbsoluteY, .Indirect => self.pc += 2,
        else => self.pc += 1,
    }
}

fn runOnce(self: *Self, opcode: u8) void {
    switch (opcode) {
        // NOP instruction
        0xEA => {},

        // BRK instruction
        0x00 => {
            self.pc += 1;
            self.push(true, self.pc);

            var flags = self.flags;
            flags.B = true;
            self.push(false, @as(u8, @bitCast(flags)));
            self.flags.I = true;

            self.pc = self.bus.read16Bit(0xFFFE);
        },

        // RTI instruction
        0x40 => {
            self.flags = @bitCast(self.pop(false));
            self.pc = self.pop(true);
        },

        // setting flag instrictions
        0x38 => self.flags.C = true, // SEC
        0xF8 => self.flags.D = true, // SED
        0x78 => self.flags.I = true, // SEI

        // clearing flag instructions
        0x18 => self.flags.C = false, // CLC
        0xD8 => self.flags.D = false, // CLD
        0x58 => self.flags.I = false, // CLI
        0xB8 => self.flags.V = false, // CLV

        // increment and decrement operators
        // INC instruction
        0xE6 => self.increment('m', .ZeroPage),
        0xF6 => self.increment('m', .ZeroPageX),
        0xEE => self.increment('m', .Absolute),
        0xFE => self.increment('m', .AbsoluteX),
        0xE8 => self.increment('x', .NoneAddressing), // INX
        0xC8 => self.increment('y', .NoneAddressing), // INY
        // DEC instruction
        0xC6 => self.increment('m', .ZeroPage),
        0xD6 => self.increment('m', .ZeroPageX),
        0xCE => self.increment('m', .Absolute),
        0xDE => self.increment('m', .AbsoluteX),
        0xCA => self.decrement('x', .NoneAddressing), // DEX
        0x88 => self.decrement('y', .NoneAddressing), // DEY

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

        // LSR instruction
        0x4A => self.lsr(.NoneAddressing),
        0x46 => self.lsr(.ZeroPage),
        0x56 => self.lsr(.ZeroPageX),
        0x4E => self.lsr(.Absolute),
        0x5E => self.lsr(.AbsoluteX),

        // ROL instruction
        0x2A => self.rol(.NoneAddressing),
        0x26 => self.rol(.ZeroPage),
        0x36 => self.rol(.ZeroPageX),
        0x2E => self.rol(.Absolute),
        0x3E => self.rol(.AbsoluteX),

        // ROR instruction
        0x6A => self.rol(.NoneAddressing),
        0x66 => self.rol(.ZeroPage),
        0x76 => self.rol(.ZeroPageX),
        0x6E => self.rol(.Absolute),
        0x7E => self.rol(.AbsoluteX),

        // BIT instruction
        0x24 => self.bit(.ZeroPage),
        0x2C => self.bit(.Absolute),

        // jump instructions
        // JMP instruction
        0x4C => self.pc = self.getOperandAddress(.Absolute),
        0x6C => self.pc = self.getOperandAddress(.Indirect),
        0x20 => self.jsr(), // JSR
        0x60 => self.rts(), // RTS

        // branch instructions
        0x90 => self.branchIf('C', false), // BCC
        0xB0 => self.branchIf('C', true), // BCS
        0xD0 => self.branchIf('Z', false), // BNE
        0xF0 => self.branchIf('Z', true), // BEQ
        0x10 => self.branchIf('N', false), // BPL
        0x30 => self.branchIf('N', true), // BMI
        0x50 => self.branchIf('V', false), // BVC
        0x70 => self.branchIf('V', true), // BVS

        // compare instructions
        // CMP instruction
        0xC9 => self.compare('a', .Immediate),
        0xC5 => self.compare('a', .ZeroPage),
        0xD5 => self.compare('a', .ZeroPageX),
        0xCD => self.compare('a', .Absolute),
        0xDD => self.compare('a', .AbsoluteX),
        0xD9 => self.compare('a', .AbsoluteY),
        0xC1 => self.compare('a', .IndirectX),
        0xD1 => self.compare('a', .IndirectY),

        // CPX instruction
        0xE0 => self.compare('x', .Immediate),
        0xE4 => self.compare('x', .ZeroPage),
        0xEC => self.compare('x', .Absolute),

        // CPY instruction
        0xC0 => self.compare('y', .Immediate),
        0xC4 => self.compare('y', .ZeroPage),
        0xCC => self.compare('y', .Absolute),

        // stack manipulation
        // PHA instruction
        0x48 => self.push(false, self.reg_a),

        // PLA instruction
        0x68 => {
            self.reg_a = self.pop(false);
            self.setFlag('Z', .{ .zeroed_data = self.reg_a });
            self.setFlag('N', .{ .neged_data = self.reg_a });
        },

        // PHP instruction
        0x08 => {
            const flags_data: u8 = @bitCast(self.flags);
            self.push(false, flags_data);
        },

        // PLP instruction
        0x28 => {
            const flag_data = self.pop(false);
            self.flags = @bitCast(flag_data);
        },

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
    const old_reg_a = self.reg_a;
    const memory_data = self.bus.readByte(self.getOperandAddress(addr_mode));

    const add_with_overflow = blk: {
        const tmp1 = @addWithOverflow(old_reg_a, memory_data);
        const tmp2 = @addWithOverflow(tmp1[0], @as(u8, @intFromBool(self.flags.C)));
        break :blk .{ tmp2[0], @as(bool, @bitCast(tmp1[1] | tmp2[1])) };
    };

    self.reg_a = add_with_overflow[0];

    self.setFlag('Z', .{ .zeroed_data = self.reg_a });
    self.setFlag('N', .{ .neged_data = self.reg_a });
    self.setFlag('C', .{ .is_carried = add_with_overflow[1] });
    self.setFlag('V', .{ .calc_overflow = .{
        .a = old_reg_a,
        .b = memory_data,
        .result = add_with_overflow[0],
    } });

    self.incPc(addr_mode);
}

// NOTE: see https://web.archive.org/web/20200129081101/http://users.telenet.be:80/kim1-6502/6502/proman.html#222
// 6502 manual page 15
fn sbc(self: *Self, comptime addr_mode: AddressingMode) void {
    const old_reg_a = self.reg_a;
    const memory_data = self.bus.readByte(self.getOperandAddress(addr_mode));

    const sub_with_overflow = blk: {
        const tmp1 = @addWithOverflow(old_reg_a, ~memory_data);
        const tmp2 = @addWithOverflow(tmp1[0], @as(u8, @intFromBool(self.flags.C)));
        break :blk .{ tmp2[0], @as(bool, @bitCast(tmp1[1] | tmp2[1])) };
    };

    self.reg_a = sub_with_overflow[0];

    self.setFlag('Z', .{ .zeroed_data = self.reg_a });
    self.setFlag('N', .{ .neged_data = self.reg_a });
    self.setFlag('C', .{ .is_carried = sub_with_overflow[1] });
    self.setFlag('V', .{ .calc_overflow = .{
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

fn lsr(self: *Self, comptime addr_mode: AddressingMode) void {
    var rored_data: struct { u8, u1 } = undefined;

    if (addr_mode == .NoneAddressing) {
        rored_data[1] = @truncate(self.reg_a | 1);
        self.reg_a >>= 1;
        rored_data[0] = self.reg_a;
    } else {
        const addr = self.getOperandAddress(addr_mode);
        const addr_data = self.bus.readByte(addr);

        rored_data[1] = @truncate(addr_data | 1);
        rored_data[0] = addr_data >> 1;
        self.bus.writeByte(addr, rored_data[0]);
    }

    self.setFlag('Z', .{ .zeroed_data = rored_data[0] });
    self.setFlag('N', .{ .neged_data = rored_data[0] });
    self.setFlag('C', .{ .is_carried = rored_data[1] == 1 });

    self.incPc(addr_mode);
}

fn rol(self: *Self, comptime addr_mode: AddressingMode) void {
    var roled_data: struct { u8, u1 } = undefined;
    const padding: u8 = @intCast(@intFromBool(self.flags.C));

    if (addr_mode == .NoneAddressing) {
        roled_data = @shlWithOverflow(self.reg_a, 1);
        roled_data[0] |= padding;

        self.reg_a = roled_data[0];
    } else {
        const addr = self.getOperandAddress(addr_mode);
        roled_data = @shlWithOverflow(self.bus.readByte(addr), 1);
        roled_data[0] |= padding;

        self.bus.writeByte(addr, roled_data[0]);
    }

    self.setFlag('Z', .{ .zeroed_data = roled_data[0] });
    self.setFlag('N', .{ .neged_data = roled_data[0] });
    self.setFlag('C', .{ .is_carried = roled_data[1] == 1 });

    self.incPc(addr_mode);
}

fn ror(self: *Self, comptime addr_mode: AddressingMode) void {
    var rored_data: struct { u8, u1 } = undefined;
    const padding: u8 = @as(u8, @intCast(@intFromBool(self.flags.C))) << 7;

    if (addr_mode == .NoneAddressing) {
        rored_data[1] = @truncate(self.reg_a | 1);
        rored_data[0] = (self.reg_a >> 1) | padding;

        self.reg_a = rored_data[0];
    } else {
        const addr = self.getOperandAddress(addr_mode);
        const addr_data = self.bus.readByte(addr);

        rored_data[1] = @truncate(addr_data | 1);
        rored_data[0] = (addr_data >> 1) | padding;
        self.bus.writeByte(addr, rored_data[0]);
    }

    self.setFlag('Z', .{ .zeroed_data = rored_data[0] });
    self.setFlag('N', .{ .neged_data = rored_data[0] });
    self.setFlag('C', .{ .is_carried = rored_data[1] == 1 });

    self.incPc(addr_mode);
}

fn bit(self: *Self, comptime addr_mode: AddressingMode) void {
    const addr_val = self.bus.readByte(self.getOperandAddress(addr_mode));
    const val = addr_val & self.reg_a;

    self.setFlag('Z', .{ .zeroed_data = val });
    self.setFlag('N', .{ .neged_data = addr_val });
    self.setFlag('V', .{ .is_overflowed = addr_val & 0x40 != 0 });

    self.incPc(addr_mode);
}

fn jsr(self: *Self) void {
    const addr = self.getOperandAddress(.Absolute);

    self.push(false, @as(u8, @truncate((self.pc + 1) >> 8)));
    self.push(false, @as(u8, @truncate((self.pc + 1) & 0xFF)));

    self.pc = addr;
}

fn rts(self: *Self) void {
    const lo = self.pop(false);
    const hi = self.pop(false);

    self.pc = (@as(u16, hi) << 8 | @as(u16, lo)) + 1;
}

fn increment(
    self: *Self,
    comptime reg: u8,
    comptime addr_mode: AddressingMode,
) void {
    if (reg != 'x' and reg != 'y' and reg != 'm') {
        @compileError("`reg` should be either `x`, `y` or `m`.");
    }

    if (reg == 'm') {
        const addr = self.getOperandAddress(addr_mode);
        const val = self.bus.readByte(addr) +% 1;
        self.bus.writeByte(addr, val);

        self.setFlag('Z', .{ .zeroed_data = val });
        self.setFlag('N', .{ .neged_data = val });
    } else {
        const reg_name = "reg_" ++ [_]u8{reg};
        @field(self, reg_name) +%= 1;

        self.setFlag('Z', .{ .zeroed_data = @field(self, reg_name) });
        self.setFlag('N', .{ .neged_data = @field(self, reg_name) });
    }

    self.incPc(addr_mode);
}

fn decrement(
    self: *Self,
    comptime reg: u8,
    comptime addr_mode: AddressingMode,
) void {
    if (reg != 'x' and reg != 'y' and reg != 'm') {
        @compileError("`reg` should be either `x`, `y` or `m`.");
    }

    if (reg == 'm') {
        const addr = self.getOperandAddress(addr_mode);
        const val = self.bus.readByte(addr) -% 1;
        self.bus.writeByte(addr, val);

        self.setFlag('Z', .{ .zeroed_data = val });
        self.setFlag('N', .{ .neged_data = val });
    } else {
        const reg_name = "reg_" ++ [_]u8{reg};
        @field(self, reg_name) -%= 1;

        self.setFlag('Z', .{ .zeroed_data = @field(self, reg_name) });
        self.setFlag('N', .{ .neged_data = @field(self, reg_name) });
    }

    self.incPc(addr_mode);
}

fn compare(self: *Self, comptime reg: u8, comptime addr_mode: AddressingMode) void {
    if (!isReg(reg)) {
        @compileError("`reg` should be either `a`, `x`, or `y`.");
    }

    const reg_name = "reg_" ++ [_]u8{reg};
    const addr_val = self.bus.readByte(self.getOperandAddress(addr_mode));
    const val = @subWithOverflow(@field(self, reg_name), addr_val);

    self.setFlag('C', .{ .is_carried = val[1] == 0 });
    self.setFlag('Z', .{ .zeroed_data = val[0] });
    self.setFlag('N', .{ .neged_data = val[0] });

    self.incPc(addr_mode);
}

fn push(self: *Self, comptime is_16bit: bool, val: anytype) void {
    if (is_16bit) {
        self.bus.write16Bit(STACK_TOP + @as(u16, self.sp -% 1), val);
        self.sp -%= 2;
    } else {
        self.bus.writeByte(STACK_TOP + @as(u16, self.sp), val);
        self.sp -%= 1;
    }
}

fn pop(self: *Self, comptime is_16bit: bool) if (is_16bit) u16 else u8 {
    if (is_16bit) {
        self.sp +%= 2;
        return self.bus.read16Bit(STACK_TOP + @as(u16, self.sp -% 1));
    } else {
        self.sp +%= 1;
        return self.bus.readByte(STACK_TOP + @as(u16, self.sp));
    }
}

fn branchIf(
    self: *Self,
    comptime flag_kind: u8,
    comptime required_set: bool,
) void {
    if (!isFlag(flag_kind)) {
        @compileError("invalid `flag_kind` was found.");
    }

    const flag_str = [_]u8{flag_kind};

    if (@field(self.flags, &flag_str) == required_set) {
        const pc_offset = self.bus.readByte(self.pc);
        if (@as(i8, @bitCast(pc_offset)) < 0) {
            self.pc -|= @as(u16, ~pc_offset + 1);
        } else {
            self.pc += @as(u16, pc_offset);
        }
    }

    self.incPc(.Relative);
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
