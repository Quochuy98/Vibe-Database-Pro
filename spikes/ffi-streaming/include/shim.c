#include "dataforge_ffi_spike.h"

/* Keeps SwiftPM's C target concrete and compiles the canonical header. */
int32_t df_spike_header_probe(void) {
    return (int32_t)sizeof(df_spike_chunk_meta_v1);
}
