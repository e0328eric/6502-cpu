const std = @import("std");
const rl = @import("raylib.zig");

const Cpu = @import("./Cpu.zig");
const CpuBus = @import("./bus.zig").CpuBus;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;

pub fn main() !void {
    if (false) {
        rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "foo");
        defer rl.CloseWindow();

        rl.SetTargetFPS(60);

        while (!rl.WindowShouldClose()) {
            {
                rl.BeginDrawing();
                defer rl.EndDrawing();

                rl.ClearBackground(rl.RAYWHITE);
                rl.DrawText("This is a first window using zig", 190, 200, 20, rl.LIGHTGRAY);
            }
        }
    }

    const allocator = std.heap.c_allocator;

    const cpu = try Cpu.init(allocator);
    defer cpu.deinit();
}

test "pixeka testing" {
    _ = @import("./bus.zig");
    _ = @import("./Cpu.zig");
}
