const std = @import("std");

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    OPTIONS,
    HEAD,
    TRACE,
    CONNECT,
    OTHER,
};

pub const Version = enum {
    @"HTTP/1.1",
};

pub const StatusCode = enum(u32) {
    HTTP_200 = 200,
    HTTP_201 = 201,
    HTTP_202 = 202,
    HTTP_302 = 302,
    HTTP_400 = 400,
    HTTP_404 = 404,
    HTTP_413 = 413,
    HTTP_500 = 500,
    HTTP_503 = 503,
    HTTP_505 = 505,
    Other,
};

pub const HTTP_VERSION = Version.@"HTTP/1.1";
pub const MAX_BODY_SIZE = 4000;
const DEFAULT_STATUS_CODE = StatusCode.HTTP_200;
const DEFAULT_BODY = "";
const DEFAULT_REASON = "";

pub const Request = struct {
    method: Method,
    path: []const u8,
    query: []const u8,
    version: Version,
    headers: std.array_hash_map.String([]const u8),
    body: []const u8,

    pub fn init() Request {
        return Request{
            .method = Method.GET,
            .path = "/",
            .query = "",
            .version = Version.@"HTTP/1.1",
            .headers = .empty,
            .body = "",
        };
    }

    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        self.headers.deinit(allocator);
    }

    pub fn addHeader(self: *Request, allocator: std.mem.Allocator, name: []const u8, value: []const u8) !bool {
        const name_lowercase = try std.ascii.allocLowerString(allocator, name);
        if (self.headers.contains(name_lowercase)) {
            return false;
        }

        try self.headers.put(allocator, name_lowercase, value);
        return true;
    }
};

pub const Response = struct {
    version: Version,
    status: StatusCode,
    reason: []const u8,
    headers: std.array_hash_map.String([]const u8),
    body: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Response {
        var response = Response{
            .version = HTTP_VERSION,
            .status = DEFAULT_STATUS_CODE,
            .reason = DEFAULT_REASON,
            .headers = .empty,
            .body = DEFAULT_BODY,
        };

        //const ts: u64 = @intCast(std.time.timestamp());
        //const date_string = "Tue, 29 Oct 2024 16:56:32 GMT"; //try formatDate(ts, allocator);

        //const date = try response.headers.getOrPut(allocator, "Date");
        //date.value_ptr.* = date_string;
        //const server = try response.headers.getOrPut(allocator, "Server");
        //server.value_ptr.* = "ZigTTP";
        const connection = try response.headers.getOrPut(allocator, "Connection");
        connection.value_ptr.* = "Read this value from request";
        //const host = try response.headers.getOrPut(allocator, "Host");
        //host.value_ptr.* = "Read this value from request";

        return response;
    }

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        for (self.headers.values()) |header| {
            allocator.free(header);
        }
        self.headers.deinit();
    }

    pub fn addHeader(self: *Response, allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
        const header = try self.headers.getOrPut(allocator, name);
        header.value_ptr.* = value;
    }

    pub fn toString(self: *Response, allocator: std.mem.Allocator) ![]u8 {
        var out_string: std.ArrayList(u8) = .empty;
        const first_line = try std.fmt.allocPrint(allocator, "{s} {d} {s}\r\n", .{ @tagName(self.version), @intFromEnum(self.status), self.reason });
        try out_string.appendSlice(allocator, first_line);
        for (self.headers.keys()) |header| {
            const value = self.headers.get(header).?;
            const header_line = try std.fmt.allocPrint(allocator, "{s}: {s}\r\n", .{ header, value });
            try out_string.appendSlice(allocator, header_line);
        }
        const empty_line = "\r\n";
        try out_string.appendSlice(allocator, empty_line);
        try out_string.appendSlice(allocator, self.body);

        return out_string.items;
    }
};
