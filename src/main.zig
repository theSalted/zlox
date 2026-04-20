const std = @import("std");
const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    var chunk: Chunk = undefined;
    chunk.init(allocator);
    defer chunk.free();

    chunk.write(Chunk.OpCode.op_return);

    debug.disassembleChunk(&chunk, "test chunk");
}
