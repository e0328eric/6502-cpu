const std = @import("std");
const Cpu = @import("pixeka").Cpu;
const parseHexDump = @import("../test_cpu.zig").parseHexDump;

const testing_allocator = std.testing.allocator;
const expect = std.testing.expect;

// Program Assembly
//
// lda #$01
// sta $0200
// ldx #$05
// stx $0201
// ldy #$08
// sty $0202
//
// sta $0203
// lda $0202
// sta $0200
// ldx $0203
// stx $0202
// ldy $0201
// sty $0203
//
// brk
test "load and store (immediate, absolute)" {
    const program_str =
        \\0600: a9 01 8d 00 02 a2 05 8e 01 02 a0 08 8c 02 02 8d
        \\0610: 03 02 ad 02 02 8d 00 02 ae 03 02 8e 02 02 ac 01
        \\0620: 02 8c 03 02 00
    ;
    const program = parseHexDump(program_str);

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRunAt(.@"test", false, program);

    // expected registers
    try expect(cpu.reg_a == 0x08);
    try expect(cpu.reg_x == 0x01);
    try expect(cpu.reg_y == 0x05);

    // expected program counter
    try expect(cpu.pc == 0x0625);
}

// Program Assembly
// ldx #$01
// ldy #$02
//
// stx $17
// sty $18
//
// lda #$ab
// ldx #$02
// sta ($15, X)
//
// ldy $0201
//
// brk
test "load and store (zero page, indirect X)" {
    const program_str =
        \\0600: a2 01 a0 02 86 17 84 18 a9 ab a2 02 81 15 ac 01
        \\0610: 02 00
    ;
    const program = parseHexDump(program_str);

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRun(false, program);

    // expected registers
    try expect(cpu.reg_a == 0xAB);
    try expect(cpu.reg_x == 0x02);
    try expect(cpu.reg_y == 0xAB);
}

// Program Assembly
// ldx #$FF
// ldy #$01
//
// stx $15
// ldx #$01
// sty $16
//
// lda #$ab
// ldy #$02
// sta ($15), Y
//
// ldx $0201
//
// brk
test "load and store (zero page X, indirect Y)" {
    const program_str =
        \\0600: a2 ff a0 01 86 15 a2 01 94 15 a9 ab a0 02 91 15
        \\0610: ae 01 02 00
    ;
    const program = parseHexDump(program_str);

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRun(false, program);

    // expected registers
    try expect(cpu.reg_a == 0xAB);
    try expect(cpu.reg_x == 0xAB);
    try expect(cpu.reg_y == 0x02);
}
