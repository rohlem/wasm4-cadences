//! A nicer interface over the wasm4 API.
const wasm4 = @import("wasm4.zig");

const wasm4_omissions = struct { // documented but not provided in wasm4.zig
    /// Draws text using the built-in system font, given external string length.
    pub extern fn textUtf8(strUtf8: [*]const u8, byteLength: u32, x: i32, y: i32) void;
    comptime {
        std.debug.assert(!@hasDecl(wasm4, "textUtf8"));
    }
    /// Draws text using the built-in system font, given external string length.
    pub extern fn textUtf16(strUtf8: [*]const u16, byteLength: u32, x: i32, y: i32) void;
    comptime {
        std.debug.assert(!@hasDecl(wasm4, "textUtf16"));
    }
};

const std = @import("std");

pub const canvas_size: comptime_int = wasm4.CANVAS_SIZE; // explicit type of u32 carries no meaning/information

pub const Component = std.meta.Int(.unsigned, std.math.log2_int_ceil(usize, canvas_size));
pub const Coordinate = struct {
    x: Component,
    y: Component,
};
pub const ScreenLength = Component;
pub const ScreenSize = struct {
    width: ScreenLength,
    height: ScreenLength,
};

const PaletteColor = struct {
    const Native = u32;

    red: u8,
    green: u8,
    blue: u8,

    pub fn fromNative(native: Native) PaletteColor {
        const getByte = struct {
            fn getByte(composite: Native, comptime shift_i: u2) u8 {
                const shifted = (composite >> (shift_i * 8));
                return @intCast(u8, shifted & @as(u8, 0xFF));
            }
        }.getByte;

        const highest_byte = getByte(native, 3);
        if (highest_byte != 0) {
            std.log.warn("converting native PaletteColor with highest byte set to {x}", .{highest_byte});
        }
        return .{
            .red = getByte(native, 2),
            .green = getByte(native, 1),
            .blue = getByte(native, 0),
        };
    }
    pub fn toNative(self: PaletteColor) Native {
        return (@as(Native, self.red) << 2 * 8) |
            (@as(Native, self.green) << 1 * 8) |
            (self.blue << 0 * 8);
    }
};
comptime {
    std.debug.assert(@TypeOf(wasm4.PALETTE) == *[4]PaletteColor.Native);
}
pub const palette = @ptrCast(*[4]PaletteColor, wasm4.PALETTE);

pub const DrawColor = ?draw_color.PaletteIndex;
const draw_color = struct {
    const PaletteIndex = u2;
    pub const Native = enum(u4) {
        transparent = 0,
        @"0" = 1,
        @"1" = 2,
        @"2" = 3,
        @"3" = 4,
    };

    pub fn fromNative(native: Native) DrawColor {
        switch (native) {
            .transparent => return null,
            else => return @enumToInt(native) - 1,
        }
    }
    pub fn toNative(self: DrawColor) Native {
        if (self) |index| {
            return @intToEnum(Native, @as(@typeInfo(Native).Enum.tag_type, index) + 1);
        }
        return .transparent;
    }
};
pub const draw_colors = struct {
    const Native = u16;
    const Length = 4;
    comptime {
        const expected_draw_colors_ptr_type = *Native;
        std.debug.assert(@TypeOf(wasm4.DRAW_COLORS) == expected_draw_colors_ptr_type);
        std.debug.assert(@divExact(std.meta.bitCount(Native), std.meta.bitCount(@typeInfo(draw_color.Native).Enum.tag_type)) == Length);
    }

    const Index = std.meta.Int(.unsigned, std.math.log2_int(usize, Length));
    fn checkIndex(index: Index) void {
        std.debug.assert(index <= Length);
    }

    pub fn get(index: Index) !DrawColor {
        checkIndex(index);
        const shifted = wasm4.DRAW_COLORS.* >> (index * 8);
        return draw_color.fromNative(try std.meta.IntToEnum(draw_color.Native, @intCast(u4, shifted & 0xF)));
    }
    //could add
    //`pub fn getMultiple(comptime count: std.meta.Int(.unsigned, std.math.log2_int(Length+1)), indices: [count]Index) ![count]DrawColor;`
    //for guaranteeing only one memory access
    pub fn getAll() ![Length]DrawColor {
        var result: [Length]DrawColor = undefined;
        for (result) |*element, index| {
            element.* = try get(index);
        }
        return result;
    }
    pub fn set(index: Index, value: DrawColor) void {
        checkIndex(index);
        const ShiftType = std.math.Log2Int(Native);
        const shift = @as(ShiftType, index) * 4;
        const retention_mask = (~@as(Native, 0)) & (~(@as(Native, 0xF) << shift));
        wasm4.DRAW_COLORS.* = ((wasm4.DRAW_COLORS.*) & retention_mask) | (@as(Native, @enumToInt(draw_color.toNative(value))) << shift);
    }
    //could add
    //`pub fn setMultiple(comptime count: std.meta.Int(.unsigned, std.math.log2_int(Length+1)), indices: [count]Index, values: [count]DrawColor) void;`
    //for guaranteeing only one memory access
    pub fn setAll(values: [Length]DrawColor) void {
        var new_composite_value: Native = 0;
        for (values) |element, index| {
            new_composite_value |= element << (index * 8);
        }
        wasm4.DRAW_COLORS = draw_color.toNative(new_composite_value);
    }
};

