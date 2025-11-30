const std = @import("std");
const parse = @import("parse.zig");
const http = @import("http.zig");
const app = @import("app.zig");

pub fn main() !void {
    var out_buffer: [1024]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buffer);
    const stdout = &out_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const REQUEST =
        "GET /src/index.html?name=test HTTP/1.1\r\n" ++
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

    const request = try parse.parseRequest(REQUEST, allocator, method_map, version_map);

    try stdout.print("METHOD: {s}\nPATH: {s}\nQUERY: {s}\nVERSION: {s}\n\nHEADERS:\n", .{ @tagName(request.method), request.path, request.query, @tagName(request.version) });
    for (request.headers.keys()) |name| {
        try stdout.print("{s}: {s}\n", .{ name, request.headers.get(name).?.value });
    }

    try stdout.print("\nBODY:\n{s}", .{request.body});

    const response = switch (request.method) {
        .GET => try app.handleGet(request, allocator),
        .POST => try app.handlePost(request, allocator),
        .PUT => try app.handlePut(request, allocator),
        .DELETE => try app.handleDelete(request, allocator),
        .PATCH => try app.handlePatch(request, allocator),
        .OPTIONS => try app.handleOptions(request, allocator),
        .HEAD => try app.handleHead(request, allocator),
        .TRACE => try app.handleTrace(request, allocator),
        .CONNECT => try app.handleConnect(request, allocator),
        .OTHER => try app.handleOther(request, allocator),
    };

    try stdout.print("\n\n\nVERSION: {s}\nSTATUS: {s}\nREASON: {s}\n\nHEADERS:\n", .{ @tagName(response.version), @tagName(response.status), response.reason });
    for (response.headers.keys()) |name| {
        try stdout.print("{s}: {s}\n", .{ name, response.headers.get(name).?.value });
    }

    try stdout.print("\nBODY:\n{s}", .{response.body});

    try stdout.flush();
}

test {
    _ = @import("parse.zig");
    _ = @import("methods.zig");
    _ = @import("app.zig");
}
