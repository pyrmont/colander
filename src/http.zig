//! An HTTP client for Colander, adapted from Blueshift's transport and built
//! against Wattle's public module API.
//!
//! `colander_http/get` sends a GET request on a worker thread, so other
//! fibers keep running, and wakes the calling fiber with a map. It follows
//! redirects, decompresses gzip and deflate, and returns the response's
//! headers as well as its status and body.
//!
//! It has no timeout of its own, since `std.http.Client` has none:
//! `lib/http.wattle` gives each request a deadline with `ev/with-deadline`.
//! A request whose fiber is cancelled that way can still be waiting on the
//! network when the runtime shuts down and frees the job. So the request's
//! state is not part of the job, which the collector owns, but is allocated
//! apart from it, with an atomic status. The job's finalizer joins a worker
//! that has finished and detaches one that has not, leaving that worker to
//! free the state when its request ends.
const std = @import("std");
const wattle = @import("wattle");

const Header = struct { name: []const u8, value: []const u8 };

const Progress = enum(u8) { running, finished, abandoned };

/// A request and its result. The worker writes it; the loop thread reads it
/// in `done`, after the worker has finished.
const State = struct {
    arena: std.heap.ArenaAllocator,
    progress: std.atomic.Value(Progress) = .init(.running),
    loop: *wattle.Loop,
    url: []const u8 = "",
    headers: []std.http.Header = &.{},
    limit: usize,
    redirects: u16,
    status: u16 = 0,
    response_headers: []Header = &.{},
    final_url: []const u8 = "",
    response_body: []const u8 = "",
    failure: ?[]const u8 = null,

    fn destroy(state: *State) void {
        state.arena.deinit();
        std.heap.page_allocator.destroy(state);
    }
};

/// The handle the collector owns. It is rooted from the call until `done`.
const Job = struct {
    state: *State,
    thread: ?std.Thread,
    fiber: wattle.Value,
};

fn jobGc(job: *Job, _: usize) void {
    if (job.thread) |thread| {
        // Only a shutdown collects a job whose worker has not been joined in
        // `done`. A worker still waiting on the network is left to finish
        // and free the state itself.
        if (job.state.progress.cmpxchgStrong(.running, .abandoned, .acq_rel, .acquire) == null) {
            thread.detach();
            return;
        }
        thread.join();
    }
    job.state.destroy();
}

const job_type = wattle.define(Job, .{ .name = "colander_http/job", .gc = jobGc });

fn copy(arena: std.mem.Allocator, bytes: []const u8) wattle.Error![]const u8 {
    return arena.dupe(u8, bytes) catch wattle.panic("out of memory preparing HTTP request");
}

/// Returns the headers of head with lowercase names. The values of a name
/// given more than once are joined with ", ".
fn collectHeaders(arena: std.mem.Allocator, head: *const std.http.Client.Response.Head) ![]Header {
    var list: std.ArrayList(Header) = .empty;
    var it = head.iterateHeaders();
    outer: while (it.next()) |h| {
        const name = try std.ascii.allocLowerString(arena, h.name);
        for (list.items) |*existing| {
            if (std.mem.eql(u8, existing.name, name)) {
                existing.value = try std.mem.concat(arena, u8, &.{ existing.value, ", ", h.value });
                continue :outer;
            }
        }
        try list.append(arena, .{ .name = name, .value = try arena.dupe(u8, h.value) });
    }
    return list.toOwnedSlice(arena);
}

fn fetch(state: *State, client: *std.http.Client) !void {
    const arena = state.arena.allocator();
    const uri = try std.Uri.parse(state.url);
    var req = try client.request(.GET, uri, .{
        .redirect_behavior = .init(state.redirects),
        .keep_alive = false,
        .headers = .{ .user_agent = .omit },
        .extra_headers = state.headers,
    });
    defer req.deinit();
    try req.sendBodiless();

    const redirect_buffer = try arena.alloc(u8, 8 * 1024);
    var response = try req.receiveHead(redirect_buffer);
    state.status = @intFromEnum(response.head.status);
    state.response_headers = try collectHeaders(arena, &response.head);
    state.final_url = try std.fmt.allocPrint(arena, "{f}", .{req.uri});

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try arena.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try arena.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
    state.response_body = reader.allocRemaining(arena, .limited(state.limit)) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };
}

