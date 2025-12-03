const std = @import("std");
const parse = @import("parse.zig");
const http = @import("http.zig");
const handler = @import("handler.zig");

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

    const method_map = try http.initMethodMap(allocator);
    const version_map = try http.initVersionMap(allocator);

    const request = try parse.parseRequest(REQUEST, allocator, method_map, version_map);

    try stdout.print("METHOD: {s}\nPATH: {s}\nQUERY: {s}\nVERSION: {s}\n\nHEADERS:\n", .{ @tagName(request.method), request.path, request.query, @tagName(request.version) });
    for (request.headers.keys()) |name| {
        try stdout.print("{s}: {s}\n", .{ name, request.headers.get(name).?.value });
    }

    try stdout.print("\nBODY:\n{s}", .{request.body});

    const response = try handler.handle(allocator, request);

    try stdout.print("\n\n\nVERSION: {s}\nSTATUS: {s}\nREASON: {s}\n\nHEADERS:\n", .{ @tagName(response.version), @tagName(response.status), response.reason });

    try http.writeHeaders(stdout, response.headers);

    try stdout.print("\nBODY:\n{s}", .{response.body});

    try stdout.flush();
}

test {
    _ = @import("parse.zig");
    _ = @import("handler.zig");
    _ = @import("app.zig");
}
