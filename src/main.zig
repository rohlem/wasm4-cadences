const wasm4 = @import("wasm4.zig");
const w4 = @import("wrapper4.zig");

const std = @import("std");

const smiley_data = [8]u8{
    0b11000011,
    0b10000001,
    0b00100100,
    0b00100100,
    0b00000000,
    0b00100100,
    0b10011001,
    0b11000011,
};

var pitch: i16 = 0;
var duty_index: u2 = 0;
var channel_index: u2 = 0;
var last_gamepad = w4.Gamepad.none_pressed;

fn gamepad_delta(now: w4.Gamepad, previous: w4.Gamepad) w4.Gamepad {
    return .{
        .single_buttons = .{
            now.single_buttons[0] and !previous.single_buttons[0],
            now.single_buttons[1] and !previous.single_buttons[1],
        },
        .direction_buttons = .{
            .left = now.direction_buttons.left and !previous.direction_buttons.left,
            .right = now.direction_buttons.right and !previous.direction_buttons.right,
            .up = now.direction_buttons.up and !previous.direction_buttons.up,
            .down = now.direction_buttons.down and !previous.direction_buttons.down,
        },
    };
}

pub fn TextScratch(comptime size_bytes: usize) type {
    return struct {
        data: [size_bytes]u8,

        pub fn init() @This() {
            return .{ .data = undefined };
        }
        pub fn bufPrint(self: *@This(), comptime format_string: []const u8, argsTuple: anytype) ![]u8 {
            return try std.fmt.bufPrint(&self.data, format_string, argsTuple);
        }
        pub fn render(self: *@This(), top_left: w4.Coordinate, color: w4.DrawColor, comptime format_string: []const u8, argsTuple: anytype) !void {
            const text = try self.bufPrint(format_string, argsTuple);
            w4.textUtf8(text, top_left, color);
        }
        pub fn retainedColorRender(self: *@This(), top_left: w4.Coordinate, comptime format_string: []const u8, argsTuple: anytype) !void {
            const text = try self.bufPrint(format_string, argsTuple);
            w4.retained_colors.textUtf8(text, top_left);
        }
    };
}

fn pr_test_update(gamepad: w4.Gamepad) void {
    const new_presses: w4.Gamepad = gamepad_delta(gamepad, last_gamepad);
    const vdelta = @as(i2, @boolToInt(new_presses.direction_buttons.up)) -
        @as(i2, @boolToInt(new_presses.direction_buttons.down));
    pitch += vdelta;
    const hdelta = @as(i2, @boolToInt(new_presses.direction_buttons.right)) -
        @as(i2, @boolToInt(new_presses.direction_buttons.left and !last_gamepad.direction_buttons.left));
    duty_index +%= @bitCast(u2, hdelta);
    channel_index +%= @boolToInt(new_presses.single_buttons[1]);

    var text_scratch = TextScratch(1 << 8).init();
    text_scratch.render(.{ .x = 10, .y = 40 }, 3, "pitch (^/v): {d}", .{pitch}) catch unreachable;
    text_scratch.render(.{ .x = 10, .y = 50 }, 3, "mode (</>): {d}", .{duty_index}) catch unreachable;
    text_scratch.render(.{ .x = 10, .y = 60 }, 3, "channel (Z/Y): {d}", .{channel_index}) catch unreachable;
    if (gamepad.single_buttons[0]) {
        w4.draw_colors.set(0, 2);
        const base_freq = @floatToInt(u16, 256.0 * (std.math.pow(f32, 2.0, @intToFloat(f32, pitch) / 12)));
        const instrument = switch (channel_index) {
            0, 1 => instrument: {
                const duty = @intToEnum(w4.Instrument.PulseDuty, duty_index);
                break :instrument switch (channel_index) {
                    else => unreachable,
                    0 => break :instrument w4.Instrument{ .pulse_0 = duty },
                    1 => break :instrument w4.Instrument{ .pulse_1 = duty },
                };
            },
            2 => w4.Instrument{ .triangle = {} },
            3 => w4.Instrument{ .noise = {} },
        };
        w4.tone(.{ .start = base_freq, .end = base_freq }, w4.Adsr.init(0, 0, 2, 0), @as(u32, 40), instrument) catch unreachable;
    }
}

