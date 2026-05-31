const std = @import("std");
const memory = @import("memory.zig");

const print = std.debug.print;

const Value = @import("value.zig").Value;
const Object = @import("value.zig").Object;
const ObjectType = @import("value.zig").ObjectType;

pub const ObjectString = struct {
    obj: Object,
    len: usize,
    chars: []const u8,
};

pub inline fn isString(value: Value) bool {
    return isObjType(value, .string);
}

pub inline fn asString(value: Value) *ObjectString {
    return @fieldParentPtr("obj", value.val_object);
}

pub inline fn asCString(value: Value) []const u8 {
    return asString(value).chars;
}

fn allocateString(allocator: std.mem.Allocator, chars: []const u8, len: usize) *ObjectString {
    const string = allocator.create(ObjectString) catch @panic("out of memory");
    string.obj = .{ .type = .string };
    string.len = len;
    string.chars = chars;
    return string;
}

pub fn copyString(allocator: std.mem.Allocator, chars: [*]const u8, length: usize) *ObjectString {
    const heap = memory.allocate(allocator, u8, length);
    @memcpy(heap, chars[0..length]);
    return allocateString(allocator, heap, length);
}

pub fn takeString(allocator: std.mem.Allocator, chars: []const u8, length: usize) *ObjectString {
    return allocateString(allocator, chars, length);
}

pub fn printObject(obj: *Object) void {
    switch (obj.type) {
        .string => {
            const string: *ObjectString = @fieldParentPtr("obj", obj);
            print("{s}", .{string.chars});
        },
    }
}

pub inline fn isObjType(value: Value, object_type: ObjectType) bool {
    return value == .val_object and value.val_object.type == object_type;
}
