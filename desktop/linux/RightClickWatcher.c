#define _POSIX_C_SOURCE 200809L
#include <X11/Xlib.h>
#include <X11/Xproto.h>
#include <X11/extensions/record.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Observe only physical/core right-button presses. No key events, clipboard
 * contents, injected input, grabs, or user text pass through this helper. */
static int is_x11_session(void) {
    const char *session = getenv("XDG_SESSION_TYPE");
    const char *wayland = getenv("WAYLAND_DISPLAY");
    const char *display = getenv("DISPLAY");
    if (session && strcmp(session, "wayland") == 0) return 0;
    if (session && strcmp(session, "x11") == 0) return display && *display;
    return (!wayland || !*wayland) && display && *display;
}

static int16_t coordinate(INT16 value, Bool swapped) {
    uint16_t bits = (uint16_t)value;
    if (swapped) bits = (uint16_t)((bits >> 8) | (bits << 8));
    return (int16_t)bits;
}

static void record_event(XPointer unused, XRecordInterceptData *packet) {
    (void)unused;
    if (!packet) return;
    if (packet->category == XRecordFromServer && packet->data) {
        /* Record batches protocol elements; each core device event is 32 bytes.
         * Copy before interpreting it to avoid unaligned reads. */
        const unsigned long count = packet->data_len / (sizeof(xEvent) / 4);
        for (unsigned long index = 0; index < count; index++) {
            xEvent event;
            memcpy(&event, packet->data + index * sizeof(event), sizeof(event));
            if ((event.u.u.type & 0x7f) != ButtonPress || event.u.u.detail != 3) continue;
            struct timespec now;
            if (clock_gettime(CLOCK_REALTIME, &now) != 0) continue;
            const long long captured_at = (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
            printf("{\"event\":\"right-click\",\"x\":%d,\"y\":%d,\"capturedAt\":%lld}\n",
                coordinate(event.u.keyButtonPointer.rootX, packet->client_swapped),
                coordinate(event.u.keyButtonPointer.rootY, packet->client_swapped), captured_at);
            fflush(stdout);
        }
    }
    XRecordFreeData(packet);
}

static int unsupported(int probe, const char *reason) {
    if (probe) printf("{\"supported\":false,\"protocol\":\"x11\",\"reason\":\"%s\"}\n", reason);
    else fprintf(stderr, "PromptFinch selection watcher unavailable: %s.\n", reason);
    return 2;
}

int main(int argc, char **argv) {
    const int probe = argc == 2 && strcmp(argv[1], "--probe") == 0;
    if (argc > 1 && !probe) return unsupported(0, "INVALID_ARGUMENTS");
    if (!is_x11_session()) return unsupported(probe, "X11_SESSION_REQUIRED");
    Display *control = XOpenDisplay(NULL);
    if (!control) return unsupported(probe, "DISPLAY_UNAVAILABLE");
    int major = 0, minor = 0;
    if (!XRecordQueryVersion(control, &major, &minor)) {
        XCloseDisplay(control);
        return unsupported(probe, "RECORD_EXTENSION_UNAVAILABLE");
    }
    if (probe) {
        puts("{\"supported\":true,\"protocol\":\"x11\"}");
        XCloseDisplay(control);
        return 0;
    }
    Display *events = XOpenDisplay(NULL);
    if (!events) { XCloseDisplay(control); return unsupported(0, "DISPLAY_UNAVAILABLE"); }
    XRecordRange *range = XRecordAllocRange();
    if (!range) {
        XCloseDisplay(events); XCloseDisplay(control);
        return unsupported(0, "CONTEXT_UNAVAILABLE");
    }
    range->device_events.first = ButtonPress;
    range->device_events.last = ButtonPress;
    XRecordClientSpec clients = XRecordAllClients;
    XRecordContext context = XRecordCreateContext(control, 0, &clients, 1, &range, 1);
    XFree(range);
    if (!context) {
        XCloseDisplay(events); XCloseDisplay(control);
        return unsupported(0, "CONTEXT_UNAVAILABLE");
    }
    XSync(control, False);
    /* This blocks only the dedicated child process, never Electron's main
     * process. Closing/killing this child releases both X connections. */
    const Status enabled = XRecordEnableContext(events, context, record_event, NULL);
    XRecordFreeContext(control, context);
    XCloseDisplay(events); XCloseDisplay(control);
    return enabled ? 0 : unsupported(0, "CONTEXT_UNAVAILABLE");
}
