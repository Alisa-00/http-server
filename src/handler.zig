const std = @import("std");
const http = @import("http.zig");
const app = @import("app.zig");

const cwd = std.fs.cwd();

const DEFAULT_STATUS_CODE = http.StatusCode.HTTP_200;
const DEFAULT_REASON = "OK";
const DEFAULT_BODY = "";
const DEFAULT_HEADER_COUNT = 10;

pub fn handle(allocator: std.mem.Allocator, request: http.Request) !http.Response {

    // verify correctness of request
    // check request headers that need to be passed on to resp
    if (!validateVersion(request.version)) return BAD_VERSION_RESPONSE;
    if (!validateHeaders(request.headers)) return BAD_HEADERS_RESPONSE;
    if (!validateBody(request.body)) return BAD_BODY_RESPONSE;
    if (!validateExpect(request.headers)) return BAD_EXPECT_RESPONSE;

    const resp = switch (request.method) {
        .GET => try app.handleGet(request, allocator),
        .POST => try app.handlePost(request, allocator),
        .PUT => try app.handlePut(request, allocator),
        .DELETE => try app.handleDelete(request, allocator),
        .PATCH => try app.handlePatch(request, allocator),
        .OPTIONS => try app.handleOptions(request, allocator),
        .HEAD => try app.handleHead(request, allocator),
        .TRACE => try app.handleTrace(request, allocator),
        .CONNECT => try app.handleConnect(request, allocator),
        .OTHER => try app.handleOther(request, allocator),
    };

    // verify correctness of response

    return resp;
}

fn validateVersion(version: http.Version) bool {
    switch (version) {
        http.Version.HTTP_09 => return false,
        http.Version.HTTP_10 => return true,
        http.Version.HTTP_11 => return true,
        http.Version.HTTP_20 => return false,
        http.Version.HTTP_30 => return false,
    }
}

fn validateHeaders(headers: std.StringArrayHashMap(http.Header)) bool {

    // Host header must exist
    _ = headers.get("Host") orelse return false;

    // Only Transfer-Encoding value allowed is chunked
    const transfer_encoding = headers.contains("Transfer-Encoding");
    const content_length = headers.contains("Content-Length");

    if (transfer_encoding) {
        const value = headers.get("Transfer-Encoding").?.value;
        if (!std.ascii.eqlIgnoreCase(value, "chunked")) return false;
    }

    // Only one allowed: Transfer-Encoding, Content-Length
    if (transfer_encoding and content_length) return false;

    // Content-Length must be a base 10, non-negative integer
    if (content_length) {
        _ = std.fmt.parseUnsigned(u64, headers.get("Content-Length").?.value, 10) catch return false;
    }

    return true;
}

const MAX_BODY_LENGTH = 1000 * 1000;
fn validateBody(body: []const u8) bool {
    if (body.len > MAX_BODY_LENGTH) return false;
    return true;
}

fn validateExpect(headers: std.StringArrayHashMap(http.Header)) bool {
    if (headers.contains("Expect")) {
        const value = headers.get("Expect").?.value;
        if (std.ascii.eqlIgnoreCase(value, "100-continue")) return false;
    }
    return true;
}

const BAD_VERSION_RESPONSE = http.Response{
    .version = http.Version.HTTP_11,
    .status = http.StatusCode.HTTP_505,
    .reason = "HTTP Version Not Supported",
    .headers = http.HeaderCollection{
        .slice = &[_]http.Header{
            .{ .name = "Content-Type", .value = "text/plain" },
            .{ .name = "Content-Length", .value = "32" },
            .{ .name = "Connection", .value = "close" },
        },
    },
    .body = "505 HTTP Version Not Supported\r\n",
};

const BAD_HEADERS_RESPONSE = http.Response{
    .version = http.Version.HTTP_11,
    .status = http.StatusCode.HTTP_400,
    .reason = "Bad Request",
    .headers = http.HeaderCollection{
        .slice = &[_]http.Header{
            .{ .name = "Content-Type", .value = "text/plain" },
            .{ .name = "Content-Length", .value = "17" },
            .{ .name = "Connection", .value = "close" },
        },
    },
    .body = "400 Bad Request\r\n",
};

const BAD_BODY_RESPONSE = http.Response{
    .version = http.Version.HTTP_11,
    .status = http.StatusCode.HTTP_413,
    .reason = "Bad Request",
    .headers = http.HeaderCollection{
        .slice = &[_]http.Header{
            .{ .name = "Content-Type", .value = "text/plain" },
            .{ .name = "Content-Length", .value = "23" },
            .{ .name = "Connection", .value = "close" },
        },
    },
    .body = "413 Payload Too Large\r\n",
};

const BAD_EXPECT_RESPONSE = http.Response{
    .version = http.Version.HTTP_11,
    .status = http.StatusCode.HTTP_413,
    .reason = "Bad Request",
    .headers = http.HeaderCollection{
        .slice = &[_]http.Header{
            .{ .name = "Content-Type", .value = "text/plain" },
            .{ .name = "Content-Length", .value = "24" },
            .{ .name = "Connection", .value = "close" },
        },
    },
    .body = "417 Expectation failed\r\n",
};
