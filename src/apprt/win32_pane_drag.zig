//! Pane drag-and-drop rearrangement: pure gesture state + dock-zone math.
//!
//! The gesture starts on a sidebar row (rows map 1:1 to panes), so a plain
//! mouse press still activates the row's pane; only after the cursor moves
//! past a small threshold does it become a drag. While dragging, the cursor
//! position is hit-tested against pane rectangles: the outer bands of a
//! target pane dock the dragged pane as a new split on that side, and the
//! center swaps the two panes. Dropping on another sidebar row swaps too.
//!
//! The Win32 host owns mouse capture, the translucent preview window, and
//! the split-tree mutation; this module holds only the decision logic so it
//! is unit-testable without a live window. Coordinates are host-client
//! pixels — the same space as WM_* mouse lParam.

const std = @import("std");

/// Cursor travel (L1, unscaled px) required before a press on a sidebar row
/// becomes a drag. Matches the tab-drag threshold so both gestures feel the
/// same.
pub const drag_threshold_px: i32 = 5;

/// Fraction of the target pane's width/height that counts as an edge dock
/// band. The remaining middle region swaps. 0.3 keeps the swap zone
/// comfortably large while all four edges stay easy to hit.
pub const edge_fraction: f32 = 0.3;

pub const Rect = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,

    pub fn width(self: Rect) i32 {
        return @max(0, self.right - self.left);
    }

    pub fn height(self: Rect) i32 {
        return @max(0, self.bottom - self.top);
    }

    pub fn contains(self: Rect, x: i32, y: i32) bool {
        return x >= self.left and x < self.right and y >= self.top and y < self.bottom;
    }
};

/// Where a drop lands within a target pane.
pub const DropZone = enum {
    left,
    right,
    top,
    bottom,
    /// Middle region: swap the dragged pane with the target pane.
    swap,
};

/// Dock zone for a cursor inside `rect`, or null when outside. Edge bands
/// win by the *closest* edge when the cursor sits in a corner overlap, so
/// every point maps to exactly one zone.
pub fn zoneAt(rect: Rect, x: i32, y: i32) ?DropZone {
    if (!rect.contains(x, y)) return null;
    const w: f32 = @floatFromInt(@max(1, rect.width()));
    const h: f32 = @floatFromInt(@max(1, rect.height()));
    const fx: f32 = @as(f32, @floatFromInt(x - rect.left)) / w; // 0..1
    const fy: f32 = @as(f32, @floatFromInt(y - rect.top)) / h;

    // Distance (as a fraction of the edge band) into each band; smaller
    // means deeper into that band.
    const in_left = fx < edge_fraction;
    const in_right = fx > 1.0 - edge_fraction;
    const in_top = fy < edge_fraction;
    const in_bottom = fy > 1.0 - edge_fraction;
    if (!in_left and !in_right and !in_top and !in_bottom) return .swap;

    const d_left: f32 = if (in_left) fx else std.math.floatMax(f32);
    const d_right: f32 = if (in_right) 1.0 - fx else std.math.floatMax(f32);
    const d_top: f32 = if (in_top) fy else std.math.floatMax(f32);
    const d_bottom: f32 = if (in_bottom) 1.0 - fy else std.math.floatMax(f32);

    var best = DropZone.left;
    var best_d = d_left;
    if (d_right < best_d) {
        best = .right;
        best_d = d_right;
    }
    if (d_top < best_d) {
        best = .top;
        best_d = d_top;
    }
    if (d_bottom < best_d) {
        best = .bottom;
        best_d = d_bottom;
    }
    return best;
}

/// Rectangle the translucent drop preview should cover for a zone within
/// `rect`: the corresponding half for edge docks, a centered inset for swap.
pub fn zonePreviewRect(rect: Rect, zone: DropZone) Rect {
    const w = rect.width();
    const h = rect.height();
    return switch (zone) {
        .left => .{ .left = rect.left, .top = rect.top, .right = rect.left + @divTrunc(w, 2), .bottom = rect.bottom },
        .right => .{ .left = rect.left + @divTrunc(w, 2), .top = rect.top, .right = rect.right, .bottom = rect.bottom },
        .top => .{ .left = rect.left, .top = rect.top, .right = rect.right, .bottom = rect.top + @divTrunc(h, 2) },
        .bottom => .{ .left = rect.left, .top = rect.top + @divTrunc(h, 2), .right = rect.right, .bottom = rect.bottom },
        .swap => .{
            .left = rect.left + @divTrunc(w, 6),
            .top = rect.top + @divTrunc(h, 6),
            .right = rect.right - @divTrunc(w, 6),
            .bottom = rect.bottom - @divTrunc(h, 6),
        },
    };
}

