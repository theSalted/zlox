const std = @import("std");
const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    var chunk: Chunk = undefined;
    chunk.initChunk(allocator);
    defer _ = chunk.freeChunk();

    chunk.writeChunk(Chunk.OpCode.op_return);

    debug.disassembleChunk(&chunk, "test chunk");
}
