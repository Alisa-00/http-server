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
    HTTP_09,
    HTTP_10,
    HTTP_11,
    HTTP_20,
    HTTP_30,
};

pub const HTTP_VERSION = Version.HTTP_11;

pub const VersionMap = std.StringHashMap(Version);
pub const version_http_strings = [_][]const u8{ "HTTP/0.9", "HTTP/1.0", "HTTP/1.1", "HTTP/2.0", "HTTP/3.0" };

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
    headers: HeaderCollection,
    body: []const u8,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        for (self.headers.map.values()) |header| {
            if (header.alloc) {
                allocator.free(header.value);
            }
        }
        self.headers.map.deinit();
    }
};

pub const Header = struct {
    name: ?[]const u8 = null,
    value: []const u8,
    alloc: bool = false,
};

pub const HeaderCollection = union(enum) {
    map: std.StringArrayHashMap(Header),
    slice: []const Header,
};

pub fn writeHeaders(writer: *std.Io.Writer, h: HeaderCollection) !void {
    switch (h) {
        .slice => |s| {
            for (s) |hdr| {
                try writer.print("{s}: {s}\r\n", .{ hdr.name.?, hdr.value });
            }
        },
        .map => |*m| {
            var it = m.iterator();
            while (it.next()) |entry| {
                try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.value });
            }
        },
    }
}

pub const StatusCode = enum {
    HTTP_200,
    HTTP_202,
    HTTP_302,
    HTTP_400,
    HTTP_404,
    HTTP_413,
    HTTP_500,
    HTTP_503,
    HTTP_505,
    Other,
};
