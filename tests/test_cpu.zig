const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

pub inline fn parseHexDump(comptime hex_dump: []const u8) []const u8 {
    var output = [_]u8{0} ** hex_dump.len;
    var idx: usize = 0;

    var iter = mem.tokenizeAny(u8, hex_dump, " \n");
    while (iter.next()) |num_lit| {
        if (num_lit[num_lit.len -| 1] == ':') continue;
        output[idx] = fmt.parseInt(u8, num_lit, 16) catch {
            std.debug.panic(
                "cannot parse `{s}` into a hexdecimal integer",
                .{num_lit},
            );
        };
        idx += 1;
    }

    return output[0..idx];
}

test "6502 cpu tests" {
    _ = @import("cpu/load_and_store.zig");
    _ = @import("cpu/adc_inst.zig");
    _ = @import("cpu/sbc_inst.zig");
    _ = @import("cpu/branch_and_jump.zig");
    _ = @import("cpu/stack.zig");
    _ = @import("cpu/rule110.zig");
}
