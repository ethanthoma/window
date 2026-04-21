#include <wayland-client.h>
#include <wayland-egl.h>
#include "xdg-shell.h"

struct wl_registry* wl_display_get_registry_wrapper(struct wl_display *display) {
    return wl_display_get_registry(display);
}

void* wl_registry_bind_wrapper(struct wl_registry *registry, uint32_t name, const struct wl_interface *interface, uint32_t version) {
    return wl_registry_bind(registry, name, interface, version);
}

int wl_registry_add_listener_wrapper(struct wl_registry *registry,
                                       const struct wl_registry_listener *listener,
                                       void *data) {
    return wl_registry_add_listener(registry, listener, data);
}

struct wl_surface* wl_compositor_create_surface_wrapper(struct wl_compositor *compositor) {
    return wl_compositor_create_surface(compositor);
}

struct wl_region* wl_compositor_create_region_wrapper(struct wl_compositor *compositor) {
    return wl_compositor_create_region(compositor);
}

void wl_region_add_wrapper(struct wl_region *region, int32_t x, int32_t y, int32_t width, int32_t height) {
    wl_region_add(region, x, y, width, height);
}

void wl_surface_set_opaque_region_wrapper(struct wl_surface *surface, struct wl_region *region) {
    wl_surface_set_opaque_region(surface, region);
}

void wl_region_destroy_wrapper(struct wl_region *region) {
    wl_region_destroy(region);
}

void wl_surface_destroy_wrapper(struct wl_surface *surface) {
    wl_surface_destroy(surface);
}

void wl_surface_commit_wrapper(struct wl_surface *surface) {
    wl_surface_commit(surface);
}

void wl_surface_damage_wrapper(struct wl_surface *surface,
                                 int32_t x, int32_t y,
                                 int32_t width, int32_t height) {
    wl_surface_damage(surface, x, y, width, height);
}

struct wl_callback* wl_surface_frame_wrapper(struct wl_surface *surface) {
    return wl_surface_frame(surface);
}

int wl_callback_add_listener_wrapper(struct wl_callback *callback,
                                       const struct wl_callback_listener *listener,
                                       void *data) {
    return wl_callback_add_listener(callback, listener, data);
}

void wl_callback_destroy_wrapper(struct wl_callback *callback) {
    wl_callback_destroy(callback);
}

int xdg_wm_base_add_listener_wrapper(struct xdg_wm_base *xdg_wm_base,
                                       const struct xdg_wm_base_listener *listener,
                                       void *data) {
    return xdg_wm_base_add_listener(xdg_wm_base, listener, data);
}

void xdg_wm_base_pong_wrapper(struct xdg_wm_base *xdg_wm_base, uint32_t serial) {
    xdg_wm_base_pong(xdg_wm_base, serial);
}

struct xdg_surface* xdg_wm_base_get_xdg_surface_wrapper(struct xdg_wm_base *xdg_wm_base,
                                                         struct wl_surface *surface) {
    return xdg_wm_base_get_xdg_surface(xdg_wm_base, surface);
}

int xdg_surface_add_listener_wrapper(struct xdg_surface *xdg_surface,
                                       const struct xdg_surface_listener *listener,
                                       void *data) {
    return xdg_surface_add_listener(xdg_surface, listener, data);
}

void xdg_surface_destroy_wrapper(struct xdg_surface *xdg_surface) {
    xdg_surface_destroy(xdg_surface);
}

void xdg_surface_ack_configure_wrapper(struct xdg_surface *xdg_surface, uint32_t serial) {
    xdg_surface_ack_configure(xdg_surface, serial);
}

struct xdg_toplevel* xdg_surface_get_toplevel_wrapper(struct xdg_surface *xdg_surface) {
    return xdg_surface_get_toplevel(xdg_surface);
}

int xdg_toplevel_add_listener_wrapper(struct xdg_toplevel *xdg_toplevel,
                                        const struct xdg_toplevel_listener *listener,
                                        void *data) {
    return xdg_toplevel_add_listener(xdg_toplevel, listener, data);
}

void xdg_toplevel_destroy_wrapper(struct xdg_toplevel *xdg_toplevel) {
    xdg_toplevel_destroy(xdg_toplevel);
}

void xdg_toplevel_set_title_wrapper(struct xdg_toplevel *xdg_toplevel, const char *title) {
    xdg_toplevel_set_title(xdg_toplevel, title);
}

void xdg_toplevel_set_app_id_wrapper(struct xdg_toplevel *xdg_toplevel, const char *app_id) {
    xdg_toplevel_set_app_id(xdg_toplevel, app_id);
}

struct wl_shm_pool* wl_shm_create_pool_wrapper(struct wl_shm *shm, int32_t fd, int32_t size) {
    return wl_shm_create_pool(shm, fd, size);
}

struct wl_buffer* wl_shm_pool_create_buffer_wrapper(struct wl_shm_pool *pool,
                                                     int32_t offset, int32_t width, int32_t height,
                                                     int32_t stride, uint32_t format) {
    return wl_shm_pool_create_buffer(pool, offset, width, height, stride, format);
}

void wl_shm_pool_destroy_wrapper(struct wl_shm_pool *pool) {
    wl_shm_pool_destroy(pool);
}

void wl_surface_attach_wrapper(struct wl_surface *surface, struct wl_buffer *buffer, int32_t x, int32_t y) {
    wl_surface_attach(surface, buffer, x, y);
}

void wl_buffer_destroy_wrapper(struct wl_buffer *buffer) {
    wl_buffer_destroy(buffer);
}

struct wl_keyboard* wl_seat_get_keyboard_wrapper(struct wl_seat *seat) {
    return wl_seat_get_keyboard(seat);
}

int wl_keyboard_add_listener_wrapper(struct wl_keyboard *keyboard,
                                       const struct wl_keyboard_listener *listener,
                                       void *data) {
    return wl_keyboard_add_listener(keyboard, listener, data);
}

void wl_keyboard_destroy_wrapper(struct wl_keyboard *keyboard) {
    wl_keyboard_destroy(keyboard);
}

struct wl_pointer* wl_seat_get_pointer_wrapper(struct wl_seat *seat) {
    return wl_seat_get_pointer(seat);
}

int wl_pointer_add_listener_wrapper(struct wl_pointer *pointer,
                                      const struct wl_pointer_listener *listener,
                                      void *data) {
    return wl_pointer_add_listener(pointer, listener, data);
}

void wl_pointer_destroy_wrapper(struct wl_pointer *pointer) {
    wl_pointer_destroy(pointer);
}

struct wl_egl_window* wl_egl_window_create_wrapper(struct wl_surface *surface, int width, int height) {
    return wl_egl_window_create(surface, width, height);
}

void wl_egl_window_destroy_wrapper(struct wl_egl_window *window) {
    wl_egl_window_destroy(window);
}

void wl_egl_window_resize_wrapper(struct wl_egl_window *window, int width, int height, int dx, int dy) {
    wl_egl_window_resize(window, width, height, dx, dy);
}
