const std = @import("std");

pub const map_strings = [_][:0]const u8{ "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE", "CONNECT" };

fn buildHttpEnum() type {

    // Generate enum type from string names
    const method_enums = blk: {
        var fields: [map_strings.len]std.builtin.Type.EnumField = undefined;
        for (map_strings, 0..) |name, i| {
            fields[i] = .{ .name = name, .value = i };
        }
        break :blk @Type(.{ .@"enum" = .{
            .tag_type = u32,
            .fields = &fields,
            .decls = &.{},
            .is_exhaustive = true,
        } });
    };

    return method_enums;
}

pub const Method = buildHttpEnum();
pub const MethodMap = std.StringHashMap(Method);

pub fn initMethodMap(allocator: std.mem.Allocator) !MethodMap {
    var method_map = MethodMap.init(allocator);
    for (map_strings, 0..) |name, i| {
        try method_map.put(name, @enumFromInt(i));
    }
    return method_map;
}

pub const Version = enum {
    HTTP_10,
    HTTP_11,
    //HTTP_20,
    //HTTP_30,
};

pub const VersionMap = std.StringHashMap(Version);

pub const version_enum_strings = [_][]const u8{ "HTTP_10", "HTTP_11" }; //, "HTTP_20", "HTTP_30" };
pub const version_http_strings = [_][]const u8{ "HTTP/1.0", "HTTP/1.1" }; //, "HTTP/2.0", "HTTP/3.0" };

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
    version: Version,
    body: []const u8,
};

pub const Header = struct {
    host: []const u8,
    user_agent: []const u8,
    accept: []const u8,
    accept_encoding: []const u8,
    connection: []const u8,
};
