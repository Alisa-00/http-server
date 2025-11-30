const std = @import("std");
const http = @import("http.zig");

pub const ParseError = error{
    InvalidRequest,
    InvalidMethod,
    InvalidHeader,
    UnsupportedVersion,
    OutOfMemory,
};

const SPACE = " ";
const QUERY_DELIMITER = "?";
fn parseMethod(str: []const u8, map: http.MethodMap) ParseError!struct { http.Method, []const u8 } {
    const index = std.mem.indexOf(u8, str, SPACE) orelse return ParseError.InvalidRequest;
    const method_str = str[0..index];
    const remaining = str[index + SPACE.len ..];

    const method_enum = map.get(method_str) orelse {
        return ParseError.InvalidMethod;
    };

    return .{ method_enum, remaining };
}

fn parseTarget(str: []const u8) ParseError!struct { []const u8, []const u8, []const u8 } {
    const index = std.mem.indexOf(u8, str, SPACE) orelse return ParseError.InvalidRequest;
    const target_str = str[0..index];
    const remaining = str[index + SPACE.len ..];

    const query_index = std.mem.indexOf(u8, target_str, QUERY_DELIMITER) orelse target_str.len;
    const path = target_str[0..query_index];
    var query = target_str[query_index..];

    if (query.len > 0) query = query[QUERY_DELIMITER.len..];

    return .{ path, query, remaining };
}

const LINE_DELIMITER = "\r\n";
fn parseVersion(str: []const u8, map: http.VersionMap) ParseError!struct { http.Version, []const u8 } {
    const index = std.mem.indexOf(u8, str, LINE_DELIMITER) orelse return ParseError.InvalidRequest;
    const version_str = str[0..index];
    const remaining = str[index + LINE_DELIMITER.len ..];

    const version_enum = map.get(version_str) orelse {
        return ParseError.UnsupportedVersion;
    };

    return .{ version_enum, remaining };
}

const HEADER_VALUE_SEPARATOR = ":";
fn parseHeaderLine(str: []const u8) ParseError!struct { []const u8, http.Header } {
    const index = std.mem.indexOf(u8, str, HEADER_VALUE_SEPARATOR) orelse return ParseError.InvalidHeader;
    const name = str[0..index];
    const rest = str[index + HEADER_VALUE_SEPARATOR.len ..];
    if (std.mem.startsWith(u8, rest, " ")) {
        return .{ name, .{ .value = rest[HEADER_VALUE_SEPARATOR.len..] } };
    }
    return .{ name, .{ .value = rest } };
}

pub fn parseHeaders(str: []const u8, allocator: std.mem.Allocator) !struct { std.StringArrayHashMap(http.Header), isize, []const u8 } {
    var remaining: []const u8 = str;
    var header_list = std.StringArrayHashMap(http.Header).init(allocator);
    var done = std.mem.startsWith(u8, remaining, LINE_DELIMITER);
    var content_length: isize = -1;
    while (!done) : (done = std.mem.startsWith(u8, remaining, LINE_DELIMITER)) {
        const index = std.mem.indexOf(u8, remaining, LINE_DELIMITER) orelse return ParseError.InvalidRequest;
        const line = remaining[0..index];
        const name, const header = try parseHeaderLine(line);
        try header_list.put(name, header);
        if (std.ascii.eqlIgnoreCase(name, "content-length")) content_length = try std.fmt.parseInt(isize, header.value, 10);
        remaining = remaining[index + LINE_DELIMITER.len ..];
    }
    remaining = remaining[LINE_DELIMITER.len..];

    return .{ header_list, content_length, remaining };
}

pub fn parseBody(str: []const u8, content_length: isize) ParseError![]const u8 {
    if (content_length > -1) {
        if (content_length >= str.len) return str;
        return str[0..@intCast(content_length)];
    }

    return str;
}

pub fn parseRequest(str: []const u8, allocator: std.mem.Allocator, method_map: http.MethodMap, version_map: http.VersionMap) !http.Request {
    const method, var remaining = try parseMethod(str, method_map);
    const path, const query, remaining = try parseTarget(remaining);
    const version, remaining = try parseVersion(remaining, version_map);
    const headers, const length, remaining = try parseHeaders(remaining, allocator);
    const body = try parseBody(remaining, length);

    const req = http.Request{
        .method = method,
        .path = path,
        .query = query,
        .version = version,
        .headers = headers,
        .body = body,
    };

    return req;
}

const builtin = @import("builtin");
const REQUEST = if (builtin.is_test)
blk: {
    break :blk "GET /hello?name=test HTTP/1.1\r\n" ++
        "Host:localhost:8080\r\n" ++
        "User-Agent:curl/8.7.1\r\n" ++
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
        "Accept-Encoding: gzip, deflate\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Content-Length: 10\r\n" ++
        "\r\n" ++
        "THIS IS THE BODY\r\n";
};
var http_request = if (builtin.is_test)
blk: {
    break :blk http.Request{
        .method = .GET,
        .path = "/hello",
        .query = "name=test",
        .version = http.Version.HTTP_11,
        .headers = undefined,
        .body = "THIS IS THE BODY\r\n",
    };
};