pub const Gamepad = struct {
    const Native = u8;
    comptime {
        const expected_gamepad_ptr_type = *const Native;
        std.debug.assert(@TypeOf(wasm4.GAMEPAD1) == expected_gamepad_ptr_type);
        std.debug.assert(@TypeOf(wasm4.GAMEPAD2) == expected_gamepad_ptr_type);
        std.debug.assert(@TypeOf(wasm4.GAMEPAD3) == expected_gamepad_ptr_type);
        std.debug.assert(@TypeOf(wasm4.GAMEPAD4) == expected_gamepad_ptr_type);
    }

    pub const DirectionButtons = struct {
        left: bool,
        right: bool,
        up: bool,
        down: bool,
    };

    pub const none_pressed = Gamepad{
        .single_buttons = .{
            false,
            false,
        },
        .direction_buttons = .{
            .left = false,
            .right = false,
            .up = false,
            .down = false,
        },
    };

    single_buttons: [2]bool,
    direction_buttons: DirectionButtons,

    pub fn fromNative(native: Native) Gamepad {
        const Index = std.math.Log2Int(Native);
        const getBit = struct {
            fn getBit(composite: Native, index: Index) bool {
                return (composite & (@as(Native, 1) << index)) != 0;
            }
        }.getBit;
        for ([_]Index{ 2, 3 }) |index| {
            const bit_state = getBit(native, index);
            if (bit_state != false) {
                std.log.warn("converting native Gamepad with bit {} set to {}", .{ index, bit_state });
            }
        }
        return .{
            .single_buttons = .{
                getBit(native, 0),
                getBit(native, 1),
            },
            .direction_buttons = .{
                .left = getBit(native, 4),
                .right = getBit(native, 5),
                .up = getBit(native, 6),
                .down = getBit(native, 7),
            },
        };
    }
    pub fn toNative(self: Gamepad) Native {
        return (@as(Native, @boolToInt(self.single_buttons[0])) << 0) |
            (@as(Native, @boolToInt(self.single_buttons[1])) << 1) |
            (@as(Native, @boolToInt(self.direction_buttons.left)) << 4) |
            (@as(Native, @boolToInt(self.direction_buttons.right)) << 5) |
            (@as(Native, @boolToInt(self.direction_buttons.up)) << 6) |
            (@as(Native, @boolToInt(self.direction_buttons.down)) << 7);
    }
};

pub fn GamepadSingleton(comptime native_address: *const Gamepad.Native) type {
    return struct {
        pub fn get() Gamepad {
            return Gamepad.fromNative(native_address.*);
        }
    };
}
pub const gamepads = [_]type{
    GamepadSingleton(wasm4.GAMEPAD1),
    GamepadSingleton(wasm4.GAMEPAD2),
    GamepadSingleton(wasm4.GAMEPAD3),
    GamepadSingleton(wasm4.GAMEPAD4),
};

