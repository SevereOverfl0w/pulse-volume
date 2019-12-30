const pulse = @cImport(@cInclude("pulse/pulseaudio.h"));
const warn = @import("std").debug.warn;
const round = @import("std").math.round;
const toSlice = @import("std").mem.toSlice;
const toSliceConst = @import("std").mem.toSliceConst;
const cstr = @import("std").cstr;

pub const PA_VOLUME_NORM = 0x10000;

fn volume_as_percent(cvol: pulse.pa_cvolume) u32 {
    // Implementation taken from pa_cvolume_sprintf
    return (pulse.pa_cvolume_max(&cvol) * 100 + (PA_VOLUME_NORM / 2)) / PA_VOLUME_NORM;
}

extern fn get_sink_info_callback(c: ?*pulse.struct_pa_context, optional_sink: [*c]const pulse.struct_pa_sink_info, islast: c_int, optional_userdata: ?*c_void) void {
    if (optional_sink) |sink| {
        if (optional_userdata) |user_data| {
            const default_sink = toSliceConst(u8, @ptrCast([*:0]u8, user_data));
            const sink_name = toSliceConst(u8, sink.*.name);
            if (cstr.cmp(sink_name, default_sink) == 0) {
                warn("{}%\n", .{volume_as_percent(sink.*.volume)});
            }
        }
    }
}

extern fn get_server_info_cb(c: ?*pulse.struct_pa_context, optional_server_info: [*c]const pulse.struct_pa_server_info, userdata: ?*c_void) void {
    if (optional_server_info != null) {
        var server_info = optional_server_info.*;
        var default_sink_name = server_info.default_sink_name;
        // This intToPtr/ptrToInt is here to workaround the fact that
        // default_sink_name is a const, but we're casting it to a non-const by
        // using it in a *c_void location.  This is okay because the
        // get_sink_info_callback casts it back to a const later.
        const o = pulse.pa_context_get_sink_info_list(c, get_sink_info_callback, @intToPtr(*c_void, @ptrToInt(default_sink_name)));
        pulse.pa_operation_unref(o);
    }
}

extern fn context_subscribe_callback(c: ?*pulse.struct_pa_context, t: pulse.pa_subscription_event_type_t, idx: u32, userdata: ?*c_void) void {
    const o = pulse.pa_context_get_server_info(c, get_server_info_cb, null);
    pulse.pa_operation_unref(o);
}

extern fn context_state_callback(c: ?*pulse.pa_context, userdata: ?*c_void) void {
    if (pulse.pa_context_get_state(c) == pulse.PA_CONTEXT_READY) {
        pulse.pa_context_set_subscribe_callback(c, context_subscribe_callback, null);

        const o = pulse.pa_context_subscribe(c, @intToEnum(pulse.enum_pa_subscription_mask, @enumToInt(pulse.PA_SUBSCRIPTION_MASK_SINK) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_SOURCE) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_SINK_INPUT) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_SOURCE_OUTPUT) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_MODULE) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_CLIENT) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_SAMPLE_CACHE) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_SERVER) |
            @enumToInt(pulse.PA_SUBSCRIPTION_MASK_CARD)), null, null);

        pulse.pa_operation_unref(o);

        const o2 = pulse.pa_context_get_server_info(c, get_server_info_cb, null);
        pulse.pa_operation_unref(o2);
    }
}

pub fn main() !void {
    const proplist = pulse.pa_proplist_new();
    defer pulse.pa_proplist_free(proplist);

    const m = pulse.pa_mainloop_new() orelse return error.PaMainloopNewFailed;
    defer pulse.pa_mainloop_free(m);

    const mainloop_api = pulse.pa_mainloop_get_api(m);

    const context = pulse.pa_context_new_with_proplist(mainloop_api, null, proplist) orelse return error.PaContextFailed;
    defer pulse.pa_context_unref(context);

    _ = pulse.pa_context_set_state_callback(context, context_state_callback, null);

    if (pulse.pa_context_connect(context, null, pulse.pa_context_flags.PA_CONTEXT_NOFLAGS, null) < 0) {
        return error.PaContextConnectFailed;
    }

    var ret: c_int = 1;

    if (pulse.pa_mainloop_run(m, &ret) < 0) {
        return error.PaMainloopRunFailed;
    }
}
