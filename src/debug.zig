const std = @import("std");
const Chunk = @import("Chunk.zig");

const val = @import("value.zig");

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

    if (offset > 0 and chunk.lines.?[offset] == chunk.lines.?[offset - 1]) {
        print("   | ", .{});
    } else {
        print("{d:>4} ", .{chunk.lines.?[offset]});
    }

    const instruction = chunk.code.?[offset];
    const op: Chunk.OpCode = @enumFromInt(instruction);

    switch (op) {
        .op_constant => return constantInstruction("OP_CONSTANT", chunk, offset),
        .op_return => return simpleInstruction("OP_RETURN", offset),
    }
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    print("{s}\n", .{name});

    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const constant = chunk.code.?[offset + 1];
    print("{s:<16} {d:>4} '", .{ name, constant });

    val.printValue(chunk.constants.values.?[constant]);

    print("'\n", .{});

    return offset + 2;
}
