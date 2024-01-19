const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

pub inline fn parseHexDump(comptime hex_dump: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(50000);
        var output = [_]u8{0} ** hex_dump.len;
        var idx = 0;

        var iter = mem.tokenizeAny(u8, hex_dump, " \n");
        while (iter.next()) |num_lit| {
            if (num_lit[num_lit.len -| 1] == ':') continue;
            output[idx] = fmt.parseInt(u8, num_lit, 16) catch {
                @compileError(fmt.comptimePrint(
                    "cannot parse {s} into a hexdecimal integer",
                    .{num_lit},
                ));
            };
            idx += 1;
        }

        return output[0..idx];
    }
}

test "6502 cpu tests" {
    _ = @import("./cpu/load_and_store.zig");
    _ = @import("./cpu/adc_inst.zig");
    _ = @import("./cpu/sbc_inst.zig");
}