/// Runs the request. `job` is only passed on to `done`: once the job is
/// abandoned it may have been freed.
fn worker(job: *Job, state: *State) void {
    {
        var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        var client: std.http.Client = .{
            .allocator = std.heap.page_allocator,
            .io = threaded.io(),
        };
        defer client.deinit();

        fetch(state, &client) catch |err| {
            state.failure = switch (err) {
                error.StreamTooLong => "response body too large",
                error.TooManyHttpRedirects => "too many redirects",
                else => @errorName(err),
            };
        };
    }
    if (state.progress.cmpxchgStrong(.running, .finished, .acq_rel, .acquire) == null) {
        wattle.post(state.loop, &done, job);
    } else {
        state.destroy();
    }
}

fn done(wake: *wattle.Wake, raw: *anyopaque) callconv(.c) void {
    const job: *Job = @ptrCast(@alignCast(raw));
    job.thread.?.join();
    job.thread = null;
    const state = job.state;

    const result = if (state.failure) |message|
        wattle.mapOf(&.{.{ .key = wattle.keyword("error"), .value = wattle.string(message) }})
    else result: {
        // The callback cannot raise, and the collector's own allocations are
        // fatal on failure too.
        const pairs = state.arena.allocator().alloc(wattle.Keyval, state.response_headers.len) catch
            @panic("out of memory reading HTTP headers");
        for (state.response_headers, 0..) |h, i| {
            pairs[i] = .{ .key = wattle.string(h.name), .value = wattle.string(h.value) };
        }
        break :result wattle.mapOf(&.{
            .{ .key = wattle.keyword("status"), .value = wattle.number(@floatFromInt(state.status)) },
            .{ .key = wattle.keyword("headers"), .value = wattle.mapOf(pairs) },
            .{ .key = wattle.keyword("url"), .value = wattle.string(state.final_url) },
            .{ .key = wattle.keyword("body"), .value = wattle.string(state.response_body) },
        });
    };
    // A false wake means the fiber was cancelled, by its deadline, say.
    _ = wattle.wake(wake, job.fiber, result);
    _ = wattle.gcunroot(job.fiber);
    _ = wattle.gcunroot(wattle.abstract(job));
}

fn get(argv: []wattle.Value) wattle.Error!wattle.Value {
    try wattle.fixarity(argv, 4);
    const url = try wattle.getBytes(argv, 0);
    const limit = try wattle.getSize(argv, 2);
    const redirects = try wattle.getSize(argv, 3);
    if (redirects >= std.math.maxInt(u16))
        return wattle.panic("too many redirects allowed");
    var headers = try wattle.getDictionary(argv, 1);
    const loop = try wattle.loop();
    const fiber = try wattle.rootFiber();

    const state = std.heap.page_allocator.create(State) catch
        return wattle.panic("out of memory preparing HTTP request");
    state.* = .{
        .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        .loop = loop,
        .limit = limit,
        .redirects = @intCast(redirects),
    };
    // Until the job exists, a failure here frees the state; after it, the
    // job's finalizer does.
    var owned = false;
    errdefer if (!owned) state.destroy();
    const allocator = state.arena.allocator();
    state.url = try copy(allocator, url);

    state.headers = allocator.alloc(std.http.Header, headers.count) catch
        return wattle.panic("out of memory preparing HTTP headers");
    var i: usize = 0;
    while (try headers.next()) |kv| : (i += 1) {
        const name = wattle.bytesView(kv.key) orelse
            return wattle.panic("HTTP header names must be strings");
        const value = wattle.bytesView(kv.value) orelse
            return wattle.panic("HTTP header values must be strings");
        if (name.len == 0 or std.mem.findAny(u8, name, ":\r\n") != null or
            std.mem.findAny(u8, value, "\r\n") != null)
            return wattle.panic("HTTP header names and values cannot hold line breaks or ':'");
        state.headers[i] = .{
            .name = try copy(allocator, name),
            .value = try copy(allocator, value),
        };
    }

    const job = wattle.new(Job, &job_type, null);
    job.* = .{ .state = state, .thread = null, .fiber = fiber };
    owned = true;
    wattle.gcroot(job.fiber);
    wattle.gcroot(wattle.abstract(job));
    job.thread = std.Thread.spawn(.{}, worker, .{ job, state }) catch {
        _ = wattle.gcunroot(job.fiber);
        _ = wattle.gcunroot(wattle.abstract(job));
        return wattle.panic("could not start HTTP worker thread");
    };
    return wattle.await();
}

fn defs(env: *wattle.Env) wattle.Error!void {
    wattle.nfuns(env, "colander_http", &.{
        wattle.reg("get", &get, "(colander_http/get url headers limit redirects)",
            \\Sends a GET request for url with the request headers (a map of
            \\strings), following up to redirects redirects and reading at most
            \\limit bytes of body. Returns a map with :status, :headers (lowercase
            \\names to values), :url (after redirects) and :body, or with :error.
        ),
    });
}

comptime {
    wattle.entry(defs);
}
