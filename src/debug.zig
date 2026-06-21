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
        .constant => return constantInstruction("OP_CONSTANT", chunk, offset),
        .nil => return simpleInstruction("OP_NIL", offset),
        .@"true" => return simpleInstruction("OP_TRUE", offset),
        .@"false" => return simpleInstruction("OP_FALSE", offset),
        .pop => return simpleInstruction("OP_POP", offset),
        .define_global => return constantInstruction("OP_DEFINE_GLOBAL", chunk, offset),
        .get_local => return byteInstruction("OP_GET_LOCAL", chunk, offset),
        .set_local => return byteInstruction("OP_SET_LOCAL", chunk, offset),
        .get_global => return constantInstruction("OP_GET_GLOBAL", chunk, offset),
        .set_global => return constantInstruction("OP_SET_GLOBAL", chunk, offset),
        .equal => return simpleInstruction("OP_EQUAL", offset),
        .greater => return simpleInstruction("OP_GREATER", offset),
        .less => return simpleInstruction("OP_LESS", offset),
        .add => return simpleInstruction("OP_ADD", offset),
        .subtract => return simpleInstruction("OP_SUBTRACT", offset),
        .multiply => return simpleInstruction("OP_MULTIPLY", offset),
        .divide => return simpleInstruction("OP_DIVIDE", offset),
        .not => return simpleInstruction("OP_NOT", offset),
        .negate => return simpleInstruction("OP_NEGATE", offset),
        .print => return simpleInstruction("OP_PRINT", offset),
        .jump => return simpleInstruction("OP_JUMP", offset),
        .jump_if_false => return simpleInstruction("OP_JUMP_IF_FALSE", offset),
        .@"return" => return simpleInstruction("OP_RETURN", offset),
    }
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    print("{s}\n", .{name});

    return offset + 1;
}

fn byteInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const slot = chunk.code.?[offset + 1];
    print("{s:<16} {d:>4} ", .{ name, slot });
    return offset + 2;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const constant = chunk.code.?[offset + 1];
    print("{s:<16} {d:>4} '", .{ name, constant });

    val.printValue(chunk.constants.values.?[constant]);

    print("'\n", .{});

    return offset + 2;
}
