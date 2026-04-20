const std = @import("std");
const Chunk = @This();

pub const OpCode = enum(u8) {
    op_return,
};

count: usize,
capacity: usize,
code: ?[*]u8,

allocator: std.mem.Allocator,

pub fn initChunk(chunk: *Chunk, allocator: std.mem.Allocator) void {
    chunk.count = 0;
    chunk.capacity = 0;
    chunk.code = null;

    chunk.allocator = allocator;
}

pub fn writeChunk(chunk: *Chunk, byte: u8) void {
    if (chunk.capacity < chunk.count + 1) {
        const old_capacity = chunk.capacity;
        chunk.capacity = growCapacity(old_capacity);
        chunk.code = growArray(u8, chunk.allocator, chunk.code, old_capacity, chunk.capacity);
    }

    chunk.code.?[chunk.count] = byte;
    chunk.count += 1;
}

pub fn freeChunk(chunk: *Chunk) void {
    freeArray(u8, chunk.allocator, chunk.code, chunk.capacity);
    initChunk(chunk, chunk.allocator);
}

fn growCapacity(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * 2;
}

fn growArray(comptime T: type, allocator: std.mem.Allocator, ptr: ?[*]T, old: usize, new: usize) [*]T {
    if (ptr) |p| {
        const new_slice = allocator.realloc(p[0..old], new) catch @panic("out of memory");
        return new_slice.ptr;
    }

    const new_slice = allocator.alloc(T, new) catch @panic("out of memory");
    return new_slice.ptr;
}

fn freeArray(comptime T: type, allocator: std.mem.Allocator, ptr: ?[*]T, count: usize) void {
    if (ptr) |p| allocator.free(p[0..count]);
}
