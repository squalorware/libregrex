//! Common namespace for various types and functions
//! which are used to implement the exported C compatibility layer
//!
//! MUST NOT be importable or accessible from the root module
//! to avoid mixing up with the public API definitions;
//! When imported, MUST NOT be public
const types = @import("types");
const engine = @import("engine");

pub const C_IterHolder = types.ext.C_IterHolder;
pub const C_MutableStringPtr = ?*?[*:0]u8;
pub const C_MatchHolder = types.ext.C_MatchHolder;
pub const C_ReturnCode = types.ext.C_ReturnCode;
pub const C_StringPtr = ?[*:0]const u8;
pub const freeMatchCallback = types.freeMatchCallback;
pub const ManagedIterator = engine.ManagedIterator;
pub const ManagedMatch = types.ManagedMatch;
pub const Match = types.Match;
pub const Span = types.Span;
pub const toC_Array = types.conv.toC_Array;
pub const toC_ArrayWrapped = types.conv.toC_ArrayWrapped;
pub const toC_String = types.conv.toC_String;
pub const toCompileFlags = types.conv.toCompileFlags;
pub const toErrorCode = types.conv.toErrorCode;
pub const toErrorMsg = types.conv.toErrorMsg;
pub const toErrorSet = types.conv.toErrorSet;
