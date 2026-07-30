#ifndef DATAFORGE_FFI_SPIKE_H
#define DATAFORGE_FFI_SPIKE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DF_SPIKE_ABI_VERSION UINT32_C(1)
#define DF_SPIKE_ROW_ENCODING_VERSION UINT32_C(1)

#define DF_SPIKE_FEATURE_PULL_ACK (UINT64_C(1) << 0)
#define DF_SPIKE_FEATURE_CANCELLATION (UINT64_C(1) << 1)
#define DF_SPIKE_FEATURE_TYPED_ROWS (UINT64_C(1) << 2)
#define DF_SPIKE_FEATURE_PANIC_CONTAINMENT (UINT64_C(1) << 3)
#define DF_SPIKE_FEATURE_CALLER_BUFFER (UINT64_C(1) << 4)

typedef uint64_t df_spike_stream_handle_t;
typedef int32_t df_spike_status_code_t;

enum {
    DF_SPIKE_STATUS_OK = 0,
    DF_SPIKE_STATUS_TERMINAL = 1,
    DF_SPIKE_STATUS_CANCELLED = 2,
    DF_SPIKE_STATUS_INVALID_ARGUMENT = 3,
    DF_SPIKE_STATUS_ABI_MISMATCH = 4,
    DF_SPIKE_STATUS_UNSUPPORTED_FEATURE = 5,
    DF_SPIKE_STATUS_INVALID_HANDLE = 6,
    DF_SPIKE_STATUS_STALE_HANDLE = 7,
    DF_SPIKE_STATUS_REGISTRY_FULL = 8,
    DF_SPIKE_STATUS_LIMIT_EXCEEDED = 9,
    DF_SPIKE_STATUS_BUFFER_TOO_SMALL = 10,
    DF_SPIKE_STATUS_NEEDS_ACK = 11,
    DF_SPIKE_STATUS_ACK_MISMATCH = 12,
    DF_SPIKE_STATUS_BUSY = 13,
    DF_SPIKE_STATUS_ALLOCATION_FAILED = 14,
    DF_SPIKE_STATUS_PANIC = 15,
    DF_SPIKE_STATUS_INTERNAL = 16
};

enum {
    DF_SPIKE_STATE_READY = 1,
    DF_SPIKE_STATE_OUTSTANDING = 2,
    DF_SPIKE_STATE_COMPLETED = 3,
    DF_SPIKE_STATE_CANCELLED = 4,
    DF_SPIKE_STATE_FAILED = 5,
    DF_SPIKE_STATE_CANCEL_PENDING_ACK = 6
};

enum {
    DF_SPIKE_CANCEL_ACCEPTED = 1,
    DF_SPIKE_CANCEL_PENDING_ACK = 2,
    DF_SPIKE_CANCEL_ALREADY_REQUESTED = 3,
    DF_SPIKE_CANCEL_TOO_LATE = 4
};

enum {
    DF_SPIKE_CHUNK_FLAG_LAST = 1u << 0
};

/* All v1 structs are fixed-width, caller-owned records. Unknown larger tails
 * are ignored; the known prefix must be at least sizeof(the v1 struct). */
typedef struct df_spike_abi_request_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t required_features;
    uint64_t optional_features;
    uint32_t reserved0;
    uint32_t reserved1;
} df_spike_abi_request_v1;

typedef struct df_spike_abi_info_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t supported_features;
    uint32_t max_streams;
    uint32_t max_chunk_rows;
    uint32_t max_chunk_bytes;
    uint32_t row_encoding_version;
    uint32_t reserved0;
    uint32_t reserved1;
} df_spike_abi_info_v1;

typedef struct df_spike_stream_options_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t total_rows;
    uint64_t seed;
    uint32_t requested_chunk_rows;
    uint32_t requested_chunk_bytes;
    uint32_t reserved0;
    uint32_t reserved1;
} df_spike_stream_options_v1;

