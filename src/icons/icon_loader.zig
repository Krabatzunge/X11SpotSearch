const std = @import("std");
const IconCache = @import("icon_cache.zig").IconCache;
const icon_loading = @import("icon_loading.zig");
const c = @import("../c.zig").c;
const IconDiscovery = @import("icon_discovery.zig").IconDiscovery;

pub const IconRequest = struct {
   size: u16,
   source: union(enum) {
        path: []const u8,
        name: []const u8,
    },
   key: []const u8,

   pub fn clone(self: IconRequest, allocator: std.mem.Allocator) !IconRequest {
       const clone_sourced: @TypeOf(self.source) = switch (self.source) {
           .path => |p| .{ .path = try allocator.dupe(u8, p) },
           .name => |n| .{ .name = try allocator.dupe(u8, n) },
       };

       const cloned_key = try allocator.dupe(u8, self.key);

       return IconRequest {
            .source = clone_sourced,
            .size = self.size,
            .key = cloned_key,
       };
   }

    pub fn free(self: IconRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        switch (self.source) {
            .path => |p| allocator.free(p),
            .name => |n| allocator.free(n),
        }
    }
};

pub const IconLoader = struct {
    thread: std.Thread,
    queue_mutex: std.Thread.Mutex = .{},
    queue_con: std.Thread.Condition = .{},
    cache_mutex: std.Thread.Mutex = .{},
    name_cache_mutex: std.Thread.Mutex = .{},
    requsted_cache_mutex: std.Thread.Mutex = .{},
    icon_cache: *IconCache,
    icon_discovery: *IconDiscovery,
    pending_request: std.ArrayList(IconRequest),
    allocator: std.mem.Allocator,
    stop_flag: bool = false,
    event_fd: std.posix.fd_t,
    arena: std.heap.ArenaAllocator,
    main_thread_arena: std.heap.ArenaAllocator,
    name_cache: std.StringHashMap(?[]const u8),
    requested_cache: std.StringHashMap(bool),

    pub fn init(allocator: std.mem.Allocator, arena_parent: std.mem.Allocator, icon_cache: *IconCache, icon_discov: *IconDiscovery, event_fd: std.posix.fd_t) !*IconLoader {
        const self = try allocator.create(IconLoader);
        errdefer allocator.destroy(self);

        self.arena = std.heap.ArenaAllocator.init(arena_parent);
        self.main_thread_arena = std.heap.ArenaAllocator.init(arena_parent);
        self.name_cache = std.StringHashMap(?[]const u8).init(self.arena.allocator());
        self.requested_cache = std.StringHashMap(bool).init(self.main_thread_arena.allocator());

        self.thread = undefined;
        self.icon_cache = icon_cache;
        self.icon_discovery = icon_discov;
        self.pending_request = .empty;
        self.allocator = allocator;
        self.event_fd = event_fd;

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
        self.arena.deinit();
        self.main_thread_arena.deinit();

        self.allocator.destroy(self);
    }

    pub fn request(self: *IconLoader, req: IconRequest) void {
        self.requsted_cache_mutex.lock();
        defer self.requsted_cache_mutex.unlock();
        if (self.requested_cache.get(req.key) != null) return;

        const cache_key = self.main_thread_arena.allocator().dupe(u8, req.key) catch return;
        self.requested_cache.put(cache_key, true) catch return;

        const owned_request = req.clone(self.allocator) catch return;

        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        self.pending_request.append(self.allocator, owned_request) catch {
            owned_request.free(self.allocator);
            return;
        };
        self.queue_con.signal();
    }

    pub fn getCached(self: *IconLoader, key: []const u8) ?*c.cairo_surface_t {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        return self.icon_cache.get(key);
    }
    pub fn getNameCached(self: *IconLoader, key: []const u8) ??[]const u8 {
       self.name_cache_mutex.lock();
       defer self.name_cache_mutex.unlock();
       return self.name_cache.get(key);
    }

    fn setCache(self: *IconLoader, key: []const u8, surface: *c.cairo_surface_t) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        self.icon_cache.set(key, surface) catch {};
    }
    fn setNameCache(self: *IconLoader, key: []const u8, value: ?[]const u8) void {
        self.name_cache_mutex.lock();
        defer self.name_cache_mutex.unlock();
        const owned_key = self.arena.allocator().dupe(u8, key) catch return;
        self.name_cache.put(owned_key, value) catch {};
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
                    req.free(self.allocator);
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
                defer req.free(self.allocator);
                switch (req.source) {
                    .path => |p| {
                        const surface = icon_loading.loadIconFromPath(p, req.size) catch continue;
                        self.setCache(req.key, surface);
                    },
                    .name => |n| {
                        const resolved = self.icon_discovery.getIconFromPath(n) orelse {
                            self.setNameCache(req.key, null);
                            continue;
                        };
                        self.setNameCache(req.key, resolved);

                        const surface = icon_loading.loadIconFromPath(resolved, req.size) catch {
                            any_loaded = true;
                            continue;
                        };
                        self.setCache(req.key, surface);
                    },
                }
                any_loaded = true;
            }
            self.allocator.free(work);

            if (any_loaded) {
                self.notifyMainThread();
            }
        }
    }
};
