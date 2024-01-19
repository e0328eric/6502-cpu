const std = @import("std");
const Cpu = @import("pixeka").Cpu;
const parseHexDump = @import("../test_cpu.zig").parseHexDump;

const testing_allocator = std.testing.allocator;
const expect = std.testing.expect;

// Program Assembly
// lda #$2
// ldx #$1
// sta $10
// stx $15
// ldx #$0
// lda #20
// sec
// loop:
//   inx
//   sbc $10
//   bne loop
// stx $0200
// ldy $01F6,X
// brk
test "bne instruction" {
    const program_str =
        \\0600: a9 02 a2 01 85 10 86 15 a2 00 a9 14 38 e8 e5 10
        \\0610: d0 fb 8e 00 02 bc f6 01 00
    ;
    const program = parseHexDump(program_str);

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRun(false, program);

    // expected registers
    try expect(cpu.reg_a == 0x00);
    try expect(cpu.reg_x == 0x0A);
    try expect(cpu.reg_y == 0x0A);

    // expected datas in ram
    try expect(cpu.bus.readByte(0x0010) == 0x02);
    try expect(cpu.bus.readByte(0x0015) == 0x01);
    try expect(cpu.bus.readByte(0x0200) == 0x0A);
}

// Program Assembly
// ldx #$10
// jmp here
// ldy #$FE
// brk
// here:
//     lda #$06
//     ldx #$05
//     stx $0200
//     sta $0201
//     jmp ($0200)
test "jmp instruction" {
    const program_str =
        \\0600: a2 10 4c 08 06 a0 fe 00 a9 06 a2 05 8e 00 02 8d
        \\0610: 01 02 6c 00 02
    ;
    const program = parseHexDump(program_str);

    var cpu = try Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.loadAndRunAt(.@"test", false, program);

    // expected registers
    try expect(cpu.reg_a == 0x06);
    try expect(cpu.reg_x == 0x05);
    try expect(cpu.reg_y == 0xFE);
}