const Harmony = enum {
    diminished,
    minor_b5,
    minor_6,
    minor,
    major7,
    major,
    augmented,
    augmented7,

    pub fn next(self: Harmony) Harmony {
        switch (self) {
            .diminished => return .minor_b5,
            .minor_b5 => return .minor_6,
            .minor_6 => return .minor,
            .minor => return .major7,
            .major7 => return .major,
            .major => return .augmented,
            .augmented => return .augmented7,
            .augmented7 => return .diminished,
        }
    }
    pub fn previous(self: Harmony) Harmony {
        switch (self) {
            .diminished => return .augmented7,
            .minor_b5 => return .diminished,
            .minor_6 => return .minor_b5,
            .minor => return .minor_6,
            .major7 => return .minor,
            .major => return .major7,
            .augmented => return .major,
            .augmented7 => return .augmented,
        }
    }
    pub fn shortName(self: Harmony) []const u8 {
        switch (self) {
            .diminished => return "dim",
            .minor_b5 => return "m_b5",
            .minor_6 => return "m_6",
            .minor => return "m",
            .major7 => return "maj7",
            .major => return "maj",
            .augmented => return "aug",
            .augmented7 => return "aug7",
        }
    }
};
var harmony = Harmony.minor;
const Positioning = enum {
    spread,
    narrow,

    pub fn next(self: Positioning) Positioning {
        switch (self) {
            .spread => return .narrow,
            .narrow => return .spread,
        }
    }
};
var positioning: Positioning = .spread;
var moved_b: bool = false;
var frame_counter: usize = 0;

