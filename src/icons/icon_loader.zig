const std = @import("std");
const IconCache = @import("icon_cache.zig").IconCache;
const icon_loading = @import("icon_loading.zig");
const c = @import("../c.zig").c;
const IconDiscovery = @import("icon_discovery.zig").IconDiscovery;
const constants = @import("../constants.zig");

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
    arena_parent: std.mem.Allocator,
    init_cache_len: usize = 0,

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
        self.arena_parent = arena_parent;
        self.event_fd = event_fd;

        self.initNameCache();

        self.thread = try std.Thread.spawn(.{}, IconLoader.runLoop, .{self});

        return self;
    }

    pub fn deinit(self: *IconLoader) void {
        self.queue_mutex.lock();
        self.stop_flag = true;
        self.queue_con.signal();
        self.queue_mutex.unlock();

        self.thread.join();
        self.saveNameCache();
        self.pending_request.deinit(self.allocator);
        self.arena.deinit();
        self.main_thread_arena.deinit();

        self.allocator.destroy(self);
    }

    fn initNameCache(self: *IconLoader) void {
        var loading_arena = std.heap.ArenaAllocator.init(self.arena_parent);
        defer loading_arena.deinit();
        const alloc = loading_arena.allocator();
        const path = self.getCachePath(alloc) catch return;

        const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch return;
        defer file.close();

        const content = file.readToEndAlloc(alloc, 1024 * 64) catch return;

        var line_iter = std.mem.splitScalar(u8, content, '\n');
        
        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, &.{'\r', ' ', '\t'});
            if (line.len == 0) continue;

            if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
                const key = line[0..eq];
                const value = line[eq + 1..];
                const owned_key = self.main_thread_arena.allocator().dupe(u8, key) catch continue;
                const owned_value = self.main_thread_arena.allocator().dupe(u8, value) catch continue;
                self.name_cache.put(owned_key, owned_value) catch continue;
                self.init_cache_len += 1;
            }
        }
    }

    fn getCachePath(self: *IconLoader, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        const config_base = std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => blk: {
                const home = try std.process.getEnvVarOwned(allocator, "HOME");
                break :blk try std.fs.path.join(allocator, &.{ home, ".cache" });
            },
            else => return err,
        };

        return try std.fs.path.join(allocator, &.{ config_base, constants.APP_NAME, "name-resolution.zc" });
    }

    fn saveNameCache(self: *IconLoader) void {
        var save_arena = std.heap.ArenaAllocator.init(self.arena_parent); 
        defer save_arena.deinit();
        const alloc = save_arena.allocator();
        const path = self.getCachePath(alloc) catch return;
        const dir_path = std.fs.path.dirname(path) orelse return;

        std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return,
        };

        var file = std.fs.cwd().createFile(path, .{
            .read = true,
            .truncate = true, 
        }) catch {
            std.debug.print("Failed creating name cache file", .{});
            return;
        };
        defer file.close();

        const end_pos = file.getEndPos() catch return;
        file.seekTo(end_pos) catch return;

        var iter = self.name_cache.keyIterator();

        var writer_buf: [1024]u8 = undefined;
        while (iter.next()) |key| {
            const value = self.name_cache.get(key.*) orelse continue;
            if (value) |v| {
                const format = std.fmt.bufPrint(&writer_buf, "{s}={s}\n", .{key.*, v}) catch continue;
                file.writeAll(format) catch return;
                writer_buf = undefined;
            }
        }

        file.sync() catch return;
        std.debug.print("Finished file sync for name resolution cache", .{});
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
        const owned_value: ?[]const u8 = if (value) |v|
            self.arena.allocator().dupe(u8, v) catch return
        else
            null;
        self.name_cache.put(owned_key, owned_value) catch {};
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
