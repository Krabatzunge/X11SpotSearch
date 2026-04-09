const std = @import("std");
const c = @import("c.zig").c;

pub const CurlRequest = struct {
    allocator: std.mem.Allocator,
    url: [:0]u8,
    response: std.ArrayList(u8),
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    done: bool = false,
    err: ?anyerror = null,
    status_code: ?u32 = null,

    fn init(allocator: std.mem.Allocator, url: []const u8) !*CurlRequest {
        const req = try allocator.create(CurlRequest);
        errdefer allocator.destroy(req);

        const url_z = try allocator.dupeZ(u8, url);
        errdefer allocator.free(url_z);

        req.* = .{
            .allocator = allocator,
            .url = url_z,
            .response = .empty,
        };

        return req;
    }

    pub fn destroy(self: *CurlRequest) void {
        self.response.deinit(self.allocator);
        self.allocator.free(self.url);
        self.allocator.destroy(self);
    }

    pub fn tryValue(self: *CurlRequest) !?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.done) return null;
        if (self.err) |err| return err;
        return self.response.items;
    }

    pub fn wait(self: *CurlRequest) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (!self.done) {
            self.cond.wait(&self.mutex);
        }

        if (self.err) |err| {
            return err;
        }
        return self.response.items;
    }

    pub fn statusCode(self: *CurlRequest) ?u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.done) return null;
        return self.status_code;
    }
};

pub const AsyncCurl = struct {
    allocator: std.mem.Allocator,
    multi: *c.CURLM,
    thread: std.Thread,
    queue_mutex: std.Thread.Mutex = .{},
    queue_cond: std.Thread.Condition = .{},
    pending_requests: std.ArrayList(*CurlRequest),
    stop_flag: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const global_res = c.curl_global_init(c.CURL_GLOBAL_ALL);
        if (global_res != 0) return error.CurlGlobalInitFailed;
        errdefer c.curl_global_cleanup();

        const multi = c.curl_multi_init() orelse {
            return error.CurlMultiInitFailed;
        };
        errdefer c.curl_multi_cleanup(multi);

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .multi = multi,
            .thread = undefined,
            .pending_requests = .empty,
        };

        self.thread = try std.Thread.spawn(.{}, Self.runLoop, .{self});
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.queue_mutex.lock();
        self.stop_flag = true;
        self.queue_cond.signal();
        self.queue_mutex.unlock();

        self.thread.join();
        self.pending_requests.deinit(self.allocator);

        c.curl_multi_cleanup(self.multi);
        c.curl_global_cleanup();
        self.allocator.destroy(self);
    }

    pub fn fetch(self: *Self, url: []const u8) !*CurlRequest {
        const req = try CurlRequest.init(self.allocator, url);
        errdefer req.destroy();

        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        if (self.stop_flag) {
            return error.AsyncCurlStopped;
        }

        try self.pending_requests.append(self.allocator, req);
        self.queue_cond.signal();
        return req;
    }

    pub fn wait(self: *Self, req: *CurlRequest) ![]const u8 {
        _ = self;
        return req.wait();
    }

    pub fn try_value(self: *Self, req: *CurlRequest) !?[]const u8 {
        _ = self;
        return req.tryValue();
    }

    pub fn release(self: *Self, req: *CurlRequest) void {
        _ = self;
        req.destroy();
    }

    fn runLoop(self: *Self) void {
        const ActiveRequest = struct {
            easy: *c.CURL,
            req: *CurlRequest,
        };

        var active_requests: std.ArrayList(ActiveRequest) = .empty;
        defer {
            for (active_requests.items) |item| {
                abortActiveRequest(self, item.easy, item.req);
            }
            active_requests.deinit(self.allocator);
        }

        while (true) {
            self.queue_mutex.lock();

            while (!self.stop_flag and self.pending_requests.items.len == 0 and active_requests.items.len == 0) {
                self.queue_cond.wait(&self.queue_mutex);
            }

            if (self.stop_flag) {
                for (self.pending_requests.items) |req| {
                    completeRequest(req, null, error.CurlRequestAborted);
                }
                self.pending_requests.clearRetainingCapacity();

                for (active_requests.items) |item| {
                    abortActiveRequest(self, item.easy, item.req);
                }
                active_requests.clearRetainingCapacity();

                self.queue_mutex.unlock();
                break;
            }

            for (self.pending_requests.items) |req| {
                const easy = c.curl_easy_init() orelse {
                    completeRequest(req, null, error.CurlEasyInitFailed);
                    continue;
                };

                configureEasyHandle(easy, req) catch |err| {
                    c.curl_easy_cleanup(easy);
                    completeRequest(req, null, err);
                    continue;
                };

                if (c.curl_multi_add_handle(self.multi, easy) != c.CURLM_OK) {
                    c.curl_easy_cleanup(easy);
                    completeRequest(req, null, error.CurlMultiAddFailed);
                    continue;
                }

                active_requests.append(self.allocator, .{ .easy = easy, .req = req }) catch |err| {
                    _ = c.curl_multi_remove_handle(self.multi, easy);
                    c.curl_easy_cleanup(easy);
                    completeRequest(req, null, err);
                };
            }
            self.pending_requests.clearRetainingCapacity();
            self.queue_mutex.unlock();

            if (active_requests.items.len == 0) continue;

            var still_running: c_int = 0;
            _ = c.curl_multi_perform(self.multi, &still_running);

            var numfds: c_int = 0;
            _ = c.curl_multi_poll(self.multi, null, 0, 100, &numfds);

            var msgs_in_queue: c_int = 0;
            while (c.curl_multi_info_read(self.multi, &msgs_in_queue)) |info| {
                if (info.msg != c.CURLMSG_DONE) continue;

                for (active_requests.items, 0..) |item, idx| {
                    if (item.easy != info.easy_handle) continue;

                    var status_code: c_long = 0;
                    const getinfo_res = c.curl_easy_getinfo(item.easy, c.CURLINFO_RESPONSE_CODE, &status_code);
                    const http_status: ?u32 = if (getinfo_res == c.CURLE_OK) @intCast(status_code) else null;

                    if (info.data.result == c.CURLE_OK) {
                        if (http_status) |code| {
                            completeRequest(item.req, code, if (code >= 400) error.HttpRequestFailed else null);
                        } else {
                            completeRequest(item.req, null, null);
                        }
                    } else {
                        completeRequest(item.req, http_status, error.CurlRequestFailed);
                    }

                    _ = c.curl_multi_remove_handle(self.multi, item.easy);
                    c.curl_easy_cleanup(item.easy);
                    _ = active_requests.swapRemove(idx);
                    break;
                }
            }
        }
    }
};

