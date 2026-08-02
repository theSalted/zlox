const std = @import("std");
const memory = @import("memory.zig");

const print = std.debug.print;

const Value = @import("value.zig").Value;
const VM = @import("VM.zig").VM;
const Chunk = @import("Chunk.zig");

pub const ObjectType = enum(u8) { string, native, function };

pub const Object = extern struct {
    type: ObjectType,
    next: ?*Object,
};

pub const ObjectFunction = struct {
    obj: Object,
    arity: usize,
    chunk: Chunk,
    name: ?*ObjectString,
};

pub const NativeFn = *const fn (vm: *VM, arg_count: u8, args: [*]Value) Value;

pub const ObjectNative = struct {
    obj: Object,
    function: NativeFn,
};

pub const ObjectString = extern struct {
    obj: Object,
    len: usize,
    chars: [*]const u8,
    hash: u32,
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

pub fn newFunction(vm: *VM) *ObjectFunction {
    const function = allocateObject(vm, ObjectFunction, .function);
    function.arity = 0;
    function.name = null;
    function.chunk.init(vm.allocator);
    return function;
}

pub fn newNative(vm: *VM, function: NativeFn) *ObjectNative {
    const native = allocateObject(vm, ObjectNative, .native);
    native.function = function;
    return native;
}

fn allocateString(vm: *VM, chars: [*]const u8, len: usize, hash: u32) *ObjectString {
    const string = allocateObject(vm, ObjectString, .string);
    string.len = len;
    string.chars = chars;
    string.hash = hash;
    _ = vm.strings.set(string, .val_nil);
    return string;
}

pub fn copyString(vm: *VM, chars: [*]const u8, length: usize) *ObjectString {
    const hash = hashString(chars, length);
    if (vm.strings.findString(chars, length, hash)) |interned| return interned;

    const heap = memory.allocate(vm.allocator, u8, length);
    @memcpy(heap, chars[0..length]);
    return allocateString(vm, heap.ptr, length, hash);
}

pub fn takeString(vm: *VM, chars: [*]const u8, length: usize) *ObjectString {
    const hash = hashString(chars, length);
    if (vm.strings.findString(chars, length, hash)) |interned| {
        memory.freeArray(u8, vm.allocator, chars, length);
        return interned;
    }

    return allocateString(vm, chars, length, hash);
}

fn hashString(key: [*]const u8, length: usize) u32 {
    var hash: u32 = 2166136261;
    for (key[0..length]) |byte| {
        hash ^= byte;
        hash *%= 16777619;
    }
    return hash;
}

pub fn printObject(obj: *Object) void {
    switch (obj.type) {
        .string => {
            const string: *ObjectString = @ptrCast(@alignCast(obj));
            print("{s}", .{string.chars[0..string.len]});
        },
        .native => {
            print("<native fn>", .{});
        },
        .function => {
            const function: *ObjectFunction = @ptrCast(@alignCast(obj));
            if (function.name == null) {
                print("<script>", .{});
                return;
            }
            print("<fn {s}>", .{function.name.?.chars[0..function.name.?.len]});
        },
    }
}

pub inline fn isObjType(value: Value, object_type: ObjectType) bool {
    return value == .val_object and value.val_object.type == object_type;
}

pub inline fn asFunction(obj: *Object) *ObjectFunction {
    return @ptrCast(@alignCast(obj));
}

pub inline fn asNative(obj: *Object) *ObjectNative {
    return @ptrCast(@alignCast(obj));
}
