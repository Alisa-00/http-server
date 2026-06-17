const std = @import("std");
const http = @import("http.zig");

pub const ParseError = error{
    InvalidRequest,
    InvalidMethod,
    InvalidHeader,
    UnsupportedVersion,
    HeaderTooLong,
};

fn parseSpace(reader: *std.Io.Reader) ![]const u8 {
    const value = try reader.takeDelimiter(' ') orelse return ParseError.InvalidRequest;
    return value;
}

fn parseNewline(reader: *std.Io.Reader) ![]const u8 {
    const untrimmed = try reader.takeDelimiter('\n') orelse return ParseError.InvalidRequest;

    if (untrimmed[untrimmed.len - 1] == '\r') {
        return untrimmed[0 .. untrimmed.len - 1];
    }
    return untrimmed;
}

fn parseMethod(reader: *std.Io.Reader) !http.Method {
    const method_string = try parseSpace(reader);
    const method = std.meta.stringToEnum(http.Method, method_string);
    return method orelse return ParseError.InvalidMethod;
}

fn parseTarget(reader: *std.Io.Reader) ![]const u8 {
    return try parseSpace(reader);
}

fn parseVersion(reader: *std.Io.Reader) !http.Version {
    const version_string = try parseNewline(reader);
    const version = std.meta.stringToEnum(http.Version, version_string);
    return version orelse return ParseError.UnsupportedVersion;
}

fn parseHeaderName(reader: *std.Io.Reader) ![]const u8 {
    const end_distance = try reader.peekDelimiterExclusive('\n');
    const header_distance = try reader.peekDelimiterExclusive(':');

    if (end_distance.len > header_distance.len) {
        const name = try reader.takeDelimiter(':') orelse return ParseError.InvalidRequest;
        return name;
    }

    return try parseNewline(reader);
}

fn parseHeaderValue(reader: *std.Io.Reader) ![]const u8 {
    const value = try parseNewline(reader);
    return value;
}

fn parseBody(allocator: std.mem.Allocator, reader: *std.Io.Reader, length: usize) ![]const u8 {
    const body = try allocator.alloc(u8, length);
    try reader.readSliceAll(body);
    return body;
}

pub fn parseRequest(allocator: std.mem.Allocator, reader: *std.Io.Reader) !http.Request {
    const method = try parseMethod(reader);
    const target = try parseTarget(reader);
    const version = try parseVersion(reader);

    var request = http.Request{
        .method = method,
        .path = target,
        .query = "",
        .version = version,
        .headers = .empty,
        .body = "",
    };

    var header = try parseHeaderName(reader);
    while (!std.ascii.eqlIgnoreCase(header, "")) : (header = try parseHeaderName(reader)) {
        const value = try parseHeaderValue(reader);
        const header_lowercase = try std.ascii.allocLowerString(allocator, header);
        _ = try request.addHeader(allocator, header_lowercase, value);
    }

    var length: u32 = 0;
    if (request.headers.contains("content-length")) {
        length = try std.fmt.parseInt(u32, request.headers.get("content-length").?, 10);
        if (length < http.MAX_BODY_SIZE) {
            length = http.MAX_BODY_SIZE;
        }
    }

    request.body = try parseBody(allocator, reader, length);

    return request;
}

