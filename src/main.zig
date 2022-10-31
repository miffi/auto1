const std = @import("std");
const fs = std.fs;

const Opts = struct {
    colors: [2][3]u8,

    width: u64,
    height: u64,

    rule: u8,
};

fn state(pattern: u3, rule: u8) u1 {
    return @truncate(u1, rule >> pattern);
}

const Reel = struct {
    const Self = @This();

    const BitSet = std.bit_set.DynamicBitSet;
    const allocator = std.heap.page_allocator;

    data: BitSet,
    size: usize,

    rule: u8,

    // XXX This cannot have a zero size
    fn initEmpty(rule: u8, _size: usize) !Self {
        return Self {
            .data = try BitSet.initEmpty(allocator, _size),
            .size = _size,
            .rule = rule,
        };
    }

    fn initRandom(rule: u8, _size: usize, rand: std.rand.Random) !Self {
        var reel = try Self.initEmpty(rule, _size);
        
        const data = try allocator.alloc(u8, _size / 8 + 1);
        defer allocator.free(data);

        rand.bytes(data);

        var i: usize = 0;
        while (i != _size) : (i += 1) {
            const bit = data[i / 8] >> @truncate(u3, 7 - i % 8);
            if (bit == 1) {
                reel.data.set(i);
            }
        }

        return reel;
    }

    fn deinit(self: *Self) void {
        self.data.deinit();
    }

    fn nextState(self: *Self) void {
        var neighbors: u3 = @as(u3, @boolToInt(self.data.isSet(0))) << 1;

        var i: usize = 1;
        while (i < self.size) : (i += 1) {
            neighbors |= @bitCast(u1, self.data.isSet(i));

            if (state(neighbors, self.rule) == 1) {
                self.data.set(i - 1);
            } else {
                self.data.unset(i - 1);
            }

            neighbors <<= 1;
        }

        if (state(neighbors, self.rule) == 1) {
            self.data.set(i - 1);
        } else {
            self.data.unset(i - 1);
        }
    }

    fn size(self: *Self) usize {
        return self.size;
    }
};

fn output_ppm(out: anytype, reel: *Reel, opts: Opts) !void {
    try out.print("P3\n{d} {d}\n255\n", .{opts.width, opts.height});

    var i: usize = 0;
    while (i != opts.height) : (i += 1) {
        var j: usize = 0;
        while (j != opts.width) : (j += 1) {
            for (opts.colors[@bitCast(u1, reel.data.isSet(j))]) |color| {
                try out.print("{d} ", .{color});
            }
            try out.print("\n", .{});
        }

        reel.nextState();
    }
}

pub fn main() !void {
    const output_file = try fs.cwd().createFile("file.ppm", .{ .truncate = true });
    defer output_file.close();

    var bw = std.io.bufferedWriter(output_file.writer());

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    const opts =  .{
        .colors = [2][3]u8{[3]u8{0x75, 0x75, 0x75}, [3]u8{0x42, 0x42, 0x42}},
        .width = 4000,
        .height = 4000,
        .rule = 169,
    };

    var reel = try Reel.initRandom(opts.rule, opts.width, rand);
    defer reel.deinit();

    try output_ppm(bw.writer(), &reel, opts);

    try bw.flush();
}
