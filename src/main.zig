const std = @import("std");
const http = @import("http.zig");
const parse = @import("parse.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var value: bool = false;
    var directory: []u8 = undefined;
    for (args) |arg| {
        std.debug.print("ARGUMENT: {s}\n", .{arg});
        if (value) {
            directory = @constCast(arg);
            value = false;
        }
        if (std.ascii.eqlIgnoreCase(arg, "--directory")) value = true;
    }

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, "Logs from your program will appear here!\n");

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 4221);
    var server = try address.listen(io, .{
        .reuse_address = true,
    });
    defer server.deinit(io);
    const allocator = std.heap.page_allocator;

    var connection_id: u32 = 0;
    var group: std.Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const connection = server.accept(io) catch |err| {
            std.debug.print("Unable to handle incoming connection!\n{}\n", .{err});
            continue;
        };

        connection_id += 1;
        group.concurrent(io, serveConnection, .{ io, allocator, connection, connection_id, directory }) catch |err| {
            std.debug.print("Could not spawn handler:\n{}\n", .{err});
            continue;
        };
    }
}

fn serveConnection(io: std.Io, allocator: std.mem.Allocator, connection: std.Io.net.Stream, id: u32, directory: []u8) void {
    handleConnection(io, allocator, connection, id, directory) catch |err| switch (err) {
        error.Canceled => {},
        else => std.debug.print("Error during connection {d}:\n{}\n", .{ id, err }),
    };
}

fn handleConnection(io: std.Io, allocator: std.mem.Allocator, connection: std.Io.net.Stream, conn_id: u32, directory: []u8) !void {
    defer connection.close(io);
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    std.debug.print("{d} - Client connected!\n", .{conn_id});

    var writer_buffer: [1024]u8 = undefined;
    var reader_buffer: [1024]u8 = undefined;

    var writer = connection.writer(io, &writer_buffer);
    var reader = connection.reader(io, &reader_buffer);
    const stream_out = &writer.interface;
    const stream_in = &reader.interface;

    std.debug.print("{d} - Reading request!\n", .{conn_id});

    const request = try parse.parseRequest(arena, stream_in);

    std.debug.print("{d} - REQUEST PARSED:\n{s} {s} {s}\n", .{ conn_id, @tagName(request.method), request.path, @tagName(request.version) });
    for (request.headers.keys()) |header| {
        const value = request.headers.get(header).?;
        std.debug.print("{s}: {s}\n", .{ header, value });
    }
    std.debug.print("{s}\n", .{request.body});

    var response = try handleRequest(io, arena, request, directory);
    const response_string = try response.toString(arena);

    std.debug.print("{d} - OUTGOING RESPONSE:\n{s}\n", .{ conn_id, response_string });

    try stream_out.print("{s}", .{response_string});
    try stream_out.flush();
}

