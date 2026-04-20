const std = @import("std");
const Chunk = @import("Chunk.zig");
const print = std.debug.print;

pub fn disassembleChunk(chunk: *const Chunk, name: []const u8) void {
    print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    print("{d:0>4} ", .{offset});

    const instruction = chunk.code.?[offset];
    const op: Chunk.OpCode = @enumFromInt(instruction);

    switch (op) {
        .op_return => return simpleInstruction("OP_RETURN", offset),
    }
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    print("{s}\n", .{name});

    return offset + 1;
}
