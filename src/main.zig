const std = @import("std");
const http = @import("http.zig");
const parse = @import("parse.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, "Logs from your program will appear here!\n");

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 4221);
    var server = try address.listen(io, .{
        .reuse_address = true,
    });
    defer server.deinit(io);

    var connection = try server.accept(io);

    std.debug.print("client connected!\n", .{});

    var writer_buffer: [1024]u8 = undefined;
    var reader_buffer: [1024]u8 = undefined;
    @memset(&writer_buffer, 0);
    @memset(&reader_buffer, 0);

    var writer = connection.writer(io, &writer_buffer);
    var reader = connection.reader(io, &reader_buffer);
    const stream_out = &writer.interface;
    const stream_in = &reader.interface;

    const request = try parse.parseRequest(arena, stream_in);

    var response = try handleRequest(request, arena);
    const response_string = try response.toString(arena);
    try stream_out.print("{s}", .{response_string});
    try stream_out.flush();
}

fn handleRequest(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    std.debug.print("REQUEST: {s} {s} {s}\n", .{ @tagName(request.method), request.path, @tagName(request.version) });

    var response = try http.Response.init(allocator);
    response.version = http.Version.@"HTTP/1.1";
    response.status = http.StatusCode.HTTP_200;
    response.reason = "OK";

    if (std.ascii.eqlIgnoreCase(request.path, "/")) return response;

    const endpoint_start = 1;
    const endpoint_end = std.ascii.findIgnoreCasePos(request.path, 1, "/") orelse (request.path.len); // find next '/'
    const endpoint = request.path[endpoint_start..endpoint_end];
    var query_content: []const u8 = "";
    if (endpoint_end != request.path.len) {
        query_content = request.path[endpoint_end + 1 ..];
    }

    std.debug.print("Endpoint: {s} Start: {d} End: {d}\nContent: {s}\n", .{ endpoint, endpoint_start, endpoint_end, query_content });

    if (std.ascii.eqlIgnoreCase(endpoint, "echo")) {
        try response.addHeader(allocator, "Content-Type", "text/plain");
        const content_length = try std.fmt.allocPrint(allocator, "{d}", .{query_content.len});
        try response.addHeader(allocator, "Content-Length", content_length);
        response.body = query_content;
    }

    if (std.ascii.eqlIgnoreCase(endpoint, "user-agent")) {
        const header_content = request.headers.get("User-Agent") orelse {
            response.status = http.StatusCode.HTTP_400;
            response.reason = "Bad Request";
            response.body = "Missing User-Agent header";
            return response;
        };

        _ = try response.addHeader(allocator, "Content-Type", "text/plain");
        const content_length = try std.fmt.allocPrint(allocator, "{d}", .{header_content.len});
        _ = try response.addHeader(allocator, "Content-Length", content_length);
        response.body = header_content;
    }

    response.status = http.StatusCode.HTTP_404;
    response.reason = "Not Found";

    return response;
}