fn handleRequest(io: std.Io, allocator: std.mem.Allocator, request: http.Request, file_directory: []u8) !http.Response {
    var response = try http.Response.init(allocator);
    response.version = http.Version.@"HTTP/1.1";
    response.status = http.StatusCode.HTTP_200;
    response.reason = "OK";

    if (request.headers.contains("accept-encoding")) {
        const encodings = request.headers.get("accept-encoding").?;
        var splits = std.mem.splitScalar(u8, encodings, ',');
        while (splits.next()) |split| {
            const encoding = std.mem.trim(u8, split, " ");
            const is_gzip = std.ascii.eqlIgnoreCase(encoding, "gzip");
            const is_wildcard = std.ascii.eqlIgnoreCase(encoding, "*");
            if (is_gzip or is_wildcard) try response.addHeader(allocator, "Content-Encoding", "gzip");
        }
    }

    if (std.ascii.eqlIgnoreCase(request.path, "/")) return response;

    const endpoint_start = 1;
    const endpoint_end = std.ascii.findIgnoreCasePos(request.path, 1, "/") orelse (request.path.len); // find next '/'
    const endpoint = request.path[endpoint_start..endpoint_end];
    var query_content: []const u8 = "";
    if (endpoint_end != request.path.len) {
        query_content = request.path[endpoint_end + 1 ..];
    }

    if (std.ascii.eqlIgnoreCase(endpoint, "files")) {
        std.debug.print("files endpoint\nopening directory: {s}\nopening file: {s}\n", .{ file_directory, query_content });
        const dir = try std.Io.Dir.openDirAbsolute(io, file_directory, std.Io.Dir.OpenOptions{});
        std.debug.print("file directory has been opened\n", .{});

        switch (request.method) {
            http.Method.GET => {
                var content = dir.readFileAlloc(io, query_content, allocator, std.Io.Limit.unlimited) catch |err| {
                    switch (err) {
                        std.Io.File.OpenError.FileNotFound => {
                            response.status = http.StatusCode.HTTP_404;
                            response.reason = "Not Found";
                            return response;
                        },
                        else => return err,
                    }
                };

                std.debug.print("File has been read\n", .{});
                if (response.headers.contains("Content-Encoding")) {
                    content = try compressBody(allocator, content, std.compress.flate.Container.gzip);
                }
                try response.addHeader(allocator, "Content-Type", "application/octet-stream");
                const content_length = try std.fmt.allocPrint(allocator, "{d}", .{content.len});
                try response.addHeader(allocator, "Content-Length", content_length);
                response.body = content;
                return response;
            },
            http.Method.POST => {
                const file = try dir.createFile(io, query_content, std.Io.Dir.CreateFileOptions{});
                defer file.close(io);
                try file.writeStreamingAll(io, request.body);

                response.status = http.StatusCode.HTTP_201;
                response.reason = "Created";
                return response;
            },
            else => {},
        }
    }

    if (std.ascii.eqlIgnoreCase(endpoint, "echo")) {
        try response.addHeader(allocator, "Content-Type", "text/plain");
        var content = @constCast(query_content);
        if (response.headers.contains("Content-Encoding")) {
            content = try compressBody(allocator, content, std.compress.flate.Container.gzip);
        }
        const content_length = try std.fmt.allocPrint(allocator, "{d}", .{content.len});
        try response.addHeader(allocator, "Content-Length", content_length);
        response.body = content;
        return response;
    }

    if (std.ascii.eqlIgnoreCase(endpoint, "user-agent")) {
        const header_content = request.headers.get("user-agent") orelse {
            response.status = http.StatusCode.HTTP_400;
            response.reason = "Bad Request";
            const body = "Missing User-Agent header";
            var content: []u8 = @constCast(body);
            if (response.headers.contains("Content-Encoding")) {
                content = try compressBody(allocator, content, std.compress.flate.Container.gzip);
            }
            response.body = content;
            const content_length = try std.fmt.allocPrint(allocator, "{d}", .{content.len});
            _ = try response.addHeader(allocator, "Content-Length", content_length);
            return response;
        };

        _ = try response.addHeader(allocator, "Content-Type", "text/plain");
        var content = @constCast(header_content);
        if (response.headers.contains("Content-Encoding")) {
            content = try compressBody(allocator, @constCast(header_content), std.compress.flate.Container.gzip);
        }
        const content_length = try std.fmt.allocPrint(allocator, "{d}", .{content.len});
        _ = try response.addHeader(allocator, "Content-Length", content_length);
        response.body = content;
        return response;
    }

    response.status = http.StatusCode.HTTP_404;
    response.reason = "Not Found";

    return response;
}

fn compressBody(allocator: std.mem.Allocator, data: []u8, container: std.compress.flate.Container) ![]u8 {
    var out = try std.Io.Writer.Allocating.initCapacity(allocator, 4096);
    errdefer out.deinit();

    var window: [std.compress.flate.max_window_len]u8 = undefined;

    var compress = try std.compress.flate.Compress.init(&out.writer, &window, container, std.compress.flate.Compress.Options.fastest);

    try compress.writer.writeAll(data);
    try compress.finish();

    return out.toOwnedSlice();
}