pub const BlitEffectFlags = struct {
    const Native = u32;
    pub const none = BlitEffectFlags{
        .flip_x = false,
        .flip_y = false,
        .rotate_anti_clockwise_quarter = false,
    };

    flip_x: bool,
    flip_y: bool,
    rotate_anti_clockwise_quarter: bool,

    pub fn toNative(self: BlitEffectFlags) Native {
        const flip_x = if (self.flip_x) wasm4.BLIT_FLIP_X else 0;
        const flip_y = if (self.flip_y) wasm4.BLIT_FLIP_Y else 0;
        const rotate_anti_clockwise_quarter = if (self.rotate_anti_clockwise_quarter) wasm4.BLIT_ROTATE else 0;
        return flip_x |
            flip_y |
            rotate_anti_clockwise_quarter;
    }
};
pub const BlitFlags = struct {
    const Native = u32;
    pub const BitsPerPixel = enum {
        one,
        two,
        pub fn numeric(self: BitsPerPixel) u2 {
            switch (self) {
                .one => return 1,
                .two => return 2,
            }
        }
    };

    bits_per_pixel: BitsPerPixel,
    effects: BlitEffectFlags,

    pub fn empty1BitPerPixel() BlitFlags {
        return .{
            .bits_per_pixel = .one,
            .effects = BlitEffectFlags.none,
        };
    }
    pub fn empty2BitsPerPixel() BlitFlags {
        return .{
            .bits_per_pixel = .two,
            .effects = BlitEffectFlags.none,
        };
    }

    pub fn fromNative(native: Native) BlitFlags {
        const Index = std.math.Log2Int(Native);
        const getBit = struct {
            fn getBit(composite: Native, index: Index) bool {
                return (composite & (@as(Native, 1) << index)) != 0;
            }
        }.getBit;
        {
            const first_unused_bit_index = 4;
            comptime {
                const first_unused_bit_mask = @as(Native, 1) << first_unused_bit_index;
                std.debug.assert(first_unused_bit_mask > wasm4.BLIT_1BPP);
                std.debug.assert(first_unused_bit_mask > wasm4.BLIT_2BPP);
                std.debug.assert(first_unused_bit_mask > wasm4.BLIT_FLIP_X);
                std.debug.assert(first_unused_bit_mask > wasm4.BLIT_FLIP_Y);
                std.debug.assert(first_unused_bit_mask > wasm4.BLIT_ROTATE);
            }
            {
                var unused_bit_index = first_unused_bit_index;
                while (true) : (unused_bit_index += 1) {
                    if (getBit(native, unused_bit_index)) {
                        std.log.warn("converting native BlitFlags with unused bit #{d} set", .{unused_bit_index});
                    }
                }
            }
        }
        comptime {
            std.debug.assert(wasm4.BLIT_1BPP == 0);
        }
        const bits_per_pixel = if (getBit(native, std.math.log2_int(wasm4.BLIT_2BPP))) .two else .one;
        return .{
            .bits_per_pixel = bits_per_pixel,
            .effects = .{
                .flip_x = getBit(native, std.math.log2_int(wasm4.BLIT_FLIP_X)),
                .flip_y = getBit(native, std.math.log2_int(wasm4.BLIT_FLIP_Y)),
                .rotate_anti_clockwise_quarter = getBit(native, std.math.log2_int(wasm4.BLIT_ROTATE)),
            },
        };
    }
    pub fn toNative(self: BlitFlags) Native {
        const bits_per_pixel = switch (self.bits_per_pixel) {
            .one => wasm4.BLIT_1BPP,
            .two => wasm4.BLIT_2BPP,
        };
        const effects = self.effects.toNative();
        return bits_per_pixel | effects;
    }
};

pub fn Sprite(comptime dimensions: ScreenSize, comptime bits_per_pixel: BlitFlags.BitsPerPixel) type {
    return struct {
        pub const dimensions = dimensions;
        pub const width = dimensions.width;
        pub const height = dimensions.height;
        pub const bits_per_pixel = bits_per_pixel;
        pub const PixelBits = std.meta.Int(.unsigned, bits_per_pixel.numeric());
        pub const Data = std.PackedIntArray(PixelBits, width * height);

        data: Data,

        pub fn init(arg: [((width * height) + 7) / 8]u8) @This() {
            var self: @This() = undefined;
            self.data.bytes = arg; // weird "cannot assign to constant" error
            return self;
        }

        pub fn blit(self: *const @This(), top_left: Coordinate, effect_flags: BlitEffectFlags, colors: [2]DrawColor) void {
            draw_colors.set(0, colors[0]);
            draw_colors.set(1, colors[1]);
            self.retainedColorsBlit(top_left, effect_flags);
        }
        pub fn blitSub(self: *const @This(), top_left: Coordinate, sub_dimensions: ScreenSize, source_top_left: Coordinate, horizontal_stride: ?ScreenLength, effect_flags: BlitEffectFlags, colors: [4]DrawColor) void {
            draw_colors.set(0, colors[0]);
            draw_colors.set(1, colors[1]);
            draw_colors.set(2, colors[2]);
            draw_colors.set(3, colors[3]);
            self.retainedColorsBlitSub(top_left, sub_dimensions, source_top_left, horizontal_stride, effect_flags);
        }
        pub fn retainedColorsBlit(self: *const @This(), top_left: Coordinate, effect_flags: BlitEffectFlags) void {
            retained_colors.blitFixed(
                bits_per_pixel,
                dimensions,
                &self.data.bytes,
                top_left,
                effect_flags,
            );
        }
        pub fn retainedColorsBlitSub(self: *const @This(), top_left: Coordinate, sub_dimensions: ScreenSize, source_top_left: Coordinate, horizontal_stride: ?ScreenLength, effect_flags: BlitEffectFlags) void {
            retained_colors.blitSub(
                bits_per_pixel,
                dimensions,
                &self.data.bytes,
                top_left,
                sub_dimensions,
                source_top_left,
                horizontal_stride orelse width,
                effect_flags,
            );
        }
    };
}

