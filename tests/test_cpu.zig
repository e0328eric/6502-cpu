const std = @import("std");

const Cpu = @import("pixeka").Cpu;

const testing_allocator = std.testing.allocator;
const expect = std.testing.expect;

// NOTE: programs are generated from https://skilldrick.github.io/easy6502
test "load and store instructions" {
    // Program Assembly
    //
    // LDA #$01
    // STA $0200
    // LDX #$05
    // STX $0201
    // LDY #$08
    // STY $0202
    //
    // STA $0203
    // LDA $0202
    // STA $0200
    // LDX $0203
    // STX $0202
    // LDY $0201
    // STY $0203
    //
    // BRK
    //
    // zig fmt: off
    const program = [_]u8{
        0xA9, 0x01, 0x8D, 0x00, 0x02, 0xA2, 0x05, 0x8E, 0x01, 0x02, 0xA0, 0x08,
        0x8C, 0x02, 0x02, 0x8D, 0x03, 0x02, 0xAD, 0x02, 0x02, 0x8D, 0x00, 0x02,
        0xAE, 0x03, 0x02, 0x8E, 0x02, 0x02, 0xAC, 0x01, 0x02, 0x8C, 0x03, 0x02,
        0x00,
    };
    // zig fmt: on

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRun(&program);

    // expected registers
    try expect(cpu.reg_a == 0x08);
    try expect(cpu.reg_x == 0x01);
    try expect(cpu.reg_y == 0x05);

    // expected program counter
    try expect(cpu.pc == 0x8025);
}

test "ADC instruction (basic)" {
    // Program Assembly
    //
    // LDA #$81
    // STA $0200
    // ADC $0200
    //
    // BRK
    //
    // zig fmt: off
    const program = [_]u8{0xA9, 0x81, 0x8D, 0x00, 0x02, 0x6D, 0x00, 0x02, 0x00};
    // zig fmt: on

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRun(&program);

    // expected registers
    try expect(cpu.reg_a == 0x02);

    // expected flags
    try expect(!cpu.flags.N);
    try expect(cpu.flags.V);
    try expect(cpu.flags.B);
    try expect(!cpu.flags.D);
    try expect(cpu.flags.I);
    try expect(!cpu.flags.Z);
    try expect(cpu.flags.C);
}

test "SBC instruction" {
    // Program Assembly
    //
    //LDA #$81
    //STA $0200
    //ADC $0200
    //
    //TAX
    //
    //ASL A
    //ASL $0200
    //ASL $0200
    //
    //SEC
    //SBC $0200
    //
    //TXA
    //
    //LDX $0200
    //
    //BRK
    //
    // zig fmt: off
    const program = [_]u8{
        0xA9, 0x81, 0x8D, 0x00, 0x02, 0x6D, 0x00, 0x02, 0xAA, 0x0A, 0x0E, 0x00,
        0x02, 0x0E, 0x00, 0x02, 0x38, 0xED, 0x00, 0x02, 0x8A, 0xAE, 0x00, 0x02,
        0x00,
    };
    // zig fmt: on

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRun(&program);

    // expected registers
    try expect(cpu.reg_a == 0x02);
    try expect(cpu.reg_x == 0x04);

    // expected flags
    try expect(!cpu.flags.N);
    try expect(!cpu.flags.V);
    try expect(cpu.flags.B);
    try expect(!cpu.flags.D);
    try expect(cpu.flags.I);
    try expect(!cpu.flags.Z);
    try expect(cpu.flags.C);
}
