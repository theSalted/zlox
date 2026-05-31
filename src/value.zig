const std = @import("std");
const mem = @import("memory.zig");

const print = std.debug.print;

pub const Object = struct {
    type: ObjectType,
};

pub const Value = union(enum) {
    val_bool: bool,
    val_nil: void,
    val_number: f64,
    val_object: *Object,
};

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

pub fn valuesEqual(a: Value, b: Value) bool {
    return switch (a) {
        .val_bool => |av| b == .val_bool and av == b.val_bool,
        .val_nil => b == .val_nil,
        .val_number => |av| b == .val_number and av == b.val_number,
    };
}

pub fn printValue(value: Value) void {
    switch (value) {
        .val_bool => |b| print("{}", .{b}),
        .val_nil => print("nil", .{}),
        .val_number => |n| print("{d}", .{n}),
    }
}