pub const Frequency = u16;
pub const FrequencySlide = struct {
    pub const Native = u32;

    start: Frequency,
    end: Frequency,

    pub fn toNative(self: FrequencySlide) Native {
        return (@as(Native, self.start) << 0) |
            (@as(Native, self.end) << 16);
    }
};
pub fn checkVolume(volume: u7) !void {
    if (volume > 100) {
        return error.OutOfRange;
    }
}
pub const Adsr = struct {
    const Native = u32;

    pub const stop = Adsr.init(0, 0, 0, 0);

    attack_frames: u8,
    decay_frames: u8,
    sustain_frames: u8,
    release_frames: u8,

    pub fn init(attack_frames: u8, decay_frames: u8, sustain_frames: u8, release_frames: u8) Adsr {
        return .{
            .attack_frames = attack_frames,
            .decay_frames = decay_frames,
            .sustain_frames = sustain_frames,
            .release_frames = release_frames,
        };
    }
    pub fn toNative(self: Adsr) Native {
        return (@as(Native, self.attack_frames) << (3 * 8)) |
            (@as(Native, self.decay_frames) << (2 * 8)) |
            (@as(Native, self.release_frames) << (1 * 8)) |
            (@as(Native, self.sustain_frames) << (0 * 8));
    }
};
pub const Instrument = union(enum) {
    const Native = u4;
    pub const PulseDuty = enum {
        eighth,
        quarter,
        half,
        three_quarters,

        pub fn toNative(self: PulseDuty) u4 {
            switch (self) {
                .eighth => return wasm4.TONE_MODE1,
                .quarter => return wasm4.TONE_MODE2,
                .half => return wasm4.TONE_MODE3,
                .three_quarters => return wasm4.TONE_MODE4,
            }
        }
    };

    pulse_0: PulseDuty,
    pulse_1: PulseDuty,
    triangle,
    noise,

    pub fn toNative(self: Instrument) Native {
        switch (self) {
            .pulse_0, .pulse_1 => |duty| {
                const instrument_index: u4 = switch (self) {
                    else => unreachable,
                    .pulse_0 => wasm4.TONE_PULSE1,
                    .pulse_1 => wasm4.TONE_PULSE2,
                };
                return instrument_index | duty.toNative();
            },
            .triangle => return wasm4.TONE_TRIANGLE,
            .noise => return wasm4.TONE_NOISE,
        }
    }
};

pub fn tone(frequency_slide: FrequencySlide, adsr: Adsr, volume: u7, instrument: Instrument) !void {
    try checkVolume(volume);
    wasm4.tone(frequency_slide.toNative(), adsr.toNative(), volume, instrument.toNative());
}

pub fn text(str: [*:0]const u8, top_left: Coordinate, color: DrawColor) void {
    draw_colors.set(0, color);
    retained_colors.text(str, top_left);
}
pub fn textUtf8(str: []const u8, top_left: Coordinate, color: DrawColor) void {
    draw_colors.set(0, color);
    retained_colors.textUtf8(str, top_left);
}
pub fn textUtf16(str: []const u16, top_left: Coordinate, color: DrawColor) void {
    draw_colors.set(0, color);
    retained_colors.textUtf16(str, top_left);
}

