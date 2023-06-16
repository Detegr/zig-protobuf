const std = @import("std");
const protobuf = @import("protobuf");
const mem = std.mem;
const Allocator = mem.Allocator;
const eql = mem.eql;
const fd = protobuf.fd;
const pb_decode = protobuf.pb_decode;
const pb_encode = protobuf.pb_encode;
const pb_deinit = protobuf.pb_deinit;
const pb_init = protobuf.pb_init;
const testing = std.testing;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const FieldType = protobuf.FieldType;
const tests = @import("./generated/tests.pb.zig");

pub fn printAllDecoded(input: []const u8) !void {
    var iterator = protobuf.WireDecoderIterator{ .input = input };
    std.debug.print("Decoding: {s}\n", .{std.fmt.fmtSliceHexUpper(input)});
    while (try iterator.next()) |extracted_data| {
        std.debug.print("  {any}\n", .{extracted_data});
    }
}

test "basic encoding" {
    var demo = tests.Demo1{ .a = 150 };
    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);
    // 0x08 , 0x96, 0x01
    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x96, 0x01 }, obtained);

    demo.a = 0;
    const obtained2 = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained2);
    // 0x08 , 0x96, 0x01
    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x00 }, obtained2);
}

test "basic decoding" {
    const input = [_]u8{ 0x08, 0x96, 0x01 };
    const obtained = try tests.Demo1.decode(&input, testing.allocator);

    try testing.expectEqual(tests.Demo1{ .a = 150 }, obtained);

    const input2 = [_]u8{ 0x08, 0x00 };
    const obtained2 = try tests.Demo1.decode(&input2, testing.allocator);
    try testing.expectEqual(tests.Demo1{ .a = 0 }, obtained2);
}

test "basic encoding with optionals" {
    const demo = tests.Demo2{ .a = 150, .b = null };
    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);
    // 0x08 , 0x96, 0x01
    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x96, 0x01 }, obtained);

    const demo2 = tests.Demo2{ .a = 150, .b = 150 };
    const obtained2 = try demo2.encode(testing.allocator);
    defer testing.allocator.free(obtained2);
    // 0x08 , 0x96, 0x01
    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x96, 0x01, 0x10, 0x96, 0x01 }, obtained2);
}

test "basic encoding with negative numbers" {
    var demo = tests.WithNegativeIntegers{ .a = -2, .b = -1 };
    const obtained = try demo.encode(testing.allocator);
    defer demo.deinit();
    defer testing.allocator.free(obtained);
    // 0x08
    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x03, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F }, obtained);
    const decoded = try tests.WithNegativeIntegers.decode(obtained, testing.allocator);
    try testing.expectEqual(demo, decoded);
}

test "DemoWithAllVarint" {
    var demo = tests.DemoWithAllVarint{ .sint32 = -1, .sint64 = -1, .uint32 = 150, .uint64 = 150, .a_bool = true, .a_enum = tests.DemoWithAllVarint.DemoEnum.AndAnother, .pos_int32 = 1, .pos_int64 = 2, .neg_int32 = -1, .neg_int64 = -2 };
    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);
    // 0x08 , 0x96, 0x01
    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x01, 0x10, 0x01, 0x18, 0x96, 0x01, 0x20, 0x96, 0x01, 0x28, 0x01, 0x30, 0x02, 0x38, 0x01, 0x40, 0x02, 0x48, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0x50, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, obtained);

    const decoded = try tests.DemoWithAllVarint.decode(obtained, testing.allocator);
    try testing.expectEqual(demo, decoded);
}

test "WithSubmessages" {
    var demo = tests.WithSubmessages2{ .sub_demo1 = .{ .a = 1 }, .sub_demo2 = .{ .a = 2, .b = 3 } };

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x08 + 2, 0x02, 0x08, 0x01, 0x10 + 2, 0x04, 0x08, 0x02, 0x10, 0x03 }, obtained);

    const decoded = try tests.WithSubmessages2.decode(obtained, testing.allocator);
    try testing.expectEqual(demo, decoded);
}

test "FixedInt - not packed" {
    var demo = tests.WithIntsNotPacked.init(testing.allocator);
    try demo.list_of_data.append(0x08);
    try demo.list_of_data.append(0x01);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{
        0x08, 0x08,
        0x08, 0x01,
    }, obtained);

    const decoded = try tests.WithIntsNotPacked.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, demo.list_of_data.items, decoded.list_of_data.items);
}

test "varint packed - decode empty" {
    const decoded = try tests.WithIntsPacked.decode("\x0A\x00", testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, &[_]u32{}, decoded.list_of_data.items);
}

