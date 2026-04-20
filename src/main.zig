const std = @import("std");
const Chunk = @import("Chunk.zig");

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    var chunk: Chunk = undefined;
    Chunk.initChunk(&chunk, allocator);
}
