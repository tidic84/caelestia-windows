#pragma once

// Fonctions du coeur Rust (src/lib.rs, ilot_core.dll)

#include <cstddef>
#include <cstdint>

extern "C" {
typedef void (*ilot_emit_fn)(const char *name, const char *json);

void ilot_register(const char *label, intptr_t hwnd);
void ilot_unregister(const char *label);
void ilot_set_open(bool open);
void ilot_start(ilot_emit_fn emit);
void ilot_shutdown();
char *ilot_invoke(const char *label, const char *cmd, const char *args);
void ilot_free(char *p);
uint8_t *ilot_image(const char *id, size_t *len);
void ilot_free_bytes(uint8_t *p, size_t len);
int ilot_cli();
}
