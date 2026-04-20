const std = @import("std");
const IconCache = @import("icon_cache.zig").IconCache;
const icon_loading = @import("icon_loading.zig");
const c = @import("../c.zig").c;

pub const IconRequest = struct {
   path: []const u8, 
   size: u16,
   key: []const u8,
};

pub const IconLoader = struct {
    thread: std.Thread,
    queue_mutex: std.Thread.Mutex = .{},
    queue_con: std.Thread.Condition = .{},
    cache_mutex: std.Thread.Mutex = .{},
    icon_cache: *IconCache,
    pending_request: std.ArrayList(IconRequest),
    allocator: std.mem.Allocator,
    stop_flag: bool = false,
    event_fd: std.posix.fd_t,

    pub fn init(allocator: std.mem.Allocator, icon_cache: *IconCache, event_fd: std.posix.fd_t) !*IconLoader {
        const self = try allocator.create(IconLoader);
        errdefer allocator.destroy(self);

        self.* = .{
            .thread = undefined,
            .icon_cache = icon_cache,
            .pending_request = .empty,
            .allocator = allocator,
            .event_fd = event_fd,
        }; 

        self.thread = try std.Thread.spawn(.{}, IconLoader.runLoop, .{self});
        return self;
    }

    pub fn deinit(self: *IconLoader) void {
        self.queue_mutex.lock();
        self.stop_flag = true;
        self.queue_con.signal();
        self.queue_mutex.unlock();

        self.thread.join();
        self.pending_request.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    pub fn request(self: *IconLoader, req: IconRequest) void {
        const owned_path = self.allocator.dupe(u8, req.path) catch return;
        const owned_key = self.allocator.dupe(u8, req.key) catch {
            self.allocator.free(owned_path);
            return;
        };

        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        self.pending_request.append(self.allocator, .{
            .path = owned_path,
            .size = req.size,
            .key = owned_key,
        }) catch {
            self.allocator.free(owned_path);
            self.allocator.free(owned_key);
            return;
        };
        self.queue_con.signal();
    }

    pub fn getCached(self: *IconLoader, key: []const u8) ?*c.cairo_surface_t {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        return self.icon_cache.get(key);
    }

    fn setCache(self: *IconLoader, key: []const u8, surface: *c.cairo_surface_t) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        self.icon_cache.set(key, surface) catch {};
    }

    fn notifyMainThread(self: *IconLoader) void {
        const val: u64 = 1;
        _ = std.posix.write(self.event_fd, std.mem.asBytes(&val)) catch {};
    }

    fn runLoop(self: *IconLoader) void {
        while (true) {
            self.queue_mutex.lock();

            while (!self.stop_flag and self.pending_request.items.len == 0) {
                self.queue_con.wait(&self.queue_mutex);
            }

            if (self.stop_flag) {
                for (self.pending_request.items) |req| {
                    self.allocator.free(req.path);
                    self.allocator.free(req.key);
                }
                self.pending_request.clearRetainingCapacity();
                self.queue_mutex.unlock();
                break;
            }

            const work = self.pending_request.toOwnedSlice(self.allocator) catch {
                self.queue_mutex.unlock();
                continue;
            };
            self.queue_mutex.unlock();

            var any_loaded = false;
            for (work) |req| {
                defer self.allocator.free(req.path);
                defer self.allocator.free(req.key);
                const surface = icon_loading.loadIconFromPath(req.path, req.size) catch continue;
                self.setCache(req.key, surface);
                any_loaded = true;
            }
            self.allocator.free(work);

            if (any_loaded) {
                self.notifyMainThread();
            }
        }
    }
};
