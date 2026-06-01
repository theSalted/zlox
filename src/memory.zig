const std = @import("std");
const object = @import("object.zig");

const VM = @import("VM.zig").VM;
const Object = object.Object;
const ObjectString = object.ObjectString;

pub fn growCapacity(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * 2;
}

pub fn growArray(comptime T: type, allocator: std.mem.Allocator, ptr: ?[*]T, old: usize, new: usize) [*]T {
    if (ptr) |p| {
        const new_slice = allocator.realloc(p[0..old], new) catch @panic("out of memory");
        return new_slice.ptr;
    }

    const new_slice = allocator.alloc(T, new) catch @panic("out of memory");
    return new_slice.ptr;
}

pub fn freeArray(comptime T: type, allocator: std.mem.Allocator, ptr: ?[*]const T, count: usize) void {
    if (ptr) |p| allocator.free(p[0..count]);
}

pub fn freeObject(vm: *VM, obj: *Object) void {
    switch (obj.type) {
        .string => {
            const string: *ObjectString = @ptrCast(@alignCast(obj));
            freeArray(u8, vm.allocator, string.chars, string.len);
            vm.allocator.destroy(string);
        },
    }
}

pub fn freeObjects(vm: *VM) void {
    var current = vm.objects;
    while (current) |o| {
        const next = o.next;
        freeObject(vm, o);
        current = next;
    }
}

pub fn allocate(allocator: std.mem.Allocator, comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("out of memory");
}
