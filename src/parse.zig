const std = @import("std");
const http = @import("http.zig");

pub const ParseError = error{
    InvalidRequest,
    InvalidMethod,
    UnsupportedVersion,
    OutOfMemory,
};

fn parseMethod(str: []const u8, map: http.MethodMap) ParseError!struct { method: http.Method, remaining: []const u8 } {
    const index = std.mem.indexOf(u8, str, " ") orelse return ParseError.InvalidRequest;
    const method_str = str[0..index];
    const remaining = str[index + 1 ..];

    const method_enum = map.get(method_str) orelse {
        return ParseError.InvalidMethod;
    };

    return .{ .method = method_enum, .remaining = remaining };
}

fn parsePath(str: []const u8) ParseError!struct { path: []const u8, remaining: []const u8 } {
    const index = std.mem.indexOf(u8, str, " ") orelse return ParseError.InvalidRequest;
    const path_str = str[0..index];
    const remaining = str[index + 1 ..];

    return .{ .path = path_str, .remaining = remaining };
}

fn parseVersion(str: []const u8, map: http.VersionMap) ParseError!struct { version: http.Version, remaining: []const u8 } {
    const index = std.mem.indexOf(u8, str, "\n") orelse return ParseError.InvalidRequest;
    const version_str = str[0..index];
    const remaining = str[index + 1 ..];

    const version_enum = map.get(version_str) orelse {
        return ParseError.UnsupportedVersion;
    };

    return .{ .version = version_enum, .remaining = remaining };
}

pub fn parseHeaders(str: []const u8) ParseError!void {
    str = 'a';
}

pub fn parseBody(str: []const u8) ParseError!void {
    str = 'a';
}

pub fn parseRequest(str: []const u8, method_map: http.MethodMap, version_map: http.VersionMap) ParseError!http.Request {
    const parsed_method = try parseMethod(str, method_map);
    const method = parsed_method.method;
    const remaining1 = parsed_method.remaining;

    const parsed_path = try parsePath(remaining1);
    const path = parsed_path.path;
    const remaining2 = parsed_path.remaining;

    const parsed_version = try parseVersion(remaining2, version_map);
    const version = parsed_version.version;
    //const remaining3 = parsed_version.remaining;

    //const parsed_headers = try parseHeaders(remaining3);
    //const headers = parsed_headers.headers;
    //const remaining4 = parsed_headers.remaining;

    //const parsed_body = try parseBody(remaining4);
    //const body = parsed_body;

    const req = http.Request{
        .method = method,
        .path = path,
        .version = version,
        .body = "",
    };

    return req;
}

const builtin = @import("builtin");
const REQUEST = blk: {
    if (builtin.is_test) {
        break :blk 
        \\GET /hello?name=test HTTP/1.1
        \\Host: localhost:8080
        \\User-Agent: curl/8.7.1
        \\Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
        \\Accept-Encoding: gzip, deflate
        \\Connection: keep-alive
        \\
        ;
    }
};

var gpa = blk: {
    if (builtin.is_test) {
        break :blk std.heap.DebugAllocator(.{}){};
    }
};

const test_allocator = blk: {
    if (builtin.is_test) {
        break :blk gpa.allocator();
    }
};

test "parse http methods test" {
    std.debug.print("parse method test initiated\n\n", .{});

    var map = try http.initMethodMap(test_allocator);
    defer map.deinit();

    const TEST_REQUEST = " / HTTP/1.1";

    for (http.method_strings) |method| {
        std.debug.print("TESTING METHOD: {s}\t\t\t", .{method});

        const slices = &[_][]const u8{ method, TEST_REQUEST };
        const FULL_REQUEST = try std.mem.concat(test_allocator, u8, slices);

        const parsed = try parseMethod(FULL_REQUEST, map);

        const method_enum = map.get(method).?;

        const request = http.Request{
            .method = method_enum,
            .path = "",
            .version = http.Version.HTTP_11,
            .body = "",
        };

        try std.testing.expectEqual(parsed.method, request.method);

        std.debug.print("SUCCESS\n", .{});
    }

    for (http.method_strings) |method| {
        const method_slices = &[_][]const u8{ "no", method };
        const name = try std.mem.concat(test_allocator, u8, method_slices);
        std.debug.print("TESTING FAKE METHOD: {s}\t\t\t\t", .{name});

        const slices = &[_][]const u8{ name, TEST_REQUEST };
        const FULL_REQUEST = try std.mem.concat(test_allocator, u8, slices);

        try std.testing.expectError(ParseError.InvalidMethod, parseMethod(FULL_REQUEST, map));
        std.debug.print("SUCCESS\n", .{});
    }

    std.debug.print("\nparse method test finished successfully!\n", .{});
}

test "parse http path test" {
    std.debug.print("\nparse path test initiated\n", .{});

    var map = try http.initMethodMap(test_allocator);
    defer map.deinit();

    const parsed = try parseMethod(REQUEST, map);
    const remaining1 = parsed.remaining;

    const parsed2 = try parsePath(remaining1);

    const request = http.Request{
        .method = .GET,
        .path = "/hello?name=test",
        .version = http.Version.HTTP_11,
        .body = "",
    };

    try std.testing.expectEqualStrings(parsed2.path, request.path);

    std.debug.print("parse path test finished successfully!\n", .{});
}

test "parse http version test" {
    std.debug.print("\nparse version test initiated\n", .{});

    var method_map = try http.initMethodMap(test_allocator);
    defer method_map.deinit();
    var version_map = try http.initVersionMap(test_allocator);
    defer version_map.deinit();

    const parsed = try parseMethod(REQUEST, method_map);
    const remaining1 = parsed.remaining;

    const parsed2 = try parsePath(remaining1);
    const remaining2 = parsed2.remaining;

    const parsed3 = try parseVersion(remaining2, version_map);

    const request = http.Request{
        .method = .GET,
        .path = "/hello?name=test",
        .version = http.Version.HTTP_11,
        .body = "",
    };

    try std.testing.expectEqual(parsed3.version, request.version);

    std.debug.print("parse version test finished successfully!\n", .{});
}

test "parse http full request test" {
    std.debug.print("\nparse version test initiated\n", .{});

    var method_map = try http.initMethodMap(test_allocator);
    defer method_map.deinit();
    var version_map = try http.initVersionMap(test_allocator);
    defer version_map.deinit();

    const parsed = try parseRequest(REQUEST, method_map, version_map);

    const request = http.Request{
        .method = .GET,
        .path = "/hello?name=test",
        .version = http.Version.HTTP_11,
        .body = "",
    };

    try std.testing.expectEqual(parsed.method, request.method);
    try std.testing.expectEqualStrings(parsed.path, request.path);
    try std.testing.expectEqual(parsed.version, request.version);

    std.debug.print("parse version test finished successfully!\n", .{});
}