test "varint packed - decode" {
    const decoded = try tests.WithIntsPacked.decode("\x0A\x02\x31\x32", testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, &[_]u32{ 0x31, 0x32 }, decoded.list_of_data.items);
}

test "varint packed - encode, single element multi-byte-varint" {
    var demo = tests.WithIntsPacked.init(testing.allocator);
    try demo.list_of_data.append(0xA3);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x02, 0xA3, 0x01 }, obtained);
}

test "varint packed - decode, single element multi-byte-varint" {
    const obtained = &[_]u8{ 0x0A, 0x02, 0xA3, 0x01 };

    const decoded = try tests.WithIntsPacked.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, &[_]u32{0xA3}, decoded.list_of_data.items);
}

test "varint packed - encode decode, single element single-byte-varint" {
    var demo = tests.WithIntsPacked.init(testing.allocator);
    try demo.list_of_data.append(0x13);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x01, 0x13 }, obtained);

    const decoded = try tests.WithIntsPacked.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, demo.list_of_data.items, decoded.list_of_data.items);
}

test "varint packed - encode decode - single-byte-varint" {
    var demo = tests.WithIntsPacked.init(testing.allocator);
    try demo.list_of_data.append(0x11);
    try demo.list_of_data.append(0x12);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x02, 0x11, 0x12 }, obtained);

    const decoded = try tests.WithIntsPacked.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, demo.list_of_data.items, decoded.list_of_data.items);
}

test "varint packed - encode - multi-byte-varint" {
    var demo = tests.WithIntsPacked.init(testing.allocator);
    try demo.list_of_data.append(0xA1);
    try demo.list_of_data.append(0xA2);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x04, 0xA1, 0x01, 0xA2, 0x01 }, obtained);
}

test "integration varint packed - decode - multi-byte-varint" {
    const obtained = &[_]u8{ 0x0A, 0x04, 0xA1, 0x01, 0xA2, 0x01 };

    try testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x04, 0xA1, 0x01, 0xA2, 0x01 }, obtained);

    const decoded = try tests.WithIntsPacked.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, &[_]u32{ 0xA1, 0xA2 }, decoded.list_of_data.items);
}

fn log_slice(slice: []const u8) void {
    std.log.warn("{}", .{std.fmt.fmtSliceHexUpper(slice)});
}

test "FixedSizesList" {
    var demo = tests.FixedSizesList.init(testing.allocator);
    try demo.fixed32List.append(0x01);
    try demo.fixed32List.append(0x02);
    try demo.fixed32List.append(0x03);
    try demo.fixed32List.append(0x04);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{
        0x0D, 0x01, 0x00, 0x00, 0x00, 0x0D, 0x02, 0x00, 0x00, 0x00, 0x0D, 0x03, 0x00, 0x00, 0x00, 0x0D, 0x04, 0x00, 0x00, 0x00,
    }, obtained);

    const decoded = try tests.FixedSizesList.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, demo.fixed32List.items, decoded.fixed32List.items);
}

const VarintList = struct {
    varuint32List: ArrayList(u32),

    pub const _desc_table = .{
        .varuint32List = fd(1, .{ .List = .{ .Varint = .Simple } }),
    };

    pub fn encode(self: VarintList, allocator: Allocator) ![]u8 {
        return pb_encode(self, allocator);
    }

    pub fn deinit(self: VarintList) void {
        pb_deinit(self);
    }

    pub fn init(allocator: Allocator) VarintList {
        return pb_init(VarintList, allocator);
    }

    pub fn decode(input: []const u8, allocator: Allocator) !VarintList {
        return pb_decode(VarintList, input, allocator);
    }
};

test "VarintList - not packed" {
    var demo = VarintList.init(testing.allocator);
    try demo.varuint32List.append(0x01);
    try demo.varuint32List.append(0x02);
    try demo.varuint32List.append(0x03);
    try demo.varuint32List.append(0x04);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{
        0x08, 0x01,
        0x08, 0x02,
        0x08, 0x03,
        0x08, 0x04,
    }, obtained);

    const decoded = try VarintList.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, demo.varuint32List.items, decoded.varuint32List.items);
}

test "SubMessageList" {
    var demo = tests.SubMessageList.init(testing.allocator);
    try demo.subMessageList.append(.{ .a = 1 });
    try demo.subMessageList.append(.{ .a = 2 });
    try demo.subMessageList.append(.{ .a = 3 });
    try demo.subMessageList.append(.{ .a = 4 });
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x02, 0x08, 0x01, 0x0A, 0x02, 0x08, 0x02, 0x0A, 0x02, 0x08, 0x03, 0x0A, 0x02, 0x08, 0x04 }, obtained);

    const decoded = try tests.SubMessageList.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(tests.Demo1, demo.subMessageList.items, decoded.subMessageList.items);
}

