const std = @import("std");
const val = @import("value.zig");
const debug = @import("debug.zig");
const common = @import("common.zig");
const compiler = @import("compiler.zig");
const object = @import("object.zig");
const memory = @import("memory.zig");

const Value = val.Value;
const Chunk = @import("Chunk.zig");
const Table = @import("Table.zig").Table;
const ObjectFunction = object.ObjectFunction;

const print = std.debug.print;

pub const VM = @This();

pub const InterpretResult = enum(u8) { interpret_ok, interpret_compile_error, interpret_runtime_error };

const frames_max: usize = 64;
const stack_max: usize = frames_max * 256;

const CallFrame = struct {
    function: *ObjectFunction,
    ip: [*]u8,
    slots: [*]Value,

    fn readByte(frame: *CallFrame) u8 {
        const b = frame.ip[0];
        frame.ip += 1;
        return b;
    }

    fn readShort(frame: *CallFrame) usize {
        frame.ip += 2;
        const hi: u16 = (frame.ip - 2)[0];
        const lo: u16 = (frame.ip - 1)[0];
        return (hi << 8) | lo;
    }

    fn readConstant(frame: *CallFrame) Value {
        return frame.function.chunk.constants.values.?[frame.readByte()];
    }

    fn readString(frame: *CallFrame) *object.ObjectString {
        return object.asString(frame.readConstant());
    }
};

frames: [frames_max]CallFrame,
frame_count: usize,
stack: [stack_max]Value,
stack_top: [*]Value,
globals: Table,
strings: Table,
objects: ?*object.Object,
allocator: std.mem.Allocator,

pub fn init(vm: *VM, allocator: std.mem.Allocator) void {
    vm.allocator = allocator;
    vm.objects = null;
    vm.resetStack();
    vm.globals.init(allocator);
    vm.strings.init(allocator);
}

pub fn free(vm: *VM) void {
    memory.freeObjects(vm);
    vm.globals.free();
    vm.strings.free();
}

pub fn push(vm: *VM, value: Value) void {
    vm.stack_top[0] = value;
    vm.stack_top += 1;
}

pub fn pop(vm: *VM) Value {
    vm.stack_top -= 1;
    return vm.stack_top[0];
}

pub fn peek(vm: *VM, distance: usize) Value {
    return (vm.stack_top - 1 - distance)[0];
}

pub fn call(vm: *VM, function: *ObjectFunction, arg_count: u8) bool {
    if (arg_count != function.arity) {
        vm.runtimeError("Expected {d} arguments but got {d}.", .{ function.arity, arg_count });
        return false;
    }

    if (vm.frame_count == frames_max) {
        vm.runtimeError("Stack overflow", .{});
        return false;
    }

    vm.frame_count += 1;
    var frame = vm.frames[vm.frame_count];
    frame.function = function;
    frame.ip = function.chunk.code.?;
    frame.slots = vm.stack_top - arg_count - 1;
    return true;
}

pub fn callValue(vm: *VM, callee: Value, arg_count: u8) bool {
    switch (callee) {
        .val_object => |obj| {
            switch (obj.type) {
                .function => return vm.call(object.asFunction(obj), arg_count),
                else => {},
            }
        },
        else => {},
    }
    vm.runtimeError("Can only call functions and classes.", .{});
    return false;
}

pub fn isFalsy(value: Value) bool {
    return switch (value) {
        .val_nil => true,
        .val_bool => |b| !b,
        .val_number => false,
        .val_object => false,
    };
}

