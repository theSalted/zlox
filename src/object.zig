const Value = @import("value.zig").Value;
const Object = @import("value.zig").Object;

const ObjectType = enum {
    STRING,
};

const ObjectString = struct {
    obj: Object,
    len: usize,
    chars: []const u8,
};

pub inline fn isObjType(value: Value, object_type: ObjectType) bool {
    return value == .val_object and value.val_object.type == object_type;
}