test "EmptyLists" {
    var demo = tests.EmptyLists.init(testing.allocator);
    try demo.varuint32List.append(0x01);
    try demo.varuint32List.append(0x02);
    try demo.varuint32List.append(0x03);
    try demo.varuint32List.append(0x04);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x01, 0x08, 0x02, 0x08, 0x03, 0x08, 0x04 }, obtained);

    const decoded = try tests.EmptyLists.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqualSlices(u32, demo.varuint32List.items, decoded.varuint32List.items);
    try testing.expectEqualSlices(u32, demo.varuint32Empty.items, decoded.varuint32Empty.items);
}

test "EmptyMessage" {
    var demo = tests.EmptyMessage.init(testing.allocator);
    defer demo.deinit();

    const obtained = try demo.encode(testing.allocator);
    defer testing.allocator.free(obtained);

    try testing.expectEqualSlices(u8, &[_]u8{}, obtained);

    const decoded = try tests.EmptyMessage.decode(obtained, testing.allocator);
    defer decoded.deinit();
    try testing.expectEqual(demo, decoded);
}

const DefaultValuesInit = struct {
    a: ?u32 = 5,
    b: ?u32,
    c: ?u32 = 3,
    d: ?u32,

    pub const _desc_table = .{
        .a = fd(1, .{ .Varint = .Simple }),
        .b = fd(2, .{ .Varint = .Simple }),
        .c = fd(3, .{ .Varint = .Simple }),
        .d = fd(4, .{ .Varint = .Simple }),
    };

    pub usingnamespace protobuf.MessageMixins(@This());
};

test "DefaultValuesInit" {
    var demo = DefaultValuesInit.init(testing.allocator);
    try testing.expectEqual(@as(u32, 5), demo.a.?);
    try testing.expectEqual(@as(u32, 3), demo.c.?);
    try testing.expect(if (demo.b) |_| false else true);
    try testing.expect(if (demo.d) |_| false else true);
}

// const OneOfDemo = struct {
//     const a_case = enum { value_1, value_2 };

//     const a_union = union(a_case) {
//         value_1: u32,
//         value_2: ArrayList(u32),

//         pub const _union_desc = .{ .value_1 = fd(1, .{ .Varint = .Simple }), .value_2 = fd(2, .{ .List = .{ .Varint = .Simple } }) };
//     };

//     a: ?a_union,

//     pub const _desc_table = .{ .a = fd(null, .{ .OneOf = a_union }, ?a_union) };

//     pub fn encode(self: OneOfDemo, allocator: Allocator) ![]u8 {
//         return pb_encode(self, allocator);
//     }

//     pub fn init(allocator: Allocator) OneOfDemo {
//         return pb_init(OneOfDemo, allocator);
//     }

//     pub fn deinit(self: OneOfDemo) void {
//         pb_deinit(self);
//     }

//     pub fn decode(input: []const u8, allocator: Allocator) !OneOfDemo {
//         return pb_decode(OneOfDemo, input, allocator);
//     }
// };

// test "OneOfDemo" {
//     var demo = OneOfDemo.init(testing.allocator);
//     defer demo.deinit();

//     demo.a = .{ .value_1 = 10 };

//     const obtained = try demo.encode(testing.allocator);
//     defer testing.allocator.free(obtained);
//     try testing.expectEqualSlices(u8, &[_]u8{
//         0x08, 10,
//     }, obtained);
//     // const decoded = try OneOfDemo.decode(obtained, testing.allocator);
//     // defer decoded.deinit();
//     // try testing.expectEqual(demo.a.?.value_1, decoded.a.?.value_1);

//     demo.a = .{ .value_2 = ArrayList(u32).init(testing.allocator) };
//     try demo.a.?.value_2.append(1);
//     try demo.a.?.value_2.append(2);
//     try demo.a.?.value_2.append(3);
//     try demo.a.?.value_2.append(4);

//     const obtained2 = try demo.encode(testing.allocator);
//     defer testing.allocator.free(obtained2);
//     try testing.expectEqualSlices(u8, &[_]u8{
//         0x10 + 2, 0x04,
//         0x01,     0x02,
//         0x03,     0x04,
//     }, obtained2);
//     //const decoded2 = try OneOfDemo.decode(obtained2, testing.allocator);
//     //defer decoded2.deinit();
//     //try testing.expectEqualSlices(u32, demo.a.?.value_2.items, decoded2.a.?.value_2.items);
// }