const std = @import("std");
const parse = @import("parse.zig");
const http = @import("http.zig");

pub fn main() !void {
    var out_buffer: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buffer);
    const stdout = &out_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const REQUEST =
        "GET /hello?name=test HTTP/1.1\r\n" ++
        "Host:localhost:8080\r\n" ++
        "User-Agent:curl/8.7.1\r\n" ++
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
        "Accept-Encoding: gzip, deflate\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Content-Length: 15\r\n" ++
        "\r\n" ++
        "THIS IS THE BODY\r\n";

    var method_map = try http.initMethodMap(allocator);
    defer method_map.deinit();
    var version_map = try http.initVersionMap(allocator);
    defer version_map.deinit();

    const parsed = try parse.parseRequest(REQUEST, allocator, method_map, version_map);

    try stdout.print("METHOD: {s}\nTARGET: {s}\nVERSION: {s}\n\nHEADERS:\n", .{ @tagName(parsed.method), parsed.target, @tagName(parsed.version) });
    for (parsed.headers.items) |header| {
        try stdout.print("{s}: {s}\n", .{ header.name, header.value });
    }

    try stdout.print("\nBODY:\n{s}", .{parsed.body});

    switch (parsed.method) {
        .GET => {},
        .POST => {},
        .PUT => {},
        .DELETE => {},
        .PATCH => {},
        .OPTIONS => {},
        .HEAD => {},
        .TRACE => {},
        .CONNECT => {},
        .OTHER => {},
    }

    try stdout.flush();
}

test {
    _ = @import("parse.zig");
}
