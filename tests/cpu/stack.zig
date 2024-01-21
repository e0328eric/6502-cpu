const std = @import("std");
const Cpu = @import("pixeka").Cpu;
const parseHexDump = @import("../test_cpu.zig").parseHexDump;

const testing_allocator = std.testing.allocator;
const expect = std.testing.expect;

// Program Assembly
// lda #$01
// sta $51
// sta $53
// sta $67
// sta $6E
//
// jsr draw_palette
// brk
//
// draw_palette:
//     pha
//     php
// draw_palette_loop:
//     lda $50, X
//     sta $0200, X
//     lda #$20
//     sta $65
//     inx
//     cpx $65
//     bcc draw_palette_loop
//     plp
//     pla
//     rts
test "simple stack access" {
    const program_str =
        \\0600: a9 01 85 51 85 53 85 67 85 6e 20 0e 06 00 48 08
        \\0610: b5 50 9d 00 02 a9 20 85 65 e8 e4 65 90 f2 28 68
        \\0620: 60
    ;
    const program = parseHexDump(program_str);

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRunAt(.@"test", false, program);

    // expected registers
    try expect(cpu.reg_a == 0x01);
    try expect(cpu.reg_x == 0x20);
    try expect(cpu.reg_y == 0x00);

    // expected datas in ram
    try expect(cpu.bus.readByte(0x0201) == 0x01);
    try expect(cpu.bus.readByte(0x0203) == 0x01);
    try expect(cpu.bus.readByte(0x0217) == 0x01);
    try expect(cpu.bus.readByte(0x021E) == 0x01);
}