const test_allocator = if (builtin.is_test)
blk: {
    break :blk std.testing.allocator;
};

test "parse http methods test" {
    std.debug.print("parse method test initiated\n\n", .{});

    var map = try http.initMethodMap(test_allocator);
    defer map.deinit();

    const TEST_REQUEST = " / HTTP/1.1\r\n";

    for (http.method_strings) |method| {
        std.debug.print("TESTING METHOD: {s}\t\t\t", .{method});

        const slices = &[_][]const u8{ method, TEST_REQUEST };
        const FULL_REQUEST = try std.mem.concat(test_allocator, u8, slices);
        defer test_allocator.free(FULL_REQUEST);

        const parsed_method, _ = try parseMethod(FULL_REQUEST, map);
        const method_enum = map.get(method).?;

        const request = http.Request{
            .method = method_enum,
            .path = "/",
            .query = "",
            .version = http.Version.HTTP_11,
            .headers = undefined,
            .body = "",
        };

        try std.testing.expectEqual(parsed_method, request.method);

        std.debug.print("SUCCESS\n", .{});
    }

    for (http.method_strings) |method| {
        const method_slices = &[_][]const u8{ "no", method };
        const name = try std.mem.concat(test_allocator, u8, method_slices);
        defer test_allocator.free(name);
        std.debug.print("TESTING FAKE METHOD: {s}\t\t\t\t", .{name});

        const slices = &[_][]const u8{ name, TEST_REQUEST };
        const FULL_REQUEST = try std.mem.concat(test_allocator, u8, slices);
        defer test_allocator.free(FULL_REQUEST);

        try std.testing.expectError(ParseError.InvalidMethod, parseMethod(FULL_REQUEST, map));
        std.debug.print("SUCCESS\n", .{});
    }

    std.debug.print("\nparse method test finished successfully!\n", .{});
}

test "parse http target test" {
    std.debug.print("\nparse target test initiated\n", .{});

    var map = try http.initMethodMap(test_allocator);
    defer map.deinit();

    _, var remaining = try parseMethod(REQUEST, map);
    const path, const query, remaining = try parseTarget(remaining);

    try std.testing.expectEqualStrings(path, http_request.path);
    try std.testing.expectEqualStrings(query, http_request.query);

    std.debug.print("parse target test finished successfully!\n", .{});
}

test "parse http version test" {
    std.debug.print("\nparse version test initiated\n", .{});

    var method_map = try http.initMethodMap(test_allocator);
    defer method_map.deinit();
    var version_map = try http.initVersionMap(test_allocator);
    defer version_map.deinit();

    _, var remaining = try parseMethod(REQUEST, method_map);
    _, _, remaining = try parseTarget(remaining);

    const version, remaining = try parseVersion(remaining, version_map);

    try std.testing.expectEqual(version, http_request.version);

    std.debug.print("parse version test finished successfully!\n", .{});
}

test "parse http full request test" {
    std.debug.print("\nparse full request test initiated\n", .{});

    var method_map = try http.initMethodMap(test_allocator);
    defer method_map.deinit();
    var version_map = try http.initVersionMap(test_allocator);
    defer version_map.deinit();

    var header_list = std.StringArrayHashMap(http.Header).init(test_allocator);
    try header_list.put("Host", http.Header{ .value = "localhost:8080" });
    try header_list.put("User-Agent", http.Header{ .value = "curl/8.7.1" });
    try header_list.put("Accept", http.Header{ .value = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" });
    try header_list.put("Accept-Encoding", http.Header{ .value = "gzip, deflate" });
    try header_list.put("Connection", http.Header{ .value = "keep-alive" });
    try header_list.put("Content-Length", http.Header{ .value = "10" });
    defer header_list.deinit();
    http_request.headers = header_list;

    var parsed = try parseRequest(REQUEST, test_allocator, method_map, version_map);
    defer parsed.headers.deinit();

    try std.testing.expectEqual(http_request.method, parsed.method);
    try std.testing.expectEqualStrings(http_request.path, parsed.path);
    try std.testing.expectEqualStrings(http_request.query, parsed.query);
    try std.testing.expectEqual(http_request.version, parsed.version);
    for (parsed.headers.keys(), http_request.headers.keys()) |parsed_header, test_header| {
        try std.testing.expectEqualStrings(test_header, parsed_header);
        try std.testing.expectEqualStrings(http_request.headers.get(test_header).?.value, parsed.headers.get(parsed_header).?.value);
    }
    try std.testing.expectEqualStrings(http_request.body[0..10], parsed.body);

    std.debug.print("parse full request test finished successfully!\n", .{});
}
