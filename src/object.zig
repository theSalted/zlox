const std = @import("std");
const memory = @import("memory.zig");

const print = std.debug.print;

const Value = @import("value.zig").Value;
const VM = @import("VM.zig").VM;

pub const ObjectType = enum(u8) {
    string,
};

pub const Object = extern struct {
    type: ObjectType,
    next: ?*Object,
};

pub const ObjectString = extern struct {
    obj: Object,
    len: usize,
    chars: [*]const u8,
};

pub inline fn isString(value: Value) bool {
    return isObjType(value, .string);
}

pub inline fn asString(value: Value) *ObjectString {
    return @ptrCast(@alignCast(value.val_object));
}

pub inline fn asCString(value: Value) [*]const u8 {
    return asString(value).chars;
}

fn allocateObject(vm: *VM, comptime T: type, object_type: ObjectType) *T {
    const ptr = vm.allocator.create(T) catch @panic("out of memory");
    ptr.obj = .{ .type = object_type, .next = vm.objects };
    vm.objects = &ptr.obj;
    return ptr;
}

fn allocateString(vm: *VM, chars: [*]const u8, len: usize) *ObjectString {
    const string = allocateObject(vm, ObjectString, .string);
    string.len = len;
    string.chars = chars;
    return string;
}

pub fn copyString(vm: *VM, chars: [*]const u8, length: usize) *ObjectString {
    const heap = memory.allocate(vm.allocator, u8, length);
    @memcpy(heap, chars[0..length]);
    return allocateString(vm, heap.ptr, length);
}

pub fn takeString(vm: *VM, chars: [*]const u8, length: usize) *ObjectString {
    return allocateString(vm, chars, length);
}

pub fn printObject(obj: *Object) void {
    switch (obj.type) {
        .string => {
            const string: *ObjectString = @ptrCast(@alignCast(obj));
            print("{s}", .{string.chars[0..string.len]});
        },
    }
}

pub inline fn isObjType(value: Value, object_type: ObjectType) bool {
    return value == .val_object and value.val_object.type == object_type;
}
