const std = @import("std");
const http = @import("http.zig");

const cwd = std.fs.cwd();

const DEFAULT_STATUS_CODE = http.StatusCode.HTTP_200;
const DEFAULT_REASON = "OK";
const DEFAULT_BODY = "";
const DEFAULT_HEADER_COUNT = 10;

fn formatDate(ts: u64, allocator: std.mem.Allocator) ![]u8 {
    const weekday_names = [_][]const u8{
        "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed",
    };

    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = ts };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_seconds.getDaySeconds();

    const year = year_day.year;

    const month = @tagName(month_day.month);
    var month_upper: [3]u8 = undefined;
    month_upper[0] = std.ascii.toUpper(month[0]);
    month_upper[1] = month[1];
    month_upper[2] = month[2];

    var uppercase: [1]u8 = undefined;
    _ = std.ascii.upperString(&uppercase, month[0..1]);

    const day = month_day.day_index + 1; // day_index is 0-based
    const hour = day_secs.getHoursIntoDay();
    const minute = day_secs.getMinutesIntoHour();
    const second = day_secs.getSecondsIntoMinute();

    // weekday = (epoch_day.day + 4) % 7
    // because 1970-01-01 was weekday 4 ("Thu")
    const weekday_index: usize = @intCast((epoch_day.day + 4) % 7);

    var buf = try allocator.alloc(u8, 29);

    const date_string = std.fmt.bufPrint(
        buf[0..],
        "{s}, {d:02} {s} {d} {d:02}:{d:02}:{d:02} GMT",
        .{
            weekday_names[weekday_index],
            day,
            month_upper,
            year,
            hour,
            minute,
            second,
        },
    ) catch unreachable;

    return date_string;
}

fn initResponse(allocator: std.mem.Allocator) !http.Response {
    var response = http.Response{
        .version = http.HTTP_VERSION,
        .status = DEFAULT_STATUS_CODE,
        .reason = DEFAULT_REASON,
        .headers = http.HeaderCollection{ .map = std.StringArrayHashMap(http.Header).init(allocator) },
        .body = DEFAULT_BODY,
    };

    const ts: u64 = @intCast(std.time.timestamp());
    const date_string = try formatDate(ts, allocator);

    try response.headers.map.put("Date", http.Header{ .value = date_string, .alloc = true });
    try response.headers.map.put("Server", http.Header{ .value = "ZigTTP" });
    try response.headers.map.put("Connection", http.Header{ .value = "read from req" });
    try response.headers.map.put("Host", http.Header{ .value = "parse from req" });

    return response;
}

pub fn handleGet(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handlePost(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handlePut(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handleDelete(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handlePatch(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handleOptions(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}

pub fn handleHead(request: http.Request, allocator: std.mem.Allocator) !http.Response {

    // check if path is valid
    const filepath = if (std.ascii.startsWithIgnoreCase(request.path, "/")) request.path[1..] else request.path;
    const stat = try cwd.statFile(filepath);
    var resp = try initResponse(allocator);

    const digits = std.fmt.count("{d}", .{stat.size});
    var buf = try allocator.alloc(u8, digits);

    _ = std.fmt.bufPrint(buf[0..], "{d}", .{stat.size}) catch unreachable;

    try resp.headers.map.put("Content-Length", http.Header{ .value = buf, .alloc = true });

    return resp;
}

pub fn handleTrace(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handleConnect(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}
pub fn handleOther(request: http.Request, allocator: std.mem.Allocator) !http.Response {
    return try handleHead(request, allocator);
}

test "HEAD request" {
    const allocator = std.testing.allocator;

    var request = http.Request{
        .version = http.HTTP_VERSION,
        .method = http.Method.HEAD,
        .path = "/src/index.html",
        .query = "",
        .headers = std.StringArrayHashMap(http.Header).init(allocator),
        .body = "",
    };
    defer request.deinit();

    var res = try handleHead(request, allocator);
    defer res.deinit(allocator);

    try std.testing.expectEqual(http.HTTP_VERSION, res.version);
    try std.testing.expectEqual(http.StatusCode.HTTP_200, res.status);
    try std.testing.expectEqualStrings("OK", res.reason);
    try std.testing.expectEqualStrings("", res.body);

    const test_headers = &[_]http.Header{
        .{ .name = "Date", .value = "Sat, 25 Nov 2025 10:12:30 GMT" },
        .{ .name = "Server", .value = "ZigTTP" },
        .{ .name = "Connection", .value = "read from req" },
        .{ .name = "Host", .value = "parse from req" },
        .{ .name = "Content-Length", .value = "411740" },
    };

    for (res.headers.map.keys(), test_headers) |parsed_header, test_header| {
        std.debug.print("{s}: {s}\n", .{ parsed_header, res.headers.map.get(parsed_header).?.value });
        if (std.ascii.eqlIgnoreCase(test_header.name.?, "Date")) continue;
        try std.testing.expectEqualStrings(test_header.name.?, parsed_header);
        try std.testing.expectEqualStrings(test_header.value, res.headers.map.get(parsed_header).?.value);
    }
}
