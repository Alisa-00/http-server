const std = @import("std");
const parse = @import("parse");

pub fn main() !void {
    var out_buffer: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buffer);
    const stdout = &out_writer.interface;

    try stdout.print("hello this is a test\n", .{});
    try stdout.flush();
}
