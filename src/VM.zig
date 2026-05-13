const std = @import("std");
const val = @import("value.zig");
const debug = @import("debug.zig");
const common = @import("common.zig");

const Value = val.Value;
const Chunk = @import("Chunk.zig");

const print = std.debug.print;

const VM = @This();

const InterpretResult = enum(u8) { interpret_ok, interpret_compile_error, interpret_runtime_error };

// Chunk

chunk: *Chunk,
ip: [*]u8,

pub fn init(vm: *VM) void {
    _ = vm;
}

pub fn free(vm: *VM) void {
    _ = vm;
}

pub fn run(vm: *VM) InterpretResult {
    while (true) {
        const instruction = vm.readBytes();
        const op: Chunk.OpCode = @enumFromInt(instruction);
        switch (op) {
            .op_constant => {
                const constant: Value = readConstant(vm);
                val.printValue(constant);
                print("\n", .{});
                if (common.debug_trace_execution) {
                    _ = debug.disassembleInstruction(vm.chunk, vm.ip - vm.chunk.code.?);
                }
            },
            .op_return => return .interpret_ok,
        }
    }
}

pub fn interpret(vm: *VM, chunk: *Chunk) InterpretResult {
    vm.chunk = chunk;
    vm.ip = vm.chunk.code.?;
    return vm.run();
}

fn readBytes(vm: *VM) u8 {
    const b = vm.ip[0];
    vm.ip += 1;
    return b;
}

fn readConstant(vm: *VM) Value {
    return vm.chunk.constants.values.?[readBytes(vm)];
}