fn configureEasyHandle(easy: *c.CURL, req: *CurlRequest) !void {
    try ensureCurlCode(c.curl_easy_setopt(easy, c.CURLOPT_URL, req.url.ptr));
    try ensureCurlCode(c.curl_easy_setopt(easy, c.CURLOPT_WRITEFUNCTION, writeCallback));
    try ensureCurlCode(c.curl_easy_setopt(easy, c.CURLOPT_WRITEDATA, req));
    try ensureCurlCode(c.curl_easy_setopt(easy, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1)));
    try ensureCurlCode(c.curl_easy_setopt(easy, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1)));
    try ensureCurlCode(c.curl_easy_setopt(easy, c.CURLOPT_NOSIGNAL, @as(c_long, 1)));
}

fn ensureCurlCode(code: c.CURLcode) !void {
    if (code != c.CURLE_OK) {
        return error.CurlSetOptFailed;
    }
}

fn abortActiveRequest(self: *AsyncCurl, easy: *c.CURL, req: *CurlRequest) void {
    _ = c.curl_multi_remove_handle(self.multi, easy);
    c.curl_easy_cleanup(easy);
    completeRequest(req, null, error.CurlRequestAborted);
}

fn completeRequest(req: *CurlRequest, status_code: ?u32, err: ?anyerror) void {
    req.mutex.lock();
    defer req.mutex.unlock();

    if (req.done) return;

    req.status_code = status_code;
    if (req.err == null) {
        req.err = err;
    }
    req.done = true;
    req.cond.signal();
}

fn writeCallback(data: [*c]const u8, size: usize, nmemb: usize, userp: ?*anyopaque) callconv(.C) usize {
    const req_ptr = userp orelse return 0;
    const req: *CurlRequest = @ptrCast(@alignCast(req_ptr));
    const bytes = size * nmemb;

    req.response.appendSlice(req.allocator, data[0..bytes]) catch |err| {
        req.mutex.lock();
        if (req.err == null) {
            req.err = err;
        }
        req.mutex.unlock();
        return 0;
    };

    return bytes;
}
