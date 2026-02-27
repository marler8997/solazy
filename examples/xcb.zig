pub fn main() !void {
    const display = std.posix.getenv("DISPLAY");
    std.log.debug("connecting to X11 DISPLAY {f}", .{xcb.fmtDisplay(display)});

    const connection, const screen_count = try xcb.connect(display);
    const screen = blk: {
        // const setup = xcb.get_setup(connection);
        const setup = xcblazy.get_setup.*(connection);
        var iter = xcb.setup_roots_iterator(setup);
        for (0..screen_count) |_| {
            xcb.screen_next(&iter);
        }
        break :blk iter.data;
    };

    const window = xcb.generate_id(connection).window();

    const window_width = 800;
    const window_height = 600;
    std.log.debug("creating window", .{});
    _ = xcb.create_window(
        connection,
        .{
            .depth = .copy_from_parent,
            .wid = window,
            .parent = screen.root,
            .x = 0,
            .y = 0,
            .width = window_width,
            .height = window_height,
            .border_width = 0,
            .class = .input_output,
            .visual = screen.root_visual,
        },
        .{
            .bg_pixel = screen.white_pixel,
            .event_mask = .{
                .KeyPress = 1,
                .KeyRelease = 1,
            },
        },
    );

    // Set the window title
    const title = "Hello XCB from Zig!";
    _ = xcb.change_property(
        connection,
        .REPLACE,
        window,
        .WM_NAME,
        .STRING,
        8,
        title.len,
        title.ptr,
    );

    // Intern the WM_DELETE_WINDOW atom so we can handle the close button
    const wm_protocols_cookie = xcb.intern_atom(connection, 1, 12, "WM_PROTOCOLS");
    const wm_delete_cookie = xcb.intern_atom(connection, 0, 16, "WM_DELETE_WINDOW");

    const wm_protocols_reply = xcb.intern_atom_reply(connection, wm_protocols_cookie, null);
    const wm_delete_reply = xcb.intern_atom_reply(connection, wm_delete_cookie, null);

    if (wm_protocols_reply) |protocols| {
        if (wm_delete_reply) |delete| {
            var delete_atom = @intFromEnum(delete.atom);
            _ = xcb.change_property(
                connection,
                .REPLACE,
                window,
                protocols.atom,
                .ATOM,
                32,
                1,
                &delete_atom,
            );
        }
    }

    _ = xcb.map_window(connection, window);
    _ = xcb.flush(connection);

    var running = true;
    while (running) {
        const event = xcb.wait_for_event(connection) orelse continue;
        defer std.heap.c_allocator.destroy(event);

        switch (event.response_type.op) {
            .EXPOSE => {
                // Window needs redrawing — nothing to draw in this simple example
            },
            .KEY_PRESS => {
                const key_event: *xcb.KeyPressEvent = @ptrCast(@alignCast(event));
                std.debug.print("Key pressed: keycode={}\n", .{key_event.detail});

                // Quit on Escape (keycode 9 on most X11 setups)
                if (key_event.detail == 9) running = false;
            },
            .CONFIGURE_NOTIFY => {
                const cfg: *xcb.ConfigureNotifyEvent = @ptrCast(@alignCast(event));
                std.debug.print("Window resized: {}x{}\n", .{ cfg.width, cfg.height });
            },
            .CLIENT_MESSAGE => {
                const cm: *xcb.ClientMessageEvent = @ptrCast(@alignCast(event));
                if (wm_delete_reply) |delete| {
                    if (cm.data.data32[0] == @intFromEnum(delete.atom)) {
                        std.debug.print("Window close requested\n", .{});
                        running = false;
                    }
                }
            },
            else => {},
        }
    }
}
const std = @import("std");
const solazy = @import("solazy");
const xcb = @import("xcb");
const xcblazy = struct {
    pub const get_setup = solazy.lazy("xcb", "xcb_get_setup", *const fn (*xcb.Connection) callconv(.c) *const xcb.Setup);
};
// const lazy_xcb_get_setup = solazy.wrap(xcb.get_setup);
