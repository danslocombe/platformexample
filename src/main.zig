const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    rl.SetConfigFlags(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);

    rl.InitWindow(640, 480, "Linden");

    rl.SetConfigFlags(rl.ConfigFlags.FLAG_VSYNC_HINT);
    //rl.SetExitKey(rl.KeyboardKey.KEY_NULL);

    //rl.InitAudioDevice();
    //rl.SetMasterVolume(0.75);

    var framebuffer = rl.LoadRenderTexture(consts.screen_width, consts.screen_height);

    var game = Game{
        .player = Player{ .pos = .{
            .x = 20,
            .y = 20,
        } },
        .particles = std.ArrayList(Particle).init(gpa.allocator()),
    };

    while (!rl.WindowShouldClose()) {
        {
            game.tick();

            // draw game to framebuffer
            rl.BeginTextureMode(framebuffer);
            game.draw();
            rl.EndTextureMode();
        }

        draw_framebuffer_to_screen(&framebuffer);
    }
    rl.CloseWindow();
}

pub const ground_y = 150;

pub const Game = struct {
    player: Player,
    particles: std.ArrayList(Particle),

    pub fn tick(self: *Game) void {
        var dt = rl.GetFrameTime();
        self.player.tick(dt);
    }

    pub fn draw(self: *Game) void {
        rl.DrawRectangle(0, 0, consts.screen_width, consts.screen_height, consts.pico_sea);
        rl.DrawRectangle(0, ground_y, consts.screen_width, consts.screen_height - ground_y, consts.pico_black);

        self.player.draw();
    }
};

pub const Player = struct {
    pos: rl.Vector2,
    vel: rl.Vector2 = .{ .x = 0, .y = 0 },

    hitbox_width: f32 = 8.0,
    hitbox_height: f32 = 8.0,

    draw_width: f32 = 8.0,
    draw_height: f32 = 8.0,

    pub fn tick(self: *Player, dt: f32) void {
        const grav = 850;
        const grav_down = grav * 1.25;

        if (self.pos.y + self.hitbox_height * 0.5 >= ground_y) {
            // On ground
            self.vel.y = 0;

            if (rl.IsKeyDown(rl.KeyboardKey.KEY_UP)) {
                self.vel.y = -500;
            }
        } else {
            if (self.vel.y > 0) {
                self.vel.y += grav_down * dt;
            } else {
                self.vel.y += grav * dt;
            }
        }

        const fric_high = 0.9985;
        _ = fric_high;
        const fric_base = 0.9995;
        const fric_base_x = 0.9988;

        const move_force = 1500;

        var fric_x: f32 = fric_base_x;

        if (rl.IsKeyDown(rl.KeyboardKey.KEY_LEFT)) {
            self.vel.x -= move_force * dt;
            //fric_x = fric_high;
        } else if (rl.IsKeyDown(rl.KeyboardKey.KEY_RIGHT)) {
            self.vel.x += move_force * dt;
            //fric_x = fric_high;
        } else {
            fric_x = fric_base_x;
        }

        self.pos.x += self.vel.x * dt;
        self.pos.y += self.vel.y * dt;

        if (self.pos.y + self.hitbox_height * 0.5 >= ground_y) {
            self.pos.y = ground_y - self.hitbox_height * 0.5;
            self.vel.y = 0;
        }

        self.vel.y *= fric_base;
        self.vel.x *= fric_x;
    }

    pub fn draw(self: *Player) void {
        var p = .{
            .x = self.pos.x - self.draw_width * 0.5,
            .y = self.pos.y - self.draw_height * 0.5,
        };

        rl.DrawRectangleV(p, .{ .x = self.draw_width, .y = self.draw_height }, consts.pico_white);
    }
};

pub const Particle = struct {
    pos: rl.Vector2,
    t: i32 = 0,
};

//const ScreenShader = struct {
//    shader: rl.Shader,
//    iTime: i32 = 0,
//    shader_iTime_loc: c_int,
//    shader_amp_loc: c_int,
//};

fn draw_framebuffer_to_screen(framebuffer: *rl.RenderTexture2D) void {
    rl.BeginDrawing();
    rl.ClearBackground(consts.pico_black);

    var rl_screen_width_f = @as(f32, @floatFromInt(rl.GetScreenWidth()));
    var rl_screen_height_f = @as(f32, @floatFromInt(rl.GetScreenHeight()));
    var screen_scale = @min(rl_screen_width_f / consts.screen_width_f, rl_screen_height_f / consts.screen_height_f);

    var source_width = @as(f32, @floatFromInt(framebuffer.texture.width));

    // This minus is needed to avoid flipping the rendering (for some reason)
    var source_height = -@as(f32, @floatFromInt(framebuffer.texture.height));
    var source = rl.Rectangle{ .x = 0.0, .y = 0.0, .width = source_width, .height = source_height };

    var destination = rl.Rectangle{
        .x = (rl_screen_width_f - consts.screen_width_f * screen_scale) * 0.5,
        .y = (rl_screen_height_f - consts.screen_height_f * screen_scale) * 0.5,
        .width = consts.screen_width_f * screen_scale,
        .height = consts.screen_height_f * screen_scale,
    };

    rl.DrawTexturePro(framebuffer.texture, source, destination, .{ .x = 0.0, .y = 0.0 }, 0.0, rl.WHITE);
    rl.EndDrawing();
}
