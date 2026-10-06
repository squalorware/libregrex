const regexp = @import("regexp");
const syntax = regexp.syntax;

fn EvalParams(comptime T: type) type {
    return struct {
        value: T,
        flags: syntax.Flags,
    };
}

pub const MatchEvaluator = union(enum) {
    any: EvalParams(void),
    literal: EvalParams(u21),
    char_class: EvalParams(syntax.CharClass),
};
