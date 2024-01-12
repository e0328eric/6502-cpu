const std = @import("std");
const rl = @import("raylib.zig");

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;

pub fn main() void {
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

    const CpuBus = @import("./bus.zig").CpuBus;

    const bus = CpuBus.init();
    _ = bus.readByte(0x0888);
}