var from_minor_harmony: bool = false;
fn cadences_update(gamepad: w4.Gamepad) void {
    const new_presses: w4.Gamepad = gamepad_delta(gamepad, last_gamepad);
    const vdelta = @as(i2, @boolToInt(new_presses.direction_buttons.up)) -
        @as(i2, @boolToInt(new_presses.direction_buttons.down));
    const hdelta = @as(i2, @boolToInt(new_presses.direction_buttons.right)) -
        @as(i2, @boolToInt(new_presses.direction_buttons.left and !last_gamepad.direction_buttons.left));

    const prev_harmony = harmony.previous();
    const next_harmony = harmony.next();
    switch (hdelta) {
        else => unreachable,
        0 => {},
        1 => {
            from_minor_harmony = true;
            harmony = harmony.next();
        },
        -1 => {
            from_minor_harmony = false;
            harmony = harmony.previous();
        },
    }

    const cadence_mode = gamepad.single_buttons[1];
    if (!gamepad.single_buttons[1]) {
        pitch += vdelta;
        if (last_gamepad.single_buttons[1] and !moved_b) {
            positioning = positioning.next();
            moved_b = true;
        }
    } else {
        if (vdelta != 0) {
            positioning = positioning.next();
        }
        moved_b = moved_b or (vdelta != 0);
        if (new_presses.single_buttons[1]) {
            moved_b = false;
        }
        switch (vdelta) {
            else => unreachable,
            0 => {},
            -1 => pitch -= @as(i16, if (positioning == .spread) 7 else 5),
            1 => pitch += @as(i16, if (positioning == .spread) 7 else 5),
        }
    }

    w4.draw_colors.set(0, 3);
    var text_scratch = TextScratch(1 << 8).init();
    // note: inline-if in tuples (f.e. `.{if(a) "asdf" else "jkl;"}`) are currently broken, see https://github.com/ziglang/zig/issues/4491
    text_scratch.retainedColorRender(.{ .x = 10, .y = 40 }, "pitch (^/v): {d}", .{pitch}) catch unreachable;
    const cadence_mode_text = if (cadence_mode) @as([]const u8, "on") else @as([]const u8, "off");
    text_scratch.retainedColorRender(.{ .x = 10, .y = 30 }, "cadence jump: {s}", .{cadence_mode_text}) catch unreachable;
    const pos_text = switch (positioning) {
        .narrow => @as([]const u8, "narrow"),
        .spread => @as([]const u8, "spread"),
    };
    text_scratch.retainedColorRender(.{ .x = 10, .y = 50 }, "pos: {s}", .{pos_text}) catch unreachable;
    text_scratch.retainedColorRender(.{ .x = 10, .y = 65 }, "    harmony    ", .{}) catch unreachable;
    text_scratch.retainedColorRender(.{ .x = 5, .y = 75 }, "{s:4} < {s:4} > {s:4}", .{ prev_harmony.shortName(), harmony.shortName(), next_harmony.shortName() }) catch unreachable;

    const suggestion_text: ?[]const u8 = suggestion_text: {
        switch (harmony) {
            else => break :suggestion_text null, // no suggestion
            .minor, .major7, .major => break :suggestion_text @as([]const u8, switch (positioning) { // suggest the closest cadence
                .spread => switch (harmony) {
                    else => unreachable,
                    .minor => "cadence jump ^>", //suggest cadence
                    .major7 => {
                        if ((@mod(pitch, 6)) < 2) { //suggest resolution
                            break :suggestion_text @as([]const u8, if (from_minor_harmony) "normal step ^>" else "normal step ^<");
                        } else { //suggest cadence
                            break :suggestion_text @as([]const u8, if (from_minor_harmony) "cadence jump ^<" else "cadence jump ^>");
                        }
                    },
                    .major => "cadence jump ^<", //suggest cadence
                },
                .narrow => switch (harmony) {
                    else => unreachable,
                    .minor => "cadence jump v>", //suggest cadence
                    .major7 => {
                        if ((@mod(pitch, 6)) < 2) { //suggest resolution
                            break :suggestion_text @as([]const u8, if (from_minor_harmony) "normal step v>" else "normal step v<");
                        } else { //suggest cadence
                            break :suggestion_text @as([]const u8, if (from_minor_harmony) "cadence jump v<" else "cadence jump v>");
                        }
                    },
                    .major => "cadence jump v<",
                },
            }),
        }
    };
    if (suggestion_text) |suggested| {
        w4.draw_colors.set(0, 1);
        text_scratch.retainedColorRender(.{ .x = 10, .y = 90 }, "suggestion:", .{}) catch unreachable;
        text_scratch.retainedColorRender(.{ .x = 10, .y = 100 }, "{s}", .{suggested}) catch unreachable;
    }

    if (gamepad.single_buttons[0]) {
        const freqFromPitch = struct {
            fn freqFromPitch(input_pitch: i16) u16 {
                return @floatToInt(u16, 230.0 * (std.math.pow(f32, 2.0, @intToFloat(f32, input_pitch) / 12)));
            }
        }.freqFromPitch;
        const pitch_spread = 12 * @as(u4, @boolToInt(positioning == .spread));
        const base_freq = freqFromPitch(pitch);
        const support_pitch_1 = switch (harmony) {
            .diminished, .minor_b5, .minor_6, .minor => pitch + 3,
            .major, .major7, .augmented, .augmented7 => pitch + 4,
        };
        const support_freq_1 = freqFromPitch(support_pitch_1 + pitch_spread);
        _ = support_freq_1;
        const support_pitch_2 = switch (harmony) {
            .diminished, .minor_b5 => pitch + 6,
            .minor_6 => pitch + 8,
            .minor, .major7, .major => pitch + 7,
            .augmented, .augmented7 => pitch + 8,
        };
        const support_freq_2 = freqFromPitch(support_pitch_2 + pitch_spread);
        _ = support_freq_2;
        const support_pitch_3 = switch (harmony) {
            .diminished => pitch + 9,
            .minor_b5, .minor, .minor_6, .major7, .augmented7 => pitch + 10,
            .major, .augmented => pitch + 11,
        };
        const support_freq_3 = freqFromPitch(support_pitch_3 + pitch_spread);
        const support_pitch_4 = switch (harmony) {
            .diminished => pitch + 14,
            .minor_b5, .minor, .minor_6, .major7, .major, .augmented, .augmented7 => pitch + 14,
        };
        const support_freq_4 = freqFromPitch(support_pitch_4);
        const volume = 40;
        const support_freq_a = if (frame_counter % 4 < 2) support_freq_3 else support_freq_1;
        const support_freq_b = if ((frame_counter +% 1) % 4 < 2) support_freq_4 else support_freq_2;
        const support_volume = 22;
        w4.tone(.{ .start = base_freq, .end = base_freq }, w4.Adsr.init(0, 0, 2, 0), volume, .{ .triangle = {} }) catch unreachable;
        w4.tone(.{ .start = support_freq_a, .end = support_freq_a }, w4.Adsr.init(0, 0, 2, 0), support_volume, .{ .pulse_0 = .quarter }) catch unreachable;
        w4.tone(.{ .start = support_freq_b, .end = support_freq_b }, w4.Adsr.init(0, 0, 2, 0), support_volume, .{ .pulse_1 = .half }) catch unreachable;
    }
}

export fn update() void {
    defer frame_counter += 1;
    //w4.draw_colors.set(0, 1);
    w4.text("Hello from Zig!", .{ .x = 10, .y = 10 }, 1);

    const gamepad = w4.gamepads[0].get();
    defer last_gamepad = gamepad;
    //pr_test_update(gamepad);
    cadences_update(gamepad);

    w4.draw_colors.set(0, 2 + @as(u2, @boolToInt(gamepad.single_buttons[0])));
    w4.retained_colors.blitFixed(.one, .{ .width = 8, .height = 8 }, smiley_data, .{ .x = 76, .y = 116 }, w4.BlitEffectFlags.none);
    w4.retained_colors.text("Press X to bleep!", .{ .x = 10, .y = 130 });
}