pub fn run(vm: *VM) InterpretResult {
    var frame = &vm.frames[vm.frame_count - 1];
    while (true) {
        if (common.debug_trace_execution) {
            print("          ", .{});
            var slot: [*]Value = &vm.stack;
            while (slot != vm.stack_top) : (slot += 1) {
                print("[ ", .{});
                val.printValue(slot[0]);
                print(" ]", .{});
            }
            print("\n", .{});
            _ = debug.disassembleInstruction(&frame.function.chunk, @intFromPtr(frame.ip) - @intFromPtr(frame.function.chunk.code.?));
        }

        const instruction = frame.readByte();
        const op: Chunk.OpCode = @enumFromInt(instruction);
        switch (op) {
            .constant => {
                const constant: Value = frame.readConstant();
                vm.push(constant);
            },
            .nil => vm.push(.{ .val_nil = {} }),
            .true => vm.push(.{ .val_bool = true }),
            .false => vm.push(.{ .val_bool = false }),
            .pop => _ = vm.pop(),
            .get_local => {
                const slot = frame.readByte();
                vm.push(frame.slots[slot]);
            },
            .set_local => {
                const slot = frame.readByte();
                frame.slots[slot] = vm.peek(0);
            },
            .get_global => {
                const name = frame.readString();
                var value: Value = undefined;

                if (!vm.globals.get(name, &value)) {
                    vm.runtimeError("Undefined variable '{s}'", .{name.chars[0..name.len]});
                    return .interpret_runtime_error;
                }

                vm.push(value);
            },
            .set_global => {
                const name = frame.readString();
                if (vm.globals.set(name, vm.peek(0))) {
                    _ = vm.globals.delete(name);
                    vm.runtimeError("Undefined variable '{s}'", .{name.chars[0..name.len]});
                    return .interpret_runtime_error;
                }
            },
            .define_global => {
                const name = frame.readString();
                _ = vm.globals.set(name, vm.peek(0));
                _ = vm.pop();
            },
            .equal => {
                const b = vm.pop();
                const a = vm.pop();
                vm.push(.{ .val_bool = val.valuesEqual(a, b) });
            },
            .greater => {
                if (vm.peek(0) != .val_number or vm.peek(1) != .val_number) {
                    vm.runtimeError("Operands must be numbers.", .{});
                    return .interpret_runtime_error;
                }
                const b = vm.pop().val_number;
                const a = vm.pop().val_number;
                vm.push(.{ .val_bool = a > b });
            },
            .less => {
                if (vm.peek(0) != .val_number or vm.peek(1) != .val_number) {
                    vm.runtimeError("Operands must be numbers.", .{});
                    return .interpret_runtime_error;
                }
                const b = vm.pop().val_number;
                const a = vm.pop().val_number;
                vm.push(.{ .val_bool = a < b });
            },
            .add => {
                if (object.isString(vm.peek(0)) and object.isString(vm.peek(1))) {
                    concatenate(vm);
                } else if (vm.peek(0) == .val_number and vm.peek(1) == .val_number) {
                    const b = vm.pop().val_number;
                    const a = vm.pop().val_number;
                    vm.push(.{ .val_number = a + b });
                } else {
                    vm.runtimeError("Operands must be two numbers or two strings.", .{});
                    return .interpret_runtime_error;
                }
            },
            .subtract => {
                const r = vm.binaryOp('-');
                if (r != .interpret_ok) return r;
            },
            .multiply => {
                const r = vm.binaryOp('*');
                if (r != .interpret_ok) return r;
            },
            .divide => {
                const r = vm.binaryOp('/');
                if (r != .interpret_ok) return r;
            },
            .not => {
                vm.push(.{ .val_bool = isFalsy(vm.pop()) });
            },
            .negate => {
                if (vm.peek(0) != .val_number) {
                    vm.runtimeError("Operand must be a number.", .{});
                    return .interpret_runtime_error;
                }
                vm.push(.{ .val_number = -vm.pop().val_number });
            },
            .print => {
                val.printValue(vm.pop());
                print("\n", .{});
            },
            .jump => {
                const offset = frame.readShort();
                frame.ip += offset;
            },
            .jump_if_false => {
                const offset = frame.readShort();
                if (isFalsy(vm.peek(0))) frame.ip += offset;
            },
            .loop => {
                const offset = frame.readShort();
                frame.ip -= offset;
            },
            .call => {
                const arg_count = frame.readByte();
                if (!vm.callValue(vm.peek(arg_count), arg_count)) {
                    return .interpret_runtime_error;
                }
                frame = &vm.frames[vm.frame_count - 1];
            },
            .@"return" => {
                return .interpret_ok;
            },
        }
    }
}

pub fn interpret(vm: *VM, source: []const u8) InterpretResult {
    const function = compiler.compile(vm, source) orelse return .interpret_compile_error;
    vm.push(.{ .val_object = &function.obj });
    _ = vm.call(function, 0);
    return vm.run();
}

fn binaryOp(vm: *VM, comptime op: u8) InterpretResult {
    if (vm.peek(0) != .val_number or vm.peek(1) != .val_number) {
        vm.runtimeError("Operands must be numbers.", .{});
        return .interpret_runtime_error;
    }

    const b = vm.pop().val_number;
    const a = vm.pop().val_number;

    vm.push(.{ .val_number = switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a / b,
        else => @compileError("binaryOp: unknown op"),
    } });

    return .interpret_ok;
}

fn resetStack(vm: *VM) void {
    vm.stack_top = &vm.stack;
    vm.frame_count = 0;
}

fn runtimeError(vm: *VM, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);

    const frame = &vm.frames[vm.frame_count];
    vm.frame_count -= 1;
    const instruction = @intFromPtr(frame.ip) - @intFromPtr(frame.function.chunk.code.?) - 1;
    const line = frame.function.chunk.lines.?[instruction];
    std.debug.print("[line {d}] in script\n", .{line});

    vm.resetStack();
}

fn concatenate(vm: *VM) void {
    const b = object.asString(vm.pop());
    const a = object.asString(vm.pop());

    const length = a.len + b.len;
    const chars = memory.allocate(vm.allocator, u8, length);
    @memcpy(chars[0..a.len], a.chars[0..a.len]);
    @memcpy(chars[a.len .. a.len + b.len], b.chars[0..b.len]);

    const result = object.takeString(vm, chars.ptr, length);
    vm.push(.{ .val_object = &result.obj });
}