typedef struct df_spike_chunk_meta_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t sequence;
    uint64_t first_row;
    uint32_t row_count;
    uint32_t byte_count;
    uint32_t encoding_version;
    uint32_t flags;
    uint64_t checksum;
    uint32_t required_capacity;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
} df_spike_chunk_meta_v1;

typedef struct df_spike_stream_status_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t state;
    uint32_t terminal_error;
    uint64_t next_row;
    uint64_t total_rows;
    uint64_t outstanding_sequence;
    uint32_t last_error;
    uint32_t reserved0;
} df_spike_stream_status_v1;

typedef struct df_spike_cancel_outcome_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t outcome;
    uint32_t state;
    uint32_t reserved0;
    uint32_t reserved1;
} df_spike_cancel_outcome_v1;

/* Test-only observability for this disposable spike. */
typedef struct df_spike_registry_stats_v1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t live_streams;
    uint32_t max_streams;
    uint64_t in_flight_bytes;
    uint64_t created_streams;
    uint64_t released_streams;
    uint32_t reserved0;
    uint32_t reserved1;
} df_spike_registry_stats_v1;

df_spike_status_code_t df_spike_abi_negotiate_v1(
    const df_spike_abi_request_v1 *request,
    df_spike_abi_info_v1 *response);

df_spike_status_code_t df_spike_stream_create_v1(
    const df_spike_stream_options_v1 *options,
    df_spike_stream_handle_t *out_handle);

/* `destination` belongs to the caller and is borrowed only for this call.
 * Rust retains no pointer after return. A successful next creates one logical
 * chunk that must be acknowledged before another next. */
df_spike_status_code_t df_spike_stream_next_v1(
    df_spike_stream_handle_t handle,
    uint8_t *destination,
    uint64_t destination_capacity,
    df_spike_chunk_meta_v1 *out_meta);

df_spike_status_code_t df_spike_stream_ack_v1(
    df_spike_stream_handle_t handle,
    uint64_t sequence);

df_spike_status_code_t df_spike_stream_cancel_v1(
    df_spike_stream_handle_t handle,
    df_spike_cancel_outcome_v1 *outcome);

df_spike_status_code_t df_spike_stream_get_status_v1(
    df_spike_stream_handle_t handle,
    df_spike_stream_status_v1 *out_status);

/* Release is idempotent for the most recently released generation. It returns
 * NEEDS_ACK while a chunk is outstanding, so the caller cannot abandon the
 * logical stream without explicitly acknowledging the borrowed-buffer copy. */
df_spike_status_code_t df_spike_stream_release_v1(
    df_spike_stream_handle_t handle);

df_spike_status_code_t df_spike_get_registry_stats_v1(
    df_spike_registry_stats_v1 *out_stats);

/* Fault-injection hooks are part of the disposable spike only. */
df_spike_status_code_t df_spike_stream_arm_allocation_failure_v1(
    df_spike_stream_handle_t handle);
df_spike_status_code_t df_spike_stream_arm_panic_v1(
    df_spike_stream_handle_t handle);
df_spike_status_code_t df_spike_panic_probe_v1(void);

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(df_spike_abi_request_v1) == 32, "ABI request layout changed");
_Static_assert(sizeof(df_spike_abi_info_v1) == 40, "ABI info layout changed");
_Static_assert(sizeof(df_spike_stream_options_v1) == 40, "stream options layout changed");
_Static_assert(sizeof(df_spike_chunk_meta_v1) == 64, "chunk metadata layout changed");
_Static_assert(sizeof(df_spike_stream_status_v1) == 48, "stream status layout changed");
_Static_assert(sizeof(df_spike_cancel_outcome_v1) == 24, "cancel layout changed");
_Static_assert(sizeof(df_spike_registry_stats_v1) == 48, "stats layout changed");
#endif

#ifdef __cplusplus
}
#endif

#endif /* DATAFORGE_FFI_SPIKE_H */
