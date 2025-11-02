const std = @import("std");
const parse = @import("parse.zig");
const http = @import("http.zig");

pub fn main() !void {
    var out_buffer: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buffer);
    const stdout = &out_writer.interface;

    const allocator = std.heap.page_allocator;

    const REQUEST = "GET / HTTP/1.1\n";

    var method_map = try http.initMethodMap(allocator);
    defer method_map.deinit();
    var version_map = try http.initVersionMap(allocator);
    defer version_map.deinit();

    const parsed = try parse.parseRequest(REQUEST, method_map, version_map);

    try stdout.print("hello this is a test:\n{s}\n{s}\n{s}\n", .{ @tagName(parsed.method), parsed.path, @tagName(parsed.version) });
    try stdout.flush();
}

test {
    _ = @import("parse.zig");
}
