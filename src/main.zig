const std = @import("std");
const rl = @import("raylib");

const FroggyRand = @import("froggy_rand.zig").FroggyRand;
const consts = @import("consts.zig");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub var particle_frames: []rl.Texture = &.{};

pub fn main() anyerror!void {
    rl.SetConfigFlags(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);

    rl.InitWindow(640, 480, "Linden");

    rl.SetTargetFPS(144);
    //rl.SetConfigFlags(rl.ConfigFlags.FLAG_VSYNC_HINT);
    //rl.SetExitKey(rl.KeyboardKey.KEY_NULL);

    //rl.InitAudioDevice();
    //rl.SetMasterVolume(0.75);

    particle_frames = load_frames("dust.png");

    var framebuffer = rl.LoadRenderTexture(consts.screen_width, consts.screen_height);

    var game = Game{
        .player = Player{
            .pos = .{
                .x = 20,
                .y = 20,
            },
            .pos_prev = .{
                .x = 20,
                .y = 20,
            },
        },

        .particles = std.ArrayList(Particle).init(gpa.allocator()),
        .particles_dead = std.bit_set.DynamicBitSet.initEmpty(gpa.allocator(), 4) catch unreachable,
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

const ground_y = 150;

const camera_min_x = -100;
const camera_max_x = 500;
const camera_min_y = -100;
const camera_max_y = 500;

pub const Game = struct {
    t: i32 = 0,

    player: Player,

    camera_x: f32 = 0,
    camera_y: f32 = 0,
    camera_zoom: f32 = 1,

    particles: std.ArrayList(Particle),
    particles_dead: std.bit_set.DynamicBitSet,

    pub fn tick(self: *Game) void {
        self.t += 1;

        var dt = rl.GetFrameTime();
        const sixty_fps_dt: f32 = 1.0 / 60.0;
        var dt_norm = dt / sixty_fps_dt;

        //std.debug.print("{d}\n", .{dt});
        self.player.tick(self, dt_norm);

        for (self.particles.items, 0..) |*p, i| {
            if (self.particles_dead.isSet(i)) {
                continue;
            }

            if (!p.tick(dt_norm)) {
                self.particles_dead.set(i);
            }
        }

        var target_camera_x = self.player.pos.x - consts.screen_width_f * 0.5;
        var target_camera_y = self.player.pos.y - consts.screen_height_f * 0.5;
        target_camera_x += self.player.vel.x * 15;
        target_camera_y += self.player.vel.y * 1;
        //var k = 1500 / (1 + dt);
        var k = 100 * dt_norm;
        self.camera_x = ease(self.camera_x, target_camera_x, k);
        self.camera_y = ease(self.camera_y, target_camera_y, k);

        self.camera_x = std.math.clamp(self.camera_x, camera_min_x, camera_max_x);
        self.camera_y = std.math.clamp(self.camera_y, camera_min_y, camera_max_y);
    }

    pub fn draw(self: *Game) void {
        var camera = rl.Camera2D{
            .target = rl.Vector2{ .x = self.camera_x + consts.screen_width_f * 0.5, .y = self.camera_y + consts.screen_height_f * 0.5 },
            .offset = rl.Vector2{ .x = consts.screen_width_f * 0.5, .y = consts.screen_height_f * 0.5 },
            .rotation = 0,
            .zoom = self.camera_zoom,
        };

        camera.Begin();
        //rl.DrawRectangle(camera_min_x, camera_min_y, camera_max_x + 500 - camera_min_x, camera_max_y + 200 - camera_min_y, consts.pico_sea);

        rl.ClearBackground(consts.pico_black);

        for (0..50) |i| {
            for (0..50) |j| {
                const w = 25;
                var color = consts.pico_sea;
                //if (((i % 2) == 0) ^ ((j % 2) == 0)) {
                var a = ((i % 2) == 0);
                var b = ((j % 2) == 0);
                // No xor :(
                if ((a or b) and !(a and b)) {
                    color = consts.pico_purple;
                }

                rl.DrawRectangle(@as(i32, @intCast(i)) * w, @as(i32, @intCast(j)) * w, w, w, color);
            }
        }

        rl.DrawRectangle(camera_min_x, ground_y, camera_max_x + 500 - camera_min_x, camera_max_y + 200 - ground_y, consts.pico_black);

        self.player.draw();

        for (self.particles.items, 0..) |*p, i| {
            if (self.particles_dead.isSet(i)) {
                continue;
            }

            p.draw();
        }

        camera.End();
    }

    pub fn create_particle(self: *Game, p_pos: rl.Vector2, n: usize, offset: f32) void {
        var rand = FroggyRand.init(0);

        for (0..n) |i| {
            var pos = p_pos;
            var theta = rand.gen_f32_uniform(.{ self.t, i }) * 3.141 * 2.0;
            pos.x += offset * std.math.cos(theta);
            pos.y += offset * std.math.sin(theta);

            var frame = rand.gen_usize_range(.{ self.t, i }, 0, particle_frames.len - 1);

            self.create_particle_internal(.{
                .frame = frame,
                .pos = pos,
            });
        }
    }

    pub fn create_particle_internal(self: *Game, particle: Particle) void {
        if (self.particles_dead.findFirstSet()) |i| {
            if (i < self.particles.items.len) {
                self.particles_dead.unset(i);
                self.particles.items[i] = particle;
                return;
            }
        }

        var index = self.particles.items.len;
        self.particles.append(particle) catch unreachable;
        if (self.particles.items.len > self.particles_dead.capacity()) {
            self.particles_dead.resize(self.particles_dead.capacity() * 2, true) catch unreachable;
        }

        self.particles_dead.unset(index);
    }
};

pub const Player = struct {
    pos: rl.Vector2,
    pos_prev: rl.Vector2,
    vel: rl.Vector2 = .{ .x = 0, .y = 0 },
    vel_prev: rl.Vector2 = .{ .x = 0, .y = 0 },

    hitbox_width: f32 = 8.0,
    hitbox_height: f32 = 8.0,

    draw_width: f32 = 8.0,
    draw_height: f32 = 8.0,

    pub fn tick(self: *Player, game: *Game, dt_norm: f32) void {
        const grav = 0.35;
        const grav_down = grav * 1.25;

        if (self.pos.y + self.hitbox_height * 0.5 >= ground_y) {
            // On ground
            self.vel.y = 0;

            if (rl.IsKeyDown(rl.KeyboardKey.KEY_UP)) {
                self.vel.y = -12;
                var pp = self.pos;
                pp.y += 8;
                game.create_particle(pp, 8, 5);
            } else {
                var rand = FroggyRand.init(0);
                if (rand.gen_f32_uniform(.{game.t}) < std.math.fabs(self.vel.x) * 0.03) {
                    var pp = self.pos;
                    pp.y += 5;
                    game.create_particle(pp, 1, 1);
                }
            }
        } else {
            if (self.vel.y > 0) {
                self.vel.y += grav_down * dt_norm;
            } else {
                self.vel.y += grav * dt_norm;
            }
        }

        const fric_base = 0.95;
        const fric_base_x = 0.90;

        const move_force = 0.45;

        var fric_x: f32 = fric_base_x;

        if (rl.IsKeyDown(rl.KeyboardKey.KEY_LEFT)) {
            self.vel.x -= move_force * dt_norm;
            //fric_x = fric_high;
        } else if (rl.IsKeyDown(rl.KeyboardKey.KEY_RIGHT)) {
            self.vel.x += move_force * dt_norm;
            //fric_x = fric_high;
        } else {
            fric_x = fric_base_x;
        }

        self.pos.x += self.vel.x * dt_norm;
        self.pos.y += self.vel.y * dt_norm;

        {
            if (self.pos.y + self.hitbox_height * 0.5 >= ground_y) {
                self.pos.y = ground_y - self.hitbox_height * 0.5;
                if (self.vel.y > 5) {
                    var pp = self.pos;
                    pp.y += 8;
                    game.create_particle(pp, 8, 5);
                }

                self.vel.y = 0;
            }

            var fric_power = dt_norm;
            var fric_apply_x = std.math.pow(f32, fric_base_x, fric_power);
            var fric_apply_y = std.math.pow(f32, fric_base, fric_power);

            self.vel.x *= fric_apply_x;
            self.vel.y *= fric_apply_y;
        }

        var delta_x = std.math.fabs(self.pos.x - self.pos_prev.x);
        var delta_y = std.math.fabs(self.pos.y - self.pos_prev.y);
        var max_delta: f32 = 0;
        var x_larger: bool = false;
        if (delta_x > delta_y) {
            x_larger = true;
            max_delta = delta_x;
        } else {
            x_larger = false;
            max_delta = delta_y;
        }
        //var max_delta: f32 = 0;
        //var x_larger: bool = false;
        //if (std.math.fabs(self.vel.x) > std.math.fabs(self.vel.y)) {
        //    x_larger = true;
        //    max_delta = std.math.fabs(self.vel.x);
        //} else {
        //    x_larger = false;
        //    max_delta = std.math.fabs(self.vel.y);
        //}

        var target_width_mult: f32 = 1;
        var target_height_mult: f32 = 1;
        const dk = 0.2;
        if (x_larger) {
            target_width_mult = 1 + max_delta * dk;
            target_height_mult = 1 / (target_width_mult);
        } else {
            target_height_mult = 1 + max_delta * dk;
            target_width_mult = 1 / (target_width_mult);
        }

        const k = 8;
        self.draw_width = ease(self.draw_width, self.hitbox_width * target_width_mult, k);
        self.draw_height = ease(self.draw_height, self.hitbox_height * target_height_mult, k);

        self.pos_prev = self.pos;
        self.vel_prev = self.vel;
    }

    pub fn draw(self: *Player) void {
        var p = .{
            .x = self.pos.x - self.draw_width * 0.5,
            .y = self.pos.y + self.hitbox_height * 0.5 - self.draw_height,
        };

        rl.DrawRectangleV(p, .{ .x = self.draw_width, .y = self.draw_height }, consts.pico_white);
    }
};

pub const Particle = struct {
    pos: rl.Vector2,
    t: i32 = 0,
    scale: f32 = 1.6,
    frame: usize = 0,

    pub fn tick(self: *Particle, dt_norm: f32) bool {
        self.pos.y -= 0.2 * dt_norm;
        self.scale = self.scale * std.math.pow(f32, 0.94, dt_norm);
        return self.scale > 0.0001;
    }

    pub fn draw(self: *Particle) void {
        var p = self.pos;
        p.x -= self.scale * 4;
        p.y -= self.scale * 4;
        draw_particle_frame_scaled(self.frame, p, self.scale, self.scale);
    }
};

fn draw_particle_frame_scaled(frame: usize, pos: rl.Vector2, scale_x: f32, scale_y: f32) void {
    var sprite = particle_frames[frame];
    var rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(sprite.width)) * std.math.sign(scale_x),
        .height = @as(f32, @floatFromInt(sprite.height)) * std.math.sign(scale_y),
    };

    var dest = rl.Rectangle{
        .x = pos.x,
        .y = pos.y,
        .width = @as(f32, @floatFromInt(sprite.width)) * std.math.fabs(scale_x),
        .height = @as(f32, @floatFromInt(sprite.height)) * std.math.fabs(scale_y),
    };

    var origin = rl.Vector2{ .x = 0, .y = 0 };
    var no_tint = rl.WHITE;
    rl.DrawTexturePro(sprite, rect, dest, origin, 0, no_tint);
}

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

    rl.DrawFPS(10, 10);
    rl.EndDrawing();
}

pub fn ease(x0: f32, x1: f32, k: f32) f32 {
    return (x1 + x0 * (k - 1)) / k;
}

fn load_frames(filename: [*c]const u8) []rl.Texture {
    var image = rl.LoadImage(filename);
    defer (rl.UnloadImage(image));

    var frame_count: usize = @intCast(@divFloor(image.width, image.height));

    var frame_w = @divFloor(image.width, @as(i32, @intCast(frame_count)));

    var frames = gpa.allocator().alloc(rl.Texture2D, frame_count) catch unreachable;

    for (0..frame_count) |iu| {
        var i: i32 = @intCast(iu);
        var xoff: f32 = @floatFromInt(i * frame_w);
        var frame_image = rl.ImageFromImage(image, rl.Rectangle{ .x = xoff, .y = 0, .width = @floatFromInt(frame_w), .height = @floatFromInt(image.height) });
        defer (rl.UnloadImage(frame_image));

        frames[iu] = rl.LoadTextureFromImage(frame_image);
    }

    return frames;
}
