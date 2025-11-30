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
pub const MethodMap = std.StringHashMap(Method);

pub const method_strings = blk: {
    const method_fields = @typeInfo(Method).@"enum".fields;
    var arr: [method_fields.len][]const u8 = undefined;
    for (method_fields, 0..) |field, i| {
        arr[i] = field.name;
    }
    break :blk arr;
};

pub fn initMethodMap(allocator: std.mem.Allocator) !MethodMap {
    var method_map = MethodMap.init(allocator);
    for (method_strings, 0..) |name, i| {
        try method_map.put(name, @enumFromInt(i));
    }
    return method_map;
}

pub const Version = enum {
    HTTP_11,
};

pub const HTTP_VERSION = Version.HTTP_11;

pub const VersionMap = std.StringHashMap(Version);
pub const version_http_strings = [_][]const u8{"HTTP/1.1"}; //, "HTTP/2.0", "HTTP/3.0" };

pub const version_enum_strings = blk: {
    const version_fields = @typeInfo(Version).@"enum".fields;
    var arr: [version_fields.len][]const u8 = undefined;
    for (version_fields, 0..) |field, i| {
        arr[i] = field.name;
    }
    break :blk arr;
};

pub fn initVersionMap(allocator: std.mem.Allocator) !VersionMap {
    var version_map = VersionMap.init(allocator);
    for (version_http_strings, 0..) |name, i| {
        try version_map.put(name, @enumFromInt(i));
    }

    return version_map;
}

pub const Request = struct {
    method: Method,
    path: []const u8,
    query: []const u8,
    version: Version,
    headers: std.StringArrayHashMap(Header),
    body: []const u8,

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }
};

pub const Response = struct {
    version: Version,
    status: StatusCode,
    reason: []const u8,
    headers: std.StringArrayHashMap(Header),
    body: []const u8,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        for (self.headers.values()) |header| {
            if (header.alloc) {
                allocator.free(header.value);
            }
        }
        self.headers.deinit();
    }
};

pub const Header = struct {
    value: []const u8,
    alloc: bool = false,
};

pub const QueryParam = struct {
    key: []const u8,
    value: []const u8,
};

pub const StatusCode = enum {
    HTTP_200,
    HTTP_202,
    HTTP_302,
    HTTP_400,
    HTTP_404,
    HTTP_500,
    HTTP_503,
    Other,
};
