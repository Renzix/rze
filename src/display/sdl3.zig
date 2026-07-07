const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const SDL3Display = struct {
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,
    pub fn init() !SDL3Display {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            std.log.err("SDL init failed: {s}", .{c.SDL_GetError()});
            return error.SDLInitializationFailed;
        }

        const window = c.SDL_CreateWindow("RZE Editor", 800, 600, 0) orelse
            {
                std.log.err("Window creation failed: {s}", .{c.SDL_GetError()});
                return error.WindowCreationFailed;
            };

        const renderer = c.SDL_CreateRenderer(window, null) orelse
            {
                std.log.err("Renderer creation failed: {s}", .{c.SDL_GetError()});
                return error.RendererCreationFailed;
            };

        std.log.info("Initialized Editor", .{});
        return SDL3Display{
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *SDL3Display) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn run(self: *SDL3Display) void {
        std.log.info("Running editor", .{});
        var running = true;
        while (running) {
            var event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&event)) {
                if (event.type == c.SDL_EVENT_QUIT) {
                    running = false;
                }
            }
            _ = c.SDL_SetRenderDrawColor(self.renderer, 20, 20, 20, 255);
            _ = c.SDL_RenderClear(self.renderer);
            _ = c.SDL_RenderPresent(self.renderer);
            c.SDL_Delay(16); // 60fps
        }
    }
};
