const std = @import("std");
const mem = @import("memory.zig");

const print = std.debug.print;

pub const Value = f64;

pub const ValueArray = struct {
    count: usize,
    capacity: usize,
    values: ?[*]Value,
    allocator: std.mem.Allocator,

    pub fn init(array: *ValueArray, allocator: std.mem.Allocator) void {
        array.values = null;
        array.count = 0;
        array.capacity = 0;
        array.allocator = allocator;
    }

    pub fn write(array: *ValueArray, value: Value) void {
        if (array.capacity < array.count + 1) {
            const old_capacity = array.capacity;
            array.capacity = mem.growCapacity(old_capacity);
            array.values = mem.growArray(Value, array.allocator, array.values, old_capacity, array.capacity);
        }

        array.values.?[array.count] = value;
        array.count += 1;
    }

    pub fn free(array: *ValueArray) void {
        mem.freeArray(Value, array.allocator, array.values, array.capacity);
        init(array, array.allocator);
    }
};

pub fn printValue(value: Value) void {
    print("{d}", .{value});
}
