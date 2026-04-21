pub const MouseButton = enum(u8) {
    left = 0x01,
    right = 0x02,
    middle = 0x04,

    pub fn fromBits(bits: u8) ?MouseButton {
        return switch (bits) {
            0x01 => .left,
            0x02 => .right,
            0x04 => .middle,
            else => null,
        };
    }
};
