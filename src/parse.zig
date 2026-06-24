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
    const endline_string = try reader.peekDelimiterExclusive('\n');
    const separator_position = std.ascii.findIgnoreCase(endline_string, ":");
    if (separator_position) |_| {
        const name = try reader.takeDelimiter(':') orelse return ParseError.InvalidRequest;
        return name;
    }

    const empty_line = try parseNewline(reader);
    return empty_line;
}

fn parseHeaderValue(reader: *std.Io.Reader) ![]const u8 {
    const value = try parseNewline(reader);
    if (value[0] == ' ') {
        return value[1..];
    }
    return value;
}

fn parseBody(allocator: std.mem.Allocator, reader: *std.Io.Reader, length: usize) ![]const u8 {
    const body = try allocator.alloc(u8, length);
    std.debug.print("allocated body!\n{any}\n", .{body});
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
        if (length > http.MAX_BODY_SIZE) {
            length = http.MAX_BODY_SIZE;
        }
    }

    request.body = try parseBody(allocator, reader, length);

    return request;
}
