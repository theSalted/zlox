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

    const constant = chunk.addConstant(1.2);
    chunk.write(Chunk.OpCode.op_constant, 123);
    chunk.write(constant, 123);

    chunk.write(Chunk.OpCode.op_return, 123);

    debug.disassembleChunk(&chunk, "test chunk");
}