pub fn blitFixed(
    comptime bits_per_pixel: BlitFlags.BitsPerPixel,
    comptime dimensions: ScreenSize,
    sprite_data: [((dimensions.width * dimensions.height * bits_per_pixel.numeric()) + 7) / 8]u8,
    top_left: Coordinate,
    effect_flags: BlitEffectFlags,
    colors: [2]DrawColor,
) void {
    draw_colors.set(0, colors[0]);
    draw_colors.set(1, colors[1]);
    retained_colors.blitFixed(bits_per_pixel, dimensions, &sprite_data, top_left, effect_flags);
}
pub fn blit(
    comptime bits_per_pixel: BlitFlags.BitsPerPixel,
    dimensions: ScreenSize,
    sprite_data: []const u8,
    top_left: Coordinate,
    effect_flags: BlitEffectFlags,
    colors: [2]DrawColor,
) void {
    draw_colors.set(0, colors[0]);
    draw_colors.set(1, colors[1]);
    retained_colors.blit(
        bits_per_pixel,
        dimensions,
        sprite_data,
        top_left,
        effect_flags,
    );
}
pub fn blitSub(
    comptime bits_per_pixel: BlitFlags.BitsPerPixel,
    sprite_data: []const u8,
    sub_dimensions: ScreenSize,
    source_top_left: Coordinate,
    horizontal_stride: ScreenLength,
    effect_flags: BlitEffectFlags,
    colors: [4]DrawColor,
) void {
    draw_colors.set(0, colors[0]);
    draw_colors.set(1, colors[1]);
    draw_colors.set(2, colors[2]);
    draw_colors.set(3, colors[3]);
    retained_colors.blitSub(
        bits_per_pixel,
        sprite_data,
        sub_dimensions,
        source_top_left,
        horizontal_stride,
        effect_flags,
    );
}

pub const retained_colors = struct {
    pub fn text(str: [*:0]const u8, top_left: Coordinate) void {
        wasm4.text(str, top_left.x, top_left.y);
    }
    pub fn textUtf8(str: []const u8, top_left: Coordinate) void {
        wasm4_omissions.textUtf8(str.ptr, str.len, top_left.x, top_left.y);
    }
    pub fn textUtf16(str: []const u16, top_left: Coordinate) void {
        wasm4_omissions.textUtf16(str.ptr, str.len, top_left.x, top_left.y);
    }
    pub fn blitFixed(
        comptime bits_per_pixel: BlitFlags.BitsPerPixel,
        comptime dimensions: ScreenSize,
        sprite_data: [((dimensions.width * dimensions.height * bits_per_pixel.numeric()) + 7) / 8]u8,
        top_left: Coordinate,
        effect_flags: BlitEffectFlags,
    ) void {
        retained_colors.blit(bits_per_pixel, dimensions, &sprite_data, top_left, effect_flags);
    }
    pub fn blit(
        comptime bits_per_pixel: BlitFlags.BitsPerPixel,
        dimensions: ScreenSize,
        sprite_data: []const u8,
        top_left: Coordinate,
        effect_flags: BlitEffectFlags,
    ) void {
        const required_data_length_pixels = dimensions.width * dimensions.height;
        const required_data_length_bytes = ((required_data_length_pixels * bits_per_pixel.numeric()) + 7) / 8;
        var blit_flags = comptime switch (bits_per_pixel) {
            .one => BlitFlags.empty1BitPerPixel(),
            .two => BlitFlags.empty2BitsPerPixel(),
        };
        blit_flags.effects = effect_flags;
        wasm4.blit(
            sprite_data[0..required_data_length_bytes].ptr,
            top_left.x,
            top_left.y,
            dimensions.width,
            dimensions.height,
            blit_flags.toNative(),
        );
    }
    pub fn blitSub(
        comptime bits_per_pixel: BlitFlags.BitsPerPixel,
        sprite_data: []const u8,
        top_left: Coordinate,
        sub_dimensions: ScreenSize,
        source_top_left: Coordinate,
        horizontal_stride: ScreenLength,
        effect_flags: BlitEffectFlags,
    ) void {
        const required_data_length_pixels = (source_top_left.y + sub_dimensions.height) * horizontal_stride + (source_top_left.x + sub_dimensions.width);
        const required_data_length_bytes = ((required_data_length_pixels * bits_per_pixel.numeric()) + 7) / 8;
        var blit_flags = comptime switch (bits_per_pixel) {
            .one => BlitFlags.empty1BitPerPixel(),
            .two => BlitFlags.empty2BitsPerPixel(),
        };
        blit_flags.effects = effect_flags;
        wasm4.blitSub(
            sprite_data[0..required_data_length_bytes].ptr,
            top_left.x,
            top_left.y,
            sub_dimensions.width,
            sub_dimensions.height,
            source_top_left.x,
            source_top_left.y,
            horizontal_stride,
            blit_flags.toNative(),
        );
    }
};
