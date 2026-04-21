const std = @import("std");
const mem = @import("memory.zig");
const val = @import("value.zig");

const ValueArray = val.ValueArray;
const Value = val.Value;

const Chunk = @This();

pub const OpCode = enum(u8) {
    op_constant,
    op_return,
};

// Chunk

count: usize,
capacity: usize,
code: ?[*]u8,
constants: ValueArray,
lines: ?[*]u32,

allocator: std.mem.Allocator,

pub fn init(chunk: *Chunk, allocator: std.mem.Allocator) void {
    chunk.count = 0;
    chunk.capacity = 0;
    chunk.code = null;
    chunk.lines = null;

    chunk.allocator = allocator;

    chunk.constants.init(allocator);
}

/// `value` accepts either `OpCode` or `u8`
pub fn write(chunk: *Chunk, value: anytype, line: u32) void {
    const byte: u8 = switch (@TypeOf(value)) {
        OpCode => @intFromEnum(value),
        u8 => value,
        else => @compileError("write: expected OpCode or u8"),
    };

    if (chunk.capacity < chunk.count + 1) {
        const old_capacity = chunk.capacity;
        chunk.capacity = mem.growCapacity(old_capacity);
        chunk.code = mem.growArray(u8, chunk.allocator, chunk.code, old_capacity, chunk.capacity);
        chunk.lines = mem.growArray(u32, chunk.allocator, chunk.lines, old_capacity, chunk.capacity);
    }

    chunk.code.?[chunk.count] = byte;
    chunk.lines.?[chunk.count] = line;
    chunk.count += 1;
}

pub fn free(chunk: *Chunk) void {
    mem.freeArray(u8, chunk.allocator, chunk.code, chunk.capacity);
    mem.freeArray(u32, chunk.allocator, chunk.lines, chunk.capacity);

    chunk.constants.free();

    init(chunk, chunk.allocator);
}

pub fn addConstant(chunk: *Chunk, value: Value) u8 {
    chunk.constants.write(value);
    return @intCast(chunk.constants.count - 1);
}
