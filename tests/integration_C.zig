//! Integrated testing of exported C-compatible library API/ABI
const std = @import("std");
const clib = @import("libregrex");
const testing = std.testing;

test "regx_pattern_search() and regx_pattern_match() should use different match modes" {
    var pattern: ?*clib.regx_pattern_t = null;

    try testing.expectEqual(
        .OK,
        clib.regrex_compile("foo", 0, &pattern),
    );
    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_pattern_destroy(p);

    var search_match: ?*clib.regx_match_t = null;
    try testing.expectEqual(
        .OK,
        clib.regx_pattern_search(p, "xxfoo", &search_match),
    );
    const m = search_match orelse {
        try testing.expect(false);
        return;
    };
    clib.regx_match_destroy(m);

    var start_match: ?*clib.regx_match_t = null;
    try testing.expectEqual(
        .REGREX_ENOMATCH,
        clib.regx_pattern_match(p, "xxfoo", &start_match),
    );
    try testing.expect(start_match == null);
}

test "regx_pattern_find_iter() should iterate over matches" {
    var pattern: ?*clib.regx_pattern_t = null;

    try testing.expectEqual(
        .OK,
        clib.regrex_compile("[a-z]+", 0, &pattern),
    );
    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_pattern_destroy(p);

    var iter: ?*clib.regx_iter_t = null;
    try testing.expectEqual(
        .OK,
        clib.regx_pattern_find_iter(p, "one two", &iter),
    );
    const it = iter orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_iter_destroy(it);

    var first_match: ?*clib.regx_match_t = null;
    try testing.expectEqual(.OK, clib.regx_iter_next(it, &first_match));
    var m = first_match orelse {
        try testing.expect(false);
        return;
    };

    var first_span: clib.regx_span_t = undefined;
    try testing.expectEqual(.OK, clib.regx_match_span(m, 0, &first_span));
    try testing.expectEqual(@as(usize, 0), first_span.start);
    try testing.expectEqual(@as(usize, 3), first_span.end);
    clib.regx_match_destroy(first_match);

    var second_match: ?*clib.regx_match_t = null;
    try testing.expectEqual(.OK, clib.regx_iter_next(it, &second_match));
    m = second_match orelse {
        try testing.expect(false);
        return;
    };
    clib.regx_match_destroy(second_match);

    var end: ?*clib.regx_match_t = null;
    try testing.expectEqual(.REGREX_ENOMATCH, clib.regx_iter_next(it, &end));
    try testing.expect(end == null);
}

test "regx_pattern_sub() should write replacement output buffer" {
    var pattern: ?*clib.regx_pattern_t = null;

    try testing.expectEqual(
        .OK,
        clib.regrex_compile("[0-9]+", 0, &pattern),
    );
    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_pattern_destroy(p);

    var out_buf: ?[*:0]u8 = null;
    var out_len: usize = 0;

    try testing.expectEqual(
        .OK,
        clib.regx_pattern_sub(p, "a12b34", "#", 0, &out_buf, &out_len),
    );
    const result = out_buf orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regrex_str_free(result, out_len);

    try testing.expectEqualStrings("a#b#", std.mem.span(result));
}

test "regrex_error() maps return code to corresponding string message" {
    const expected = "Parsing error: Invalid or malformed UTF-8 code point";
    const msg = clib.regrex_error(.REGREX_EBADUTF8);

    try testing.expectEqualStrings(expected, std.mem.span(msg));
}

test "regrex_compile() should return a compiled pattern" {
    var pattern: ?*clib.regx_pattern_t = null;

    const rc = clib.regrex_compile("[0-9]+", 0, &pattern);
    try testing.expectEqual(.OK, rc);

    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_pattern_destroy(p);
}

test "regrex_search() should return match span and captured groups" {
    var match: ?*clib.regx_match_t = null;

    const rc = clib.regrex_search(
        "([a-z]+)=([0-9]+)",
        "foo=123",
        0,
        &match,
    );
    try testing.expectEqual(.OK, rc);

    const m = match orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_match_destroy(m);

    var span: clib.regx_span_t = undefined;
    try testing.expectEqual(
        .OK,
        clib.regx_match_span(m, 0, &span),
    );
    try testing.expectEqual(@as(usize, 0), span.start);
    try testing.expectEqual(@as(usize, 7), span.end);

    var out_buf: ?[*:0]u8 = null;
    var out_len: usize = 0;

    try testing.expectEqual(
        .OK,
        clib.regx_match_group(m, 1, &out_buf, &out_len),
    );
    const name = out_buf orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("foo", std.mem.span(name));

    clib.regrex_str_free(out_buf, out_len);
    out_len = 0;

    try testing.expectEqual(
        .OK,
        clib.regx_match_group(m, 2, &out_buf, &out_len),
    );
    const value = out_buf orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("123", std.mem.span(value));

    clib.regrex_str_free(out_buf, out_len);
    out_len = 0;
}

test "regrex_match() should not search past the beginning" {
    var match: ?*clib.regx_match_t = null;

    const rc = clib.regrex_match("foo", "xxfoo", 0, &match);

    try testing.expectEqual(.REGREX_ENOMATCH, rc);
    try testing.expect(match == null);
}

test "regrex_find_all() should return an array of matches" {
    var out_buf: ?[*]*clib.regx_match_t = null;
    var out_len: usize = 0;

    try testing.expectEqual(
        .OK,
        clib.regrex_find_all("([0-9]+)", "a1 b22", 0, &out_buf, &out_len),
    );

    const list = out_buf orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regx_match_buffer_free(&out_buf, out_len);

    try testing.expectEqual(@as(usize, 2), out_len);

    var span: clib.regx_span_t = undefined;
    try testing.expectEqual(.OK, clib.regx_match_span(list[1], 0, &span));
    try testing.expectEqual(@as(usize, 4), span.start);
    try testing.expectEqual(@as(usize, 6), span.end);

    var group_buf: ?[*:0]u8 = null;
    var group_len: usize = 0;
    try testing.expectEqual(.OK, clib.regx_match_group(list[1], 1, &group_buf, &group_len));

    const group = group_buf orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regrex_str_free(group_buf, group_len);

    try testing.expectEqualStrings("22", std.mem.span(group));
}

test "regrex_sub() should copy input, replace matches and write the copy to the output buffer" {
    var out_buf: ?[*:0]u8 = null;
    var out_len: usize = 0;

    try testing.expectEqual(
        .OK,
        clib.regrex_sub("[0-9]+", "a12b34", "<UwU>", 0, 0, &out_buf, &out_len),
    );
    const replaced = out_buf orelse {
        try testing.expect(false);
        return;
    };
    defer clib.regrex_str_free(out_buf, out_len);

    try testing.expectEqualStrings("a<UwU>b<UwU>", std.mem.span(replaced));
}