/// Gesture state. The Host stores one of these and forwards mouse events;
/// SetCapture/preview-window lifetimes stay in the Host.
pub const DragState = struct {
    /// A press happened on a sidebar row and may become a drag.
    armed: bool = false,
    /// The press crossed the threshold and is now a live drag.
    dragging: bool = false,
    /// Sidebar row index the gesture started on.
    source_row: usize = 0,
    start_x: i32 = 0,
    start_y: i32 = 0,

    pub fn arm(self: *DragState, row: usize, x: i32, y: i32) void {
        self.* = .{ .armed = true, .dragging = false, .source_row = row, .start_x = x, .start_y = y };
    }

    /// Feed a mouse move; returns true when this move promoted the press
    /// into a live drag (the caller switches cursor + shows preview).
    pub fn onMouseMove(self: *DragState, x: i32, y: i32, threshold: i32) bool {
        if (!self.armed or self.dragging) return false;
        const dx = if (x >= self.start_x) x - self.start_x else self.start_x - x;
        const dy = if (y >= self.start_y) y - self.start_y else self.start_y - y;
        if (dx + dy < threshold) return false;
        self.dragging = true;
        return true;
    }

    pub fn cancel(self: *DragState) void {
        self.* = .{};
    }
};

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

const r100 = Rect{ .left = 0, .top = 0, .right = 100, .bottom = 100 };

test "pane_drag: zoneAt returns null outside the rect" {
    try testing.expectEqual(@as(?DropZone, null), zoneAt(r100, -1, 50));
    try testing.expectEqual(@as(?DropZone, null), zoneAt(r100, 100, 50));
}

test "pane_drag: zoneAt maps edges and center" {
    try testing.expectEqual(@as(?DropZone, .left), zoneAt(r100, 5, 50));
    try testing.expectEqual(@as(?DropZone, .right), zoneAt(r100, 95, 50));
    try testing.expectEqual(@as(?DropZone, .top), zoneAt(r100, 50, 5));
    try testing.expectEqual(@as(?DropZone, .bottom), zoneAt(r100, 50, 95));
    try testing.expectEqual(@as(?DropZone, .swap), zoneAt(r100, 50, 50));
}

test "pane_drag: corner overlap picks the closest edge" {
    // (5, 20): 5% into the left band, 20% into the top band -> left wins.
    try testing.expectEqual(@as(?DropZone, .left), zoneAt(r100, 5, 20));
    // (20, 5): the reverse -> top wins.
    try testing.expectEqual(@as(?DropZone, .top), zoneAt(r100, 20, 5));
}

test "pane_drag: zonePreviewRect halves for edges, insets for swap" {
    try testing.expectEqual(Rect{ .left = 0, .top = 0, .right = 50, .bottom = 100 }, zonePreviewRect(r100, .left));
    try testing.expectEqual(Rect{ .left = 50, .top = 0, .right = 100, .bottom = 100 }, zonePreviewRect(r100, .right));
    try testing.expectEqual(Rect{ .left = 0, .top = 0, .right = 100, .bottom = 50 }, zonePreviewRect(r100, .top));
    try testing.expectEqual(Rect{ .left = 0, .top = 50, .right = 100, .bottom = 100 }, zonePreviewRect(r100, .bottom));
    try testing.expectEqual(Rect{ .left = 16, .top = 16, .right = 84, .bottom = 84 }, zonePreviewRect(r100, .swap));
}

test "pane_drag: DragState arms, promotes past threshold, cancels" {
    var ds = DragState{};
    ds.arm(2, 10, 10);
    try testing.expect(ds.armed);
    try testing.expect(!ds.dragging);
    // Below threshold: no promotion.
    try testing.expect(!ds.onMouseMove(12, 11, drag_threshold_px));
    try testing.expect(!ds.dragging);
    // Crossing the threshold promotes exactly once.
    try testing.expect(ds.onMouseMove(14, 12, drag_threshold_px));
    try testing.expect(ds.dragging);
    try testing.expect(!ds.onMouseMove(30, 30, drag_threshold_px));
    ds.cancel();
    try testing.expect(!ds.armed);
    try testing.expect(!ds.dragging);
}