//const builtin = @import("builtin");
//const REQUEST = if (builtin.is_test) blk: {
//    break :blk "GET /hello?name=test HTTP/1.1\r\n" ++
//        "Host:localhost:8080\r\n" ++
//        "User-Agent:curl/8.7.1\r\n" ++
//        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
//        "Accept-Encoding: gzip, deflate\r\n" ++
//        "Connection: keep-alive\r\n" ++
//        "Content-Length: 10\r\n" ++
//        "\r\n" ++
//        "THIS IS THE BODY\r\n";
//};
//var http_request = if (builtin.is_test) blk: {
//    break :blk http.Request{
//        .method = .GET,
//        .path = "/hello",
//        .query = "name=test",
//        .version = http.Version.HTTP_11,
//        .headers = undefined,
//        .body = "THIS IS THE BODY\r\n",
//    };
//};
//
//const test_allocator = if (builtin.is_test) blk: {
//    break :blk std.testing.allocator;
//};
//
//test "parse http methods test" {
//    std.debug.print("parse method test initiated\n\n", .{});
//
//    var map = try http.initMethodMap(test_allocator);
//    defer map.deinit();
//
//    const TEST_REQUEST = " / HTTP/1.1\r\n";
//
//    for (http.method_strings) |method| {
//        std.debug.print("TESTING METHOD: {s}\t\t\t", .{method});
//
//        const slices = &[_][]const u8{ method, TEST_REQUEST };
//        const FULL_REQUEST = try std.mem.concat(test_allocator, u8, slices);
//        defer test_allocator.free(FULL_REQUEST);
//
//        const parsed_method, _ = try parseMethod(FULL_REQUEST, map);
//        const method_enum = map.get(method).?;
//
//        const request = http.Request{
//            .method = method_enum,
//            .path = "/",
//            .query = "",
//            .version = http.Version.HTTP_11,
//            .headers = undefined,
//            .body = "",
//        };
//
//        try std.testing.expectEqual(parsed_method, request.method);
//
//        std.debug.print("SUCCESS\n", .{});
//    }
//
//    for (http.method_strings) |method| {
//        const method_slices = &[_][]const u8{ "no", method };
//        const name = try std.mem.concat(test_allocator, u8, method_slices);
//        defer test_allocator.free(name);
//        std.debug.print("TESTING FAKE METHOD: {s}\t\t\t\t", .{name});
//
//        const slices = &[_][]const u8{ name, TEST_REQUEST };
//        const FULL_REQUEST = try std.mem.concat(test_allocator, u8, slices);
//        defer test_allocator.free(FULL_REQUEST);
//
//        const m = try parseMethod(FULL_REQUEST, map);
//        try std.testing.expectEqual(http.Method.OTHER, m.@"0");
//        std.debug.print("SUCCESS\n", .{});
//    }
//
//    std.debug.print("\nparse method test finished successfully!\n", .{});
//}
//
//test "parse http target test" {
//    std.debug.print("\nparse target test initiated\n", .{});
//
//    var map = try http.initMethodMap(test_allocator);
//    defer map.deinit();
//
//    _, var remaining = try parseMethod(REQUEST, map);
//    const path, const query, remaining = try parseTarget(remaining);
//
//    try std.testing.expectEqualStrings(path, http_request.path);
//    try std.testing.expectEqualStrings(query, http_request.query);
//
//    std.debug.print("parse target test finished successfully!\n", .{});
//}
//
//test "parse http version test" {
//    std.debug.print("\nparse version test initiated\n", .{});
//
//    var method_map = try http.initMethodMap(test_allocator);
//    defer method_map.deinit();
//    var version_map = try http.initVersionMap(test_allocator);
//    defer version_map.deinit();
//
//    _, var remaining = try parseMethod(REQUEST, method_map);
//    _, _, remaining = try parseTarget(remaining);
//
//    const version, remaining = try parseVersion(remaining, version_map);
//
//    try std.testing.expectEqual(version, http_request.version);
//
//    std.debug.print("parse version test finished successfully!\n", .{});
//}
//
//test "parse http full request test" {
//    std.debug.print("\nparse full request test initiated\n", .{});
//
//    var method_map = try http.initMethodMap(test_allocator);
//    defer method_map.deinit();
//    var version_map = try http.initVersionMap(test_allocator);
//    defer version_map.deinit();
//
//    var header_list = std.array_hash_map(allocator, http.Header).init(test_allocator);
//    try header_list.put("Host", http.Header{ .value = "localhost:8080" });
//    try header_list.put("User-Agent", http.Header{ .value = "curl/8.7.1" });
//    try header_list.put("Accept", http.Header{ .value = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" });
//    try header_list.put("Accept-Encoding", http.Header{ .value = "gzip, deflate" });
//    try header_list.put("Connection", http.Header{ .value = "keep-alive" });
//    try header_list.put("Content-Length", http.Header{ .value = "10" });
//    defer header_list.deinit();
//    http_request.headers = header_list;
//
//    var parsed = try parseRequest(REQUEST, test_allocator, method_map, version_map);
//    defer parsed.headers.deinit();
//
//    try std.testing.expectEqual(http_request.method, parsed.method);
//    try std.testing.expectEqualStrings(http_request.path, parsed.path);
//    try std.testing.expectEqualStrings(http_request.query, parsed.query);
//    try std.testing.expectEqual(http_request.version, parsed.version);
//    for (parsed.headers.keys(), http_request.headers.keys()) |parsed_header, test_header| {
//        try std.testing.expectEqualStrings(test_header, parsed_header);
//        try std.testing.expectEqualStrings(http_request.headers.get(test_header).?.value, parsed.headers.get(parsed_header).?.value);
//    }
//    try std.testing.expectEqualStrings(http_request.body[0..10], parsed.body);
//
//    std.debug.print("parse full request test finished successfully!\n", .{});
//}
