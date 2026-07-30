#![deny(unsafe_op_in_unsafe_fn)]

use std::array;
use std::mem::{align_of, offset_of, size_of};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::{Mutex, MutexGuard, OnceLock};

#[cfg(test)]
use std::sync::Condvar;

const ABI_VERSION: u32 = 1;
const ROW_ENCODING_VERSION: u32 = 1;
const FEATURE_MASK: u64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4);

const MAX_STREAMS: usize = 128;
const MAX_CHUNK_ROWS: u32 = 1_000;
const MAX_CHUNK_BYTES: u32 = 4 * 1024 * 1024;
const DEFAULT_CHUNK_ROWS: u32 = 200;
const DEFAULT_CHUNK_BYTES: u32 = 64 * 1024;
const MAX_TOTAL_ROWS: u64 = 10_000_000;
const MAX_ROW_BYTES: u32 = 40;
const NULL_ROW_BYTES: u32 = 24;

const STATUS_OK: i32 = 0;
const STATUS_TERMINAL: i32 = 1;
const STATUS_CANCELLED: i32 = 2;
const STATUS_INVALID_ARGUMENT: i32 = 3;
const STATUS_ABI_MISMATCH: i32 = 4;
const STATUS_UNSUPPORTED_FEATURE: i32 = 5;
const STATUS_INVALID_HANDLE: i32 = 6;
const STATUS_STALE_HANDLE: i32 = 7;
const STATUS_REGISTRY_FULL: i32 = 8;
const STATUS_LIMIT_EXCEEDED: i32 = 9;
const STATUS_BUFFER_TOO_SMALL: i32 = 10;
const STATUS_NEEDS_ACK: i32 = 11;
const STATUS_ACK_MISMATCH: i32 = 12;
const STATUS_ALLOCATION_FAILED: i32 = 14;
const STATUS_PANIC: i32 = 15;
const STATUS_INTERNAL: i32 = 16;

const STATE_READY: u32 = 1;
const STATE_OUTSTANDING: u32 = 2;
const STATE_COMPLETED: u32 = 3;
const STATE_CANCELLED: u32 = 4;
const STATE_FAILED: u32 = 5;
const STATE_CANCEL_PENDING_ACK: u32 = 6;

const CANCEL_ACCEPTED: u32 = 1;
const CANCEL_PENDING_ACK: u32 = 2;
const CANCEL_ALREADY_REQUESTED: u32 = 3;
const CANCEL_TOO_LATE: u32 = 4;

const CHUNK_FLAG_LAST: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_abi_request_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub required_features: u64,
    pub optional_features: u64,
    pub reserved0: u32,
    pub reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_abi_info_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub supported_features: u64,
    pub max_streams: u32,
    pub max_chunk_rows: u32,
    pub max_chunk_bytes: u32,
    pub row_encoding_version: u32,
    pub reserved0: u32,
    pub reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_stream_options_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub total_rows: u64,
    pub seed: u64,
    pub requested_chunk_rows: u32,
    pub requested_chunk_bytes: u32,
    pub reserved0: u32,
    pub reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_chunk_meta_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub sequence: u64,
    pub first_row: u64,
    pub row_count: u32,
    pub byte_count: u32,
    pub encoding_version: u32,
    pub flags: u32,
    pub checksum: u64,
    pub required_capacity: u32,
    pub reserved0: u32,
    pub reserved1: u32,
    pub reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_stream_status_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub state: u32,
    pub terminal_error: u32,
    pub next_row: u64,
    pub total_rows: u64,
    pub outstanding_sequence: u64,
    pub last_error: u32,
    pub reserved0: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_cancel_outcome_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub outcome: u32,
    pub state: u32,
    pub reserved0: u32,
    pub reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct df_spike_registry_stats_v1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub live_streams: u32,
    pub max_streams: u32,
    pub in_flight_bytes: u64,
    pub created_streams: u64,
    pub released_streams: u64,
    pub reserved0: u32,
    pub reserved1: u32,
}

macro_rules! assert_abi_layout {
    (
        $type:ty,
        size: $size:expr,
        align: $align:expr,
        offsets: { $($field:ident: $offset:expr),+ $(,)? }
    ) => {
        const _: [(); $size] = [(); size_of::<$type>()];
        const _: [(); $align] = [(); align_of::<$type>()];
        $(const _: [(); $offset] = [(); offset_of!($type, $field)];)+
    };
}

assert_abi_layout!(
    df_spike_abi_request_v1,
    size: 32,
    align: 8,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        required_features: 8,
        optional_features: 16,
        reserved0: 24,
        reserved1: 28,
    }
);
assert_abi_layout!(
    df_spike_abi_info_v1,
    size: 40,
    align: 8,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        supported_features: 8,
        max_streams: 16,
        max_chunk_rows: 20,
        max_chunk_bytes: 24,
        row_encoding_version: 28,
        reserved0: 32,
        reserved1: 36,
    }
);
assert_abi_layout!(
    df_spike_stream_options_v1,
    size: 40,
    align: 8,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        total_rows: 8,
        seed: 16,
        requested_chunk_rows: 24,
        requested_chunk_bytes: 28,
        reserved0: 32,
        reserved1: 36,
    }
);
assert_abi_layout!(
    df_spike_chunk_meta_v1,
    size: 64,
    align: 8,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        sequence: 8,
        first_row: 16,
        row_count: 24,
        byte_count: 28,
        encoding_version: 32,
        flags: 36,
        checksum: 40,
        required_capacity: 48,
        reserved0: 52,
        reserved1: 56,
        reserved2: 60,
    }
);
assert_abi_layout!(
    df_spike_stream_status_v1,
    size: 48,
    align: 8,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        state: 8,
        terminal_error: 12,
        next_row: 16,
        total_rows: 24,
        outstanding_sequence: 32,
        last_error: 40,
        reserved0: 44,
    }
);
assert_abi_layout!(
    df_spike_cancel_outcome_v1,
    size: 24,
    align: 4,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        outcome: 8,
        state: 12,
        reserved0: 16,
        reserved1: 20,
    }
);
assert_abi_layout!(
    df_spike_registry_stats_v1,
    size: 48,
    align: 8,
    offsets: {
        struct_size: 0,
        abi_version: 4,
        live_streams: 8,
        max_streams: 12,
        in_flight_bytes: 16,
        created_streams: 24,
        released_streams: 32,
        reserved0: 40,
        reserved1: 44,
    }
);

#[derive(Clone, Copy, PartialEq, Eq)]
enum StreamState {
    Ready,
    Outstanding,
    Completed,
    Cancelled,
    Failed,
}

struct Stream {
    total_rows: u64,
    seed: u64,
    chunk_rows: u32,
    chunk_bytes: u32,
    next_row: u64,
    next_sequence: u64,
    outstanding_sequence: Option<u64>,
    outstanding_first_row: u64,
    outstanding_row_count: u32,
    cancel_requested: bool,
    state: StreamState,
    terminal_error: u32,
    last_error: u32,
    fail_next_allocation: bool,
    panic_next: bool,
}

impl Stream {
    fn new(total_rows: u64, seed: u64, chunk_rows: u32, chunk_bytes: u32) -> Self {
        Self {
            total_rows,
            seed,
            chunk_rows,
            chunk_bytes,
            next_row: 0,
            next_sequence: 1,
            outstanding_sequence: None,
            outstanding_first_row: 0,
            outstanding_row_count: 0,
            cancel_requested: false,
            state: StreamState::Ready,
            terminal_error: 0,
            last_error: 0,
            fail_next_allocation: false,
            panic_next: false,
        }
    }

    fn c_state(&self) -> u32 {
        if self.state == StreamState::Outstanding && self.cancel_requested {
            STATE_CANCEL_PENDING_ACK
        } else {
            match self.state {
                StreamState::Ready => STATE_READY,
                StreamState::Outstanding => STATE_OUTSTANDING,
                StreamState::Completed => STATE_COMPLETED,
                StreamState::Cancelled => STATE_CANCELLED,
                StreamState::Failed => STATE_FAILED,
            }
        }
    }
}

struct Slot {
    generation: u32,
    retired: bool,
    stream: Option<Stream>,
    last_released: u64,
}

impl Slot {
    const fn new() -> Self {
        Self {
            generation: 1,
            retired: false,
            stream: None,
            last_released: 0,
        }
    }
}

struct Registry {
    slots: [Slot; MAX_STREAMS],
    live_streams: u32,
    created_streams: u64,
    released_streams: u64,
}

impl Registry {
    fn new() -> Self {
        Self {
            slots: array::from_fn(|_| Slot::new()),
            live_streams: 0,
            created_streams: 0,
            released_streams: 0,
        }
    }

    #[cfg(test)]
    fn reset(&mut self) {
        *self = Self::new();
    }
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();

#[cfg(test)]
#[derive(Clone, Copy)]
enum TestRegistryOperation {
    Cancel,
    Release,
}

#[cfg(test)]
#[derive(Default)]
struct NextRegistryLockHookState {
    target_handle: u64,
    armed: bool,
    next_holds_registry_lock: bool,
    resume_next: bool,
    cancel_attempted: bool,
    release_attempted: bool,
}

#[cfg(test)]
static NEXT_REGISTRY_LOCK_HOOK: OnceLock<(Mutex<NextRegistryLockHookState>, Condvar)> =
    OnceLock::new();

#[cfg(test)]
fn next_registry_lock_hook() -> &'static (Mutex<NextRegistryLockHookState>, Condvar) {
    NEXT_REGISTRY_LOCK_HOOK.get_or_init(|| {
        (
            Mutex::new(NextRegistryLockHookState::default()),
            Condvar::new(),
        )
    })
}

#[cfg(test)]
fn lock_next_registry_hook() -> MutexGuard<'static, NextRegistryLockHookState> {
    match next_registry_lock_hook().0.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

#[cfg(test)]
fn pause_next_while_holding_registry_lock(handle: u64) {
    let (_, condition) = next_registry_lock_hook();
    let mut state = lock_next_registry_hook();
    if !state.armed || state.target_handle != handle {
        return;
    }
    state.next_holds_registry_lock = true;
    condition.notify_all();
    while !state.resume_next {
        state = match condition.wait(state) {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
    }
    state.next_holds_registry_lock = false;
    state.armed = false;
    condition.notify_all();
}

#[cfg(test)]
fn observe_registry_lock_attempt(handle: u64, operation: TestRegistryOperation) {
    let (_, condition) = next_registry_lock_hook();
    let mut state = lock_next_registry_hook();
    if !state.armed || state.target_handle != handle {
        return;
    }
    match operation {
        TestRegistryOperation::Cancel => state.cancel_attempted = true,
        TestRegistryOperation::Release => state.release_attempted = true,
    }
    condition.notify_all();
}

fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(|| Mutex::new(Registry::new()))
}

fn lock_registry() -> MutexGuard<'static, Registry> {
    match registry().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn ffi_call<F>(function: F) -> i32
where
    F: FnOnce() -> i32,
{
    match catch_unwind(AssertUnwindSafe(function)) {
        Ok(status) => status,
        Err(_) => STATUS_PANIC,
    }
}

fn clear_out<T: Default + Copy>(pointer: *mut T) -> Result<(), i32> {
    if pointer.is_null() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    // SAFETY: The caller contract requires a non-null, writable, correctly
    // aligned output pointer for the complete v1 record.
    unsafe { ptr::write(pointer, T::default()) };
    Ok(())
}

fn write_out<T: Copy>(pointer: *mut T, value: T) -> Result<(), i32> {
    if pointer.is_null() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    // SAFETY: The exported ABI requires the caller to provide an exclusive,
    // writable pointer valid for the duration of this synchronous call.
    unsafe { ptr::write(pointer, value) };
    Ok(())
}

fn input_copy<T: Copy>(pointer: *const T) -> Result<T, i32> {
    if pointer.is_null() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    // Read only the common prefix before trusting the advertised record size.
    // A caller supplying a short v1 record is rejected without reading its
    // unadvertised tail. C still cannot make a wild non-null pointer safe.
    let prefix = {
        // SAFETY: Every v1 input begins with two fixed-width fields and the C
        // contract requires that eight-byte prefix to be readable/aligned.
        unsafe { ptr::read(pointer.cast::<[u32; 2]>()) }
    };
    if !valid_prefix(prefix[0], size_of::<T>()) {
        return Err(STATUS_ABI_MISMATCH);
    }
    // SAFETY: The exported ABI requires a non-null, readable, correctly
    // aligned input record. The fixed-width record is copied immediately, so
    // no caller pointer is retained after this helper returns.
    Ok(unsafe { ptr::read(pointer) })
}

fn valid_prefix(struct_size: u32, expected: usize) -> bool {
    usize::try_from(struct_size).is_ok_and(|size| size >= expected)
}

fn encode_handle(slot_index: usize, generation: u32) -> Result<u64, i32> {
    let slot = u64::try_from(slot_index + 1).map_err(|_| STATUS_INTERNAL)?;
    Ok((u64::from(generation) << 32) | slot)
}

fn decode_handle(handle: u64) -> Result<(usize, u32), i32> {
    if handle == 0 {
        return Err(STATUS_INVALID_HANDLE);
    }
    let slot_number =
        u32::try_from(handle & u64::from(u32::MAX)).map_err(|_| STATUS_INVALID_HANDLE)?;
    let generation = u32::try_from(handle >> 32).map_err(|_| STATUS_INVALID_HANDLE)?;
    if slot_number == 0
        || usize::try_from(slot_number).map_or(true, |n| n > MAX_STREAMS)
        || generation == 0
    {
        return Err(STATUS_INVALID_HANDLE);
    }
    let slot_index = usize::try_from(slot_number - 1).map_err(|_| STATUS_INVALID_HANDLE)?;
    Ok((slot_index, generation))
}

fn stream_mut(registry: &mut Registry, handle: u64) -> Result<&mut Stream, i32> {
    let (slot_index, generation) = decode_handle(handle)?;
    let slot = &mut registry.slots[slot_index];
    if slot.retired || slot.generation != generation {
        return Err(STATUS_STALE_HANDLE);
    }
    match slot.stream.as_mut() {
        Some(stream) => Ok(stream),
        None => Err(STATUS_STALE_HANDLE),
    }
}

fn row_is_null(index: u64) -> bool {
    index.is_multiple_of(10)
}

fn row_length(index: u64) -> u32 {
    if row_is_null(index) {
        NULL_ROW_BYTES
    } else {
        MAX_ROW_BYTES
    }
}

fn row_value(index: u64, seed: u64) -> i64 {
    (index ^ seed) as i64
}

fn plan_chunk(stream: &Stream) -> Result<(u32, u32), i32> {
    let remaining = stream
        .total_rows
        .checked_sub(stream.next_row)
        .ok_or(STATUS_INTERNAL)?;
    let remaining_u32 = u32::try_from(remaining).unwrap_or(u32::MAX);
    let target_rows = stream.chunk_rows.min(remaining_u32);
    let mut rows = 0_u32;
    let mut bytes = 0_u32;
    while rows < target_rows {
        let index = stream
            .next_row
            .checked_add(u64::from(rows))
            .ok_or(STATUS_INTERNAL)?;
        let row_bytes = row_length(index);
        let Some(new_bytes) = bytes.checked_add(row_bytes) else {
            return Err(STATUS_LIMIT_EXCEEDED);
        };
        if new_bytes > stream.chunk_bytes {
            break;
        }
        bytes = new_bytes;
        rows += 1;
    }
    if rows == 0 {
        return Err(STATUS_LIMIT_EXCEEDED);
    }
    Ok((rows, bytes))
}

fn append_u64_le(destination: &mut Vec<u8>, value: u64) {
    destination.extend_from_slice(&value.to_le_bytes());
}

fn append_u32_le(destination: &mut Vec<u8>, value: u32) {
    destination.extend_from_slice(&value.to_le_bytes());
}

fn append_i64_le(destination: &mut Vec<u8>, value: i64) {
    destination.extend_from_slice(&value.to_le_bytes());
}

fn append_hex_u64(destination: &mut Vec<u8>, value: u64) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = [b'0'; 16];
    let mut position = 16_usize;
    let mut remaining = value;
    while position > 0 {
        position -= 1;
        encoded[position] = HEX[(remaining & 0x0f) as usize];
        remaining >>= 4;
    }
    destination.extend_from_slice(&encoded);
}

fn encode_rows(stream: &Stream, row_count: u32, byte_count: u32) -> Result<Vec<u8>, i32> {
    let capacity = usize::try_from(byte_count).map_err(|_| STATUS_LIMIT_EXCEEDED)?;
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(capacity)
        .map_err(|_| STATUS_ALLOCATION_FAILED)?;
    for offset in 0..row_count {
        let index = stream
            .next_row
            .checked_add(u64::from(offset))
            .ok_or(STATUS_INTERNAL)?;
        let is_null = row_is_null(index);
        let text_length = if is_null { 0 } else { 16 };
        append_u64_le(&mut bytes, index);
        append_i64_le(&mut bytes, row_value(index, stream.seed));
        append_u32_le(&mut bytes, text_length);
        bytes.push(if index & 1 == 1 { 1 } else { 0 });
        bytes.push(if is_null { 1 } else { 0 });
        bytes.extend_from_slice(&[0, 0]);
        if !is_null {
            append_hex_u64(&mut bytes, index);
        }
    }
    if bytes.len() != capacity {
        return Err(STATUS_INTERNAL);
    }
    Ok(bytes)
}

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn copy_to_destination(destination: *mut u8, bytes: &[u8]) {
    // SAFETY: The caller has supplied a non-null writable destination with at
    // least bytes.len() capacity; the pointer is borrowed only for this call.
    unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
}

fn validate_request(request: &df_spike_abi_request_v1) -> Result<(), i32> {
    if !valid_prefix(request.struct_size, size_of::<df_spike_abi_request_v1>())
        || request.abi_version != ABI_VERSION
        || request.reserved0 != 0
        || request.reserved1 != 0
    {
        return Err(STATUS_ABI_MISMATCH);
    }
    if request.required_features & !FEATURE_MASK != 0 {
        return Err(STATUS_UNSUPPORTED_FEATURE);
    }
    Ok(())
}

fn validate_options(options: &df_spike_stream_options_v1) -> Result<(u32, u32), i32> {
    if !valid_prefix(options.struct_size, size_of::<df_spike_stream_options_v1>())
        || options.abi_version != ABI_VERSION
        || options.reserved0 != 0
        || options.reserved1 != 0
    {
        return Err(STATUS_ABI_MISMATCH);
    }
    if options.total_rows > MAX_TOTAL_ROWS {
        return Err(STATUS_LIMIT_EXCEEDED);
    }
    let chunk_rows = if options.requested_chunk_rows == 0 {
        DEFAULT_CHUNK_ROWS
    } else {
        options.requested_chunk_rows
    };
    let chunk_bytes = if options.requested_chunk_bytes == 0 {
        DEFAULT_CHUNK_BYTES
    } else {
        options.requested_chunk_bytes
    };
    if chunk_rows > MAX_CHUNK_ROWS || !(MAX_ROW_BYTES..=MAX_CHUNK_BYTES).contains(&chunk_bytes) {
        return Err(STATUS_LIMIT_EXCEEDED);
    }
    Ok((chunk_rows, chunk_bytes))
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_abi_negotiate_v1(
    request: *const df_spike_abi_request_v1,
    response: *mut df_spike_abi_info_v1,
) -> i32 {
    ffi_call(|| {
        let clear_status = clear_out(response);
        if clear_status.is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        let request = match input_copy(request) {
            Ok(value) => value,
            Err(status) => return status,
        };
        if let Err(status) = validate_request(&request) {
            return status;
        }
        let response_value = df_spike_abi_info_v1 {
            struct_size: size_of::<df_spike_abi_info_v1>() as u32,
            abi_version: ABI_VERSION,
            supported_features: FEATURE_MASK,
            max_streams: MAX_STREAMS as u32,
            max_chunk_rows: MAX_CHUNK_ROWS,
            max_chunk_bytes: MAX_CHUNK_BYTES,
            row_encoding_version: ROW_ENCODING_VERSION,
            reserved0: 0,
            reserved1: 0,
        };
        if write_out(response, response_value).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_create_v1(
    options: *const df_spike_stream_options_v1,
    out_handle: *mut u64,
) -> i32 {
    ffi_call(|| {
        if clear_out(out_handle).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        let options = match input_copy(options) {
            Ok(value) => value,
            Err(status) => return status,
        };
        let (chunk_rows, chunk_bytes) = match validate_options(&options) {
            Ok(values) => values,
            Err(status) => return status,
        };
        let mut registry = lock_registry();
        if registry.live_streams == u32::MAX || registry.created_streams == u64::MAX {
            return STATUS_INTERNAL;
        }
        let Some((slot_index, slot)) = registry
            .slots
            .iter_mut()
            .enumerate()
            .find(|(_, slot)| !slot.retired && slot.stream.is_none())
        else {
            return STATUS_REGISTRY_FULL;
        };
        let generation = slot.generation;
        let handle = match encode_handle(slot_index, generation) {
            Ok(value) => value,
            Err(status) => return status,
        };
        slot.stream = Some(Stream::new(
            options.total_rows,
            options.seed,
            chunk_rows,
            chunk_bytes,
        ));
        registry.live_streams += 1;
        registry.created_streams += 1;
        if write_out(out_handle, handle).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_next_v1(
    handle: u64,
    destination: *mut u8,
    destination_capacity: u64,
    out_meta: *mut df_spike_chunk_meta_v1,
) -> i32 {
    ffi_call(|| {
        if clear_out(out_meta).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        let mut registry = lock_registry();
        #[cfg(test)]
        pause_next_while_holding_registry_lock(handle);
        let stream = match stream_mut(&mut registry, handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        if stream.state == StreamState::Failed {
            return if stream.terminal_error == 0 {
                STATUS_PANIC
            } else {
                stream.terminal_error as i32
            };
        }
        if stream.state == StreamState::Completed {
            return STATUS_TERMINAL;
        }
        if stream.state == StreamState::Cancelled || stream.cancel_requested {
            return STATUS_CANCELLED;
        }
        if stream.outstanding_sequence.is_some() {
            return STATUS_NEEDS_ACK;
        }
        if stream.next_row >= stream.total_rows {
            stream.state = StreamState::Completed;
            return STATUS_TERMINAL;
        }
        if stream.panic_next {
            stream.panic_next = false;
            stream.state = StreamState::Failed;
            stream.terminal_error = STATUS_PANIC as u32;
            panic!("DataForge FFI spike fault injection");
        }
        let (row_count, byte_count) = match plan_chunk(stream) {
            Ok(plan) => plan,
            Err(status) => return status,
        };
        let mut metadata = df_spike_chunk_meta_v1 {
            struct_size: size_of::<df_spike_chunk_meta_v1>() as u32,
            abi_version: ABI_VERSION,
            sequence: 0,
            first_row: stream.next_row,
            row_count,
            byte_count: 0,
            encoding_version: ROW_ENCODING_VERSION,
            flags: 0,
            checksum: 0,
            required_capacity: byte_count,
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        };
        if destination_capacity < u64::from(byte_count) {
            if write_out(out_meta, metadata).is_err() {
                return STATUS_INVALID_ARGUMENT;
            }
            return STATUS_BUFFER_TOO_SMALL;
        }
        if destination.is_null() {
            return STATUS_INVALID_ARGUMENT;
        }
        if stream.fail_next_allocation {
            stream.fail_next_allocation = false;
            stream.last_error = STATUS_ALLOCATION_FAILED as u32;
            return STATUS_ALLOCATION_FAILED;
        }
        let bytes = match encode_rows(stream, row_count, byte_count) {
            Ok(value) => value,
            Err(status) => {
                if status == STATUS_ALLOCATION_FAILED {
                    stream.last_error = STATUS_ALLOCATION_FAILED as u32;
                }
                return status;
            }
        };
        copy_to_destination(destination, &bytes);
        let sequence = stream.next_sequence;
        stream.next_sequence = match stream.next_sequence.checked_add(1) {
            Some(value) => value,
            None => return STATUS_INTERNAL,
        };
        stream.outstanding_sequence = Some(sequence);
        stream.outstanding_first_row = stream.next_row;
        stream.outstanding_row_count = row_count;
        stream.state = StreamState::Outstanding;
        stream.last_error = 0;
        metadata.sequence = sequence;
        metadata.byte_count = byte_count;
        metadata.checksum = fnv1a(&bytes);
        if stream
            .next_row
            .checked_add(u64::from(row_count))
            .is_some_and(|end| end == stream.total_rows)
        {
            metadata.flags |= CHUNK_FLAG_LAST;
        }
        if write_out(out_meta, metadata).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_ack_v1(handle: u64, sequence: u64) -> i32 {
    ffi_call(|| {
        let mut registry = lock_registry();
        let stream = match stream_mut(&mut registry, handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        if stream.outstanding_sequence != Some(sequence) {
            return STATUS_ACK_MISMATCH;
        }
        let next_row = match stream
            .outstanding_first_row
            .checked_add(u64::from(stream.outstanding_row_count))
        {
            Some(value) => value,
            None => return STATUS_INTERNAL,
        };
        stream.next_row = next_row;
        stream.outstanding_sequence = None;
        stream.outstanding_row_count = 0;
        stream.last_error = 0;
        if stream.cancel_requested {
            stream.state = StreamState::Cancelled;
        } else if stream.next_row == stream.total_rows {
            stream.state = StreamState::Completed;
        } else {
            stream.state = StreamState::Ready;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_cancel_v1(
    handle: u64,
    outcome: *mut df_spike_cancel_outcome_v1,
) -> i32 {
    ffi_call(|| {
        if clear_out(outcome).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        #[cfg(test)]
        observe_registry_lock_attempt(handle, TestRegistryOperation::Cancel);
        let mut registry = lock_registry();
        let stream = match stream_mut(&mut registry, handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        let mut response = df_spike_cancel_outcome_v1 {
            struct_size: size_of::<df_spike_cancel_outcome_v1>() as u32,
            abi_version: ABI_VERSION,
            outcome: 0,
            state: 0,
            reserved0: 0,
            reserved1: 0,
        };
        if stream.cancel_requested {
            response.outcome = CANCEL_ALREADY_REQUESTED;
        } else if stream.state == StreamState::Ready {
            stream.cancel_requested = true;
            stream.state = StreamState::Cancelled;
            response.outcome = CANCEL_ACCEPTED;
        } else if stream.state == StreamState::Outstanding {
            stream.cancel_requested = true;
            response.outcome = CANCEL_PENDING_ACK;
        } else {
            response.outcome = CANCEL_TOO_LATE;
        }
        response.state = stream.c_state();
        if write_out(outcome, response).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_get_status_v1(
    handle: u64,
    out_status: *mut df_spike_stream_status_v1,
) -> i32 {
    ffi_call(|| {
        if clear_out(out_status).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        let mut registry = lock_registry();
        let stream = match stream_mut(&mut registry, handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        let status = df_spike_stream_status_v1 {
            struct_size: size_of::<df_spike_stream_status_v1>() as u32,
            abi_version: ABI_VERSION,
            state: stream.c_state(),
            terminal_error: stream.terminal_error,
            next_row: stream.next_row,
            total_rows: stream.total_rows,
            outstanding_sequence: stream.outstanding_sequence.unwrap_or(0),
            last_error: stream.last_error,
            reserved0: 0,
        };
        if write_out(out_status, status).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_release_v1(handle: u64) -> i32 {
    ffi_call(|| {
        let (slot_index, generation) = match decode_handle(handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        #[cfg(test)]
        observe_registry_lock_attempt(handle, TestRegistryOperation::Release);
        let mut registry = lock_registry();
        if registry.released_streams == u64::MAX {
            let slot = &registry.slots[slot_index];
            if slot.stream.is_none() && slot.last_released == handle {
                return STATUS_OK;
            }
            if slot.retired || slot.generation != generation {
                return STATUS_STALE_HANDLE;
            }
            if slot.stream.is_none() {
                return STATUS_STALE_HANDLE;
            }
            return STATUS_INTERNAL;
        }
        {
            let slot = &mut registry.slots[slot_index];
            if slot.stream.is_none() && slot.last_released == handle {
                return STATUS_OK;
            }
            if slot.retired || slot.generation != generation {
                return STATUS_STALE_HANDLE;
            }
            if slot.stream.is_none() {
                return STATUS_STALE_HANDLE;
            }
            let has_outstanding = slot
                .stream
                .as_ref()
                .is_some_and(|stream| stream.outstanding_sequence.is_some());
            if has_outstanding {
                return STATUS_NEEDS_ACK;
            }
            slot.stream = None;
            slot.last_released = handle;
            if slot.generation == u32::MAX {
                slot.retired = true;
            } else {
                slot.generation += 1;
            }
        }
        registry.live_streams = registry.live_streams.saturating_sub(1);
        registry.released_streams += 1;
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_get_registry_stats_v1(
    out_stats: *mut df_spike_registry_stats_v1,
) -> i32 {
    ffi_call(|| {
        if clear_out(out_stats).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        let registry = lock_registry();
        let stats = df_spike_registry_stats_v1 {
            struct_size: size_of::<df_spike_registry_stats_v1>() as u32,
            abi_version: ABI_VERSION,
            live_streams: registry.live_streams,
            max_streams: MAX_STREAMS as u32,
            in_flight_bytes: 0,
            created_streams: registry.created_streams,
            released_streams: registry.released_streams,
            reserved0: 0,
            reserved1: 0,
        };
        if write_out(out_stats, stats).is_err() {
            return STATUS_INVALID_ARGUMENT;
        }
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_arm_allocation_failure_v1(handle: u64) -> i32 {
    ffi_call(|| {
        let mut registry = lock_registry();
        let stream = match stream_mut(&mut registry, handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        stream.fail_next_allocation = true;
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_stream_arm_panic_v1(handle: u64) -> i32 {
    ffi_call(|| {
        let mut registry = lock_registry();
        let stream = match stream_mut(&mut registry, handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        stream.panic_next = true;
        STATUS_OK
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn df_spike_panic_probe_v1() -> i32 {
    ffi_call(|| panic!("DataForge FFI spike panic probe"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier, OnceLock, mpsc};
    use std::thread;
    use std::time::{Duration, Instant};

    static TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    fn test_lock() -> MutexGuard<'static, ()> {
        match TEST_LOCK.get_or_init(|| Mutex::new(())).lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    fn reset() {
        lock_registry().reset();
        *lock_next_registry_hook() = NextRegistryLockHookState::default();
    }

    fn options(total_rows: u64, chunk_rows: u32, chunk_bytes: u32) -> df_spike_stream_options_v1 {
        df_spike_stream_options_v1 {
            struct_size: size_of::<df_spike_stream_options_v1>() as u32,
            abi_version: ABI_VERSION,
            total_rows,
            seed: 7,
            requested_chunk_rows: chunk_rows,
            requested_chunk_bytes: chunk_bytes,
            reserved0: 0,
            reserved1: 0,
        }
    }

    fn create(options: &df_spike_stream_options_v1) -> u64 {
        let mut handle = 0;
        assert_eq!(df_spike_stream_create_v1(options, &mut handle), STATUS_OK);
        assert_ne!(handle, 0);
        handle
    }

    fn assert_no_registry_leaks() {
        let mut stats = df_spike_registry_stats_v1::default();
        assert_eq!(df_spike_get_registry_stats_v1(&mut stats), STATUS_OK);
        assert_eq!(stats.live_streams, 0);
        assert_eq!(stats.in_flight_bytes, 0);
        assert_eq!(stats.created_streams, stats.released_streams);
    }

    fn assert_buffer_unchanged(actual: &[u8], expected: &[u8]) {
        assert!(
            actual
                .iter()
                .zip(expected)
                .all(|(actual_byte, expected_byte)| actual_byte == expected_byte),
            "controlled fault modified the caller-owned destination"
        );
    }

    struct DeterministicRng {
        state: u64,
    }

    impl DeterministicRng {
        fn new(seed: u64) -> Self {
            assert_ne!(seed, 0);
            Self { state: seed }
        }

        fn next_u64(&mut self) -> u64 {
            let mut value = self.state;
            value ^= value << 13;
            value ^= value >> 7;
            value ^= value << 17;
            self.state = value;
            value
        }

        fn below(&mut self, upper_bound: u64) -> u64 {
            assert_ne!(upper_bound, 0);
            self.next_u64() % upper_bound
        }

        fn inclusive_u32(&mut self, minimum: u32, maximum: u32) -> u32 {
            assert!(minimum <= maximum);
            let width = u64::from(maximum - minimum) + 1;
            minimum + self.below(width) as u32
        }
    }

    fn reference_row_length(index: u64) -> u32 {
        if index.is_multiple_of(10) { 24 } else { 40 }
    }

    fn reference_chunk_plan(
        first_row: u64,
        total_rows: u64,
        chunk_rows: u32,
        chunk_bytes: u32,
    ) -> (u32, u32) {
        let remaining = total_rows - first_row;
        let target_rows = u64::from(chunk_rows).min(remaining) as u32;
        let mut row_count = 0_u32;
        let mut byte_count = 0_u32;
        while row_count < target_rows {
            let row_bytes = reference_row_length(first_row + u64::from(row_count));
            if byte_count + row_bytes > chunk_bytes {
                break;
            }
            byte_count += row_bytes;
            row_count += 1;
        }
        (row_count, byte_count)
    }

    fn reference_encoded_rows(first_row: u64, row_count: u32, seed: u64) -> Vec<u8> {
        let mut bytes = Vec::new();
        for offset in 0..row_count {
            let index = first_row + u64::from(offset);
            let is_null = index.is_multiple_of(10);
            bytes.extend_from_slice(&index.to_le_bytes());
            bytes.extend_from_slice(&((index ^ seed) as i64).to_le_bytes());
            bytes.extend_from_slice(&(if is_null { 0_u32 } else { 16_u32 }).to_le_bytes());
            bytes.push(u8::from(index & 1 == 1));
            bytes.push(u8::from(is_null));
            bytes.extend_from_slice(&[0, 0]);
            if !is_null {
                let text = format!("{index:016x}");
                bytes.extend_from_slice(text.as_bytes());
            }
        }
        bytes
    }

    fn reference_checksum(bytes: &[u8]) -> u64 {
        bytes.iter().fold(0xcbf29ce484222325_u64, |hash, byte| {
            (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
        })
    }

    fn secret_like_canary(length: usize) -> Vec<u8> {
        const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut rng = DeterministicRng::new(0x8d26_4f31_b9a7_c5e3);
        (0..length)
            .map(|_| ALPHABET[rng.below(ALPHABET.len() as u64) as usize])
            .collect()
    }

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum ReferenceState {
        Ready,
        Outstanding,
        Completed,
        Cancelled,
        Released,
    }

    struct ReferenceModel {
        total_rows: u64,
        seed: u64,
        chunk_rows: u32,
        chunk_bytes: u32,
        next_row: u64,
        next_sequence: u64,
        outstanding: Option<(u64, u64, u32)>,
        cancel_requested: bool,
        state: ReferenceState,
    }

    impl ReferenceModel {
        fn new(options: &df_spike_stream_options_v1) -> Self {
            Self {
                total_rows: options.total_rows,
                seed: options.seed,
                chunk_rows: options.requested_chunk_rows,
                chunk_bytes: options.requested_chunk_bytes,
                next_row: 0,
                next_sequence: 1,
                outstanding: None,
                cancel_requested: false,
                state: ReferenceState::Ready,
            }
        }

        fn c_state(&self) -> u32 {
            match (self.state, self.cancel_requested) {
                (ReferenceState::Ready, _) => STATE_READY,
                (ReferenceState::Outstanding, true) => STATE_CANCEL_PENDING_ACK,
                (ReferenceState::Outstanding, false) => STATE_OUTSTANDING,
                (ReferenceState::Completed, _) => STATE_COMPLETED,
                (ReferenceState::Cancelled, _) => STATE_CANCELLED,
                (ReferenceState::Released, _) => 0,
            }
        }

        fn required_bytes(&self) -> Option<u32> {
            if self.state != ReferenceState::Ready || self.next_row >= self.total_rows {
                return None;
            }
            Some(
                reference_chunk_plan(
                    self.next_row,
                    self.total_rows,
                    self.chunk_rows,
                    self.chunk_bytes,
                )
                .1,
            )
        }

        fn apply_next(&mut self, destination_capacity: u64) -> (i32, df_spike_chunk_meta_v1) {
            let mut metadata = df_spike_chunk_meta_v1::default();
            if self.state == ReferenceState::Released {
                return (STATUS_STALE_HANDLE, metadata);
            }
            if self.state == ReferenceState::Completed {
                return (STATUS_TERMINAL, metadata);
            }
            if self.state == ReferenceState::Cancelled || self.cancel_requested {
                return (STATUS_CANCELLED, metadata);
            }
            if self.outstanding.is_some() {
                return (STATUS_NEEDS_ACK, metadata);
            }
            if self.next_row >= self.total_rows {
                self.state = ReferenceState::Completed;
                return (STATUS_TERMINAL, metadata);
            }

            let (row_count, byte_count) = reference_chunk_plan(
                self.next_row,
                self.total_rows,
                self.chunk_rows,
                self.chunk_bytes,
            );
            metadata = df_spike_chunk_meta_v1 {
                struct_size: size_of::<df_spike_chunk_meta_v1>() as u32,
                abi_version: ABI_VERSION,
                sequence: 0,
                first_row: self.next_row,
                row_count,
                byte_count: 0,
                encoding_version: ROW_ENCODING_VERSION,
                flags: 0,
                checksum: 0,
                required_capacity: byte_count,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            };
            if destination_capacity < u64::from(byte_count) {
                return (STATUS_BUFFER_TOO_SMALL, metadata);
            }

            let sequence = self.next_sequence;
            self.next_sequence += 1;
            self.outstanding = Some((sequence, self.next_row, row_count));
            self.state = ReferenceState::Outstanding;
            metadata.sequence = sequence;
            metadata.byte_count = byte_count;
            metadata.checksum =
                reference_checksum(&reference_encoded_rows(self.next_row, row_count, self.seed));
            if self.next_row + u64::from(row_count) == self.total_rows {
                metadata.flags = CHUNK_FLAG_LAST;
            }
            (STATUS_OK, metadata)
        }

        fn apply_ack(&mut self, sequence: u64) -> i32 {
            if self.state == ReferenceState::Released {
                return STATUS_STALE_HANDLE;
            }
            let Some((expected_sequence, first_row, row_count)) = self.outstanding else {
                return STATUS_ACK_MISMATCH;
            };
            if sequence != expected_sequence {
                return STATUS_ACK_MISMATCH;
            }
            self.next_row = first_row + u64::from(row_count);
            self.outstanding = None;
            if self.cancel_requested {
                self.state = ReferenceState::Cancelled;
            } else if self.next_row == self.total_rows {
                self.state = ReferenceState::Completed;
            } else {
                self.state = ReferenceState::Ready;
            }
            STATUS_OK
        }

        fn apply_cancel(&mut self) -> (i32, df_spike_cancel_outcome_v1) {
            if self.state == ReferenceState::Released {
                return (STATUS_STALE_HANDLE, df_spike_cancel_outcome_v1::default());
            }
            let mut outcome = df_spike_cancel_outcome_v1 {
                struct_size: size_of::<df_spike_cancel_outcome_v1>() as u32,
                abi_version: ABI_VERSION,
                outcome: 0,
                state: 0,
                reserved0: 0,
                reserved1: 0,
            };
            if self.cancel_requested {
                outcome.outcome = CANCEL_ALREADY_REQUESTED;
            } else if self.state == ReferenceState::Ready {
                self.cancel_requested = true;
                self.state = ReferenceState::Cancelled;
                outcome.outcome = CANCEL_ACCEPTED;
            } else if self.state == ReferenceState::Outstanding {
                self.cancel_requested = true;
                outcome.outcome = CANCEL_PENDING_ACK;
            } else {
                outcome.outcome = CANCEL_TOO_LATE;
            }
            outcome.state = self.c_state();
            (STATUS_OK, outcome)
        }

        fn apply_release(&mut self) -> i32 {
            if self.state == ReferenceState::Released {
                return STATUS_OK;
            }
            if self.outstanding.is_some() {
                return STATUS_NEEDS_ACK;
            }
            self.state = ReferenceState::Released;
            STATUS_OK
        }

        fn snapshot(&self) -> (i32, df_spike_stream_status_v1) {
            if self.state == ReferenceState::Released {
                return (STATUS_STALE_HANDLE, df_spike_stream_status_v1::default());
            }
            (
                STATUS_OK,
                df_spike_stream_status_v1 {
                    struct_size: size_of::<df_spike_stream_status_v1>() as u32,
                    abi_version: ABI_VERSION,
                    state: self.c_state(),
                    terminal_error: 0,
                    next_row: self.next_row,
                    total_rows: self.total_rows,
                    outstanding_sequence: self.outstanding.map_or(0, |(sequence, _, _)| sequence),
                    last_error: 0,
                    reserved0: 0,
                },
            )
        }
    }

    fn assert_status_matches_model(handle: u64, model: &ReferenceModel) {
        let (expected_status, expected_snapshot) = model.snapshot();
        let mut actual_snapshot = df_spike_stream_status_v1 {
            state: u32::MAX,
            ..df_spike_stream_status_v1::default()
        };
        assert_eq!(
            df_spike_stream_get_status_v1(handle, &mut actual_snapshot),
            expected_status
        );
        assert_eq!(actual_snapshot, expected_snapshot);
    }

    fn arm_next_registry_lock_pause(handle: u64) {
        let mut state = lock_next_registry_hook();
        *state = NextRegistryLockHookState {
            target_handle: handle,
            armed: true,
            ..NextRegistryLockHookState::default()
        };
    }

    fn wait_for_registry_hook(predicate: impl Fn(&NextRegistryLockHookState) -> bool) {
        let (_, condition) = next_registry_lock_hook();
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut state = lock_next_registry_hook();
        while !predicate(&state) {
            let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                panic!("timed out waiting for the deterministic registry-lock test hook");
            };
            let (next_state, timeout) = match condition.wait_timeout(state, remaining) {
                Ok(result) => result,
                Err(poisoned) => poisoned.into_inner(),
            };
            state = next_state;
            if timeout.timed_out() && !predicate(&state) {
                panic!("timed out waiting for the deterministic registry-lock test hook");
            }
        }
    }

    fn resume_paused_next() {
        let (_, condition) = next_registry_lock_hook();
        let mut state = lock_next_registry_hook();
        state.resume_next = true;
        condition.notify_all();
    }

    #[test]
    fn deterministic_random_chunk_boundaries_preserve_encoding_and_guards() {
        let _guard = test_lock();
        let mut rng = DeterministicRng::new(0x1f2e_3d4c_5b6a_7988);
        for case in 0..96_u32 {
            reset();
            let total_rows = if case % 11 == 0 {
                0
            } else {
                rng.inclusive_u32(1, 2_500) as u64
            };
            let chunk_rows = rng.inclusive_u32(1, 1_000);
            let chunk_bytes = rng.inclusive_u32(40, 4_096);
            let mut stream_options = options(total_rows, chunk_rows, chunk_bytes);
            stream_options.seed = rng.next_u64();
            let handle = create(&stream_options);
            let mut first_row = 0_u64;
            let mut expected_sequence = 1_u64;

            loop {
                if first_row >= total_rows {
                    let mut terminal_meta = df_spike_chunk_meta_v1 {
                        sequence: u64::MAX,
                        ..df_spike_chunk_meta_v1::default()
                    };
                    let mut terminal_buffer = [0_u8; 64];
                    assert_eq!(
                        df_spike_stream_next_v1(
                            handle,
                            terminal_buffer.as_mut_ptr(),
                            terminal_buffer.len() as u64,
                            &mut terminal_meta,
                        ),
                        STATUS_TERMINAL
                    );
                    assert_eq!(terminal_meta, df_spike_chunk_meta_v1::default());
                    break;
                }

                let (expected_rows, expected_bytes) =
                    reference_chunk_plan(first_row, total_rows, chunk_rows, chunk_bytes);
                assert!(expected_rows > 0);

                if rng.below(3) == 0 {
                    let mut undersized = secret_like_canary(expected_bytes as usize + 32);
                    let before = undersized.clone();
                    let mut metadata = df_spike_chunk_meta_v1::default();
                    assert_eq!(
                        df_spike_stream_next_v1(
                            handle,
                            undersized.as_mut_ptr(),
                            u64::from(expected_bytes - 1),
                            &mut metadata,
                        ),
                        STATUS_BUFFER_TOO_SMALL
                    );
                    assert_buffer_unchanged(&undersized, &before);
                    assert_eq!(metadata.row_count, expected_rows);
                    assert_eq!(metadata.byte_count, 0);
                    assert_eq!(metadata.required_capacity, expected_bytes);
                    assert_status_matches_model(
                        handle,
                        &ReferenceModel {
                            total_rows,
                            seed: stream_options.seed,
                            chunk_rows,
                            chunk_bytes,
                            next_row: first_row,
                            next_sequence: expected_sequence,
                            outstanding: None,
                            cancel_requested: false,
                            state: ReferenceState::Ready,
                        },
                    );
                }

                let prefix = rng.inclusive_u32(1, 31) as usize;
                let suffix = rng.inclusive_u32(1, 31) as usize;
                let extra_capacity = rng.inclusive_u32(0, 63) as usize;
                let capacity = expected_bytes as usize + extra_capacity;
                let mut destination = secret_like_canary(prefix + capacity + suffix);
                let before = destination.clone();
                let mut metadata = df_spike_chunk_meta_v1::default();
                assert_eq!(
                    df_spike_stream_next_v1(
                        handle,
                        destination[prefix..].as_mut_ptr(),
                        capacity as u64,
                        &mut metadata,
                    ),
                    STATUS_OK
                );
                let expected_bytes_data =
                    reference_encoded_rows(first_row, expected_rows, stream_options.seed);
                assert_eq!(metadata.sequence, expected_sequence);
                assert_eq!(metadata.first_row, first_row);
                assert_eq!(metadata.row_count, expected_rows);
                assert_eq!(metadata.byte_count, expected_bytes);
                assert_eq!(metadata.required_capacity, expected_bytes);
                assert_eq!(metadata.checksum, reference_checksum(&expected_bytes_data));
                assert_eq!(
                    metadata.flags,
                    if first_row + u64::from(expected_rows) == total_rows {
                        CHUNK_FLAG_LAST
                    } else {
                        0
                    }
                );
                assert!(
                    destination[prefix..prefix + expected_bytes as usize]
                        .iter()
                        .zip(&expected_bytes_data)
                        .all(|(actual_byte, expected_byte)| actual_byte == expected_byte),
                    "deterministic row encoding changed"
                );
                assert_buffer_unchanged(&destination[..prefix], &before[..prefix]);
                assert_buffer_unchanged(
                    &destination[prefix + expected_bytes as usize..],
                    &before[prefix + expected_bytes as usize..],
                );

                if rng.below(2) == 0 {
                    let mut duplicate_destination = secret_like_canary(128);
                    let duplicate_before = duplicate_destination.clone();
                    let mut duplicate_meta = df_spike_chunk_meta_v1 {
                        sequence: u64::MAX,
                        ..df_spike_chunk_meta_v1::default()
                    };
                    assert_eq!(
                        df_spike_stream_next_v1(
                            handle,
                            duplicate_destination.as_mut_ptr(),
                            duplicate_destination.len() as u64,
                            &mut duplicate_meta,
                        ),
                        STATUS_NEEDS_ACK
                    );
                    assert_eq!(duplicate_meta, df_spike_chunk_meta_v1::default());
                    assert_buffer_unchanged(&duplicate_destination, &duplicate_before);
                }
                if rng.below(2) == 0 {
                    assert_eq!(
                        df_spike_stream_ack_v1(handle, expected_sequence + 1),
                        STATUS_ACK_MISMATCH
                    );
                }
                assert_eq!(df_spike_stream_ack_v1(handle, expected_sequence), STATUS_OK);
                first_row += u64::from(expected_rows);
                expected_sequence += 1;
            }
            assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
            assert_no_registry_leaks();
        }
    }

    #[test]
    fn deterministic_random_state_transitions_match_reference_model() {
        let _guard = test_lock();
        let mut rng = DeterministicRng::new(0x9a8b_7c6d_5e4f_3021);
        let mut coverage = 0_u32;
        const SAW_OK_NEXT: u32 = 1 << 0;
        const SAW_BUFFER_TOO_SMALL: u32 = 1 << 1;
        const SAW_NEEDS_ACK: u32 = 1 << 2;
        const SAW_ACK_MISMATCH: u32 = 1 << 3;
        const SAW_CANCEL_ACCEPTED: u32 = 1 << 4;
        const SAW_CANCEL_PENDING: u32 = 1 << 5;
        const SAW_CANCEL_ALREADY: u32 = 1 << 6;
        const SAW_CANCELLED: u32 = 1 << 7;
        const SAW_TERMINAL: u32 = 1 << 8;
        const SAW_RELEASE_NEEDS_ACK: u32 = 1 << 9;
        const SAW_STALE: u32 = 1 << 10;

        for case in 0..256_u32 {
            reset();
            let total_rows = if case % 13 == 0 {
                0
            } else {
                rng.inclusive_u32(1, 180) as u64
            };
            let chunk_rows = rng.inclusive_u32(1, 24);
            let chunk_bytes = rng.inclusive_u32(40, 512);
            let mut stream_options = options(total_rows, chunk_rows, chunk_bytes);
            stream_options.seed = rng.next_u64();
            let handle = create(&stream_options);
            let mut model = ReferenceModel::new(&stream_options);
            let mut destination = vec![0_u8; 1_024];

            for step in 0..96_u32 {
                if model.state == ReferenceState::Released {
                    let mut metadata = df_spike_chunk_meta_v1::default();
                    let expected_next = model.apply_next(destination.len() as u64);
                    let actual_next = df_spike_stream_next_v1(
                        handle,
                        destination.as_mut_ptr(),
                        destination.len() as u64,
                        &mut metadata,
                    );
                    assert_eq!(actual_next, expected_next.0);
                    assert_eq!(metadata, expected_next.1);
                    coverage |= SAW_STALE;
                    let expected_cancel = model.apply_cancel();
                    let mut outcome = df_spike_cancel_outcome_v1::default();
                    let actual_cancel = df_spike_stream_cancel_v1(handle, &mut outcome);
                    assert_eq!(actual_cancel, expected_cancel.0);
                    assert_eq!(outcome, expected_cancel.1);
                    assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
                    break;
                }

                let action = match model.state {
                    ReferenceState::Ready => {
                        let roll = rng.below(100);
                        if roll < 54 || (case % 4 == 0 && step < 70) {
                            0_u8
                        } else if roll < 68 {
                            1
                        } else if roll < 78 {
                            2
                        } else if roll < 88 {
                            3
                        } else {
                            4
                        }
                    }
                    ReferenceState::Outstanding => match rng.below(100) {
                        0..=18 => 0,
                        19..=34 => 1,
                        35..=48 => 2,
                        49..=64 => 3,
                        65..=78 => 4,
                        _ => 5,
                    },
                    ReferenceState::Completed | ReferenceState::Cancelled => match rng.below(100) {
                        0..=20 => 0,
                        21..=40 => 1,
                        41..=62 => 2,
                        _ => 4,
                    },
                    ReferenceState::Released => unreachable!(),
                };

                match action {
                    0 => {
                        let capacity = if let Some(required) = model.required_bytes() {
                            if rng.below(4) == 0 {
                                u64::from(required.saturating_sub(1))
                            } else {
                                destination.len() as u64
                            }
                        } else {
                            destination.len() as u64
                        };
                        let mut metadata = df_spike_chunk_meta_v1 {
                            sequence: u64::MAX,
                            ..df_spike_chunk_meta_v1::default()
                        };
                        let expected = model.apply_next(capacity);
                        let actual = df_spike_stream_next_v1(
                            handle,
                            destination.as_mut_ptr(),
                            capacity,
                            &mut metadata,
                        );
                        assert_eq!(actual, expected.0);
                        assert_eq!(metadata, expected.1);
                        match actual {
                            STATUS_OK => coverage |= SAW_OK_NEXT,
                            STATUS_BUFFER_TOO_SMALL => coverage |= SAW_BUFFER_TOO_SMALL,
                            STATUS_NEEDS_ACK => coverage |= SAW_NEEDS_ACK,
                            STATUS_CANCELLED => coverage |= SAW_CANCELLED,
                            STATUS_TERMINAL => coverage |= SAW_TERMINAL,
                            STATUS_STALE_HANDLE => coverage |= SAW_STALE,
                            _ => {}
                        }
                    }
                    1 => {
                        let sequence = model
                            .outstanding
                            .map_or(rng.next_u64(), |(sequence, _, _)| sequence);
                        let expected = model.apply_ack(sequence);
                        let actual = df_spike_stream_ack_v1(handle, sequence);
                        assert_eq!(actual, expected);
                        if actual == STATUS_ACK_MISMATCH {
                            coverage |= SAW_ACK_MISMATCH;
                        }
                    }
                    2 => {
                        let sequence = model
                            .outstanding
                            .map_or(1, |(sequence, _, _)| sequence.saturating_add(1));
                        let expected = model.apply_ack(sequence);
                        let actual = df_spike_stream_ack_v1(handle, sequence);
                        assert_eq!(actual, expected);
                        if actual == STATUS_ACK_MISMATCH {
                            coverage |= SAW_ACK_MISMATCH;
                        }
                    }
                    3 => {
                        let expected = model.apply_cancel();
                        let mut outcome = df_spike_cancel_outcome_v1 {
                            outcome: u32::MAX,
                            ..df_spike_cancel_outcome_v1::default()
                        };
                        let actual = df_spike_stream_cancel_v1(handle, &mut outcome);
                        assert_eq!(actual, expected.0);
                        assert_eq!(outcome, expected.1);
                        match outcome.outcome {
                            CANCEL_ACCEPTED => coverage |= SAW_CANCEL_ACCEPTED,
                            CANCEL_PENDING_ACK => coverage |= SAW_CANCEL_PENDING,
                            CANCEL_ALREADY_REQUESTED => coverage |= SAW_CANCEL_ALREADY,
                            _ => {}
                        }
                    }
                    4 => {
                        let expected = model.apply_release();
                        let actual = df_spike_stream_release_v1(handle);
                        assert_eq!(actual, expected);
                        if actual == STATUS_NEEDS_ACK {
                            coverage |= SAW_RELEASE_NEEDS_ACK;
                        }
                    }
                    5 => {
                        let sequence = model.outstanding.map_or(1, |(sequence, _, _)| sequence);
                        let expected = model.apply_ack(sequence);
                        let actual = df_spike_stream_ack_v1(handle, sequence);
                        assert_eq!(actual, expected);
                        if actual == STATUS_ACK_MISMATCH {
                            coverage |= SAW_ACK_MISMATCH;
                        }
                    }
                    _ => unreachable!(),
                }
                assert_status_matches_model(handle, &model);
            }

            if model.state != ReferenceState::Released {
                if let Some((sequence, _, _)) = model.outstanding {
                    assert_eq!(
                        df_spike_stream_ack_v1(handle, sequence),
                        model.apply_ack(sequence)
                    );
                }
                assert_eq!(df_spike_stream_release_v1(handle), model.apply_release());
            }
            assert_no_registry_leaks();
        }

        let required_coverage = SAW_OK_NEXT
            | SAW_BUFFER_TOO_SMALL
            | SAW_NEEDS_ACK
            | SAW_ACK_MISMATCH
            | SAW_CANCEL_ACCEPTED
            | SAW_CANCEL_PENDING
            | SAW_CANCEL_ALREADY
            | SAW_CANCELLED
            | SAW_TERMINAL
            | SAW_RELEASE_NEEDS_ACK
            | SAW_STALE;
        assert_eq!(coverage & required_coverage, required_coverage);
    }

    #[test]
    fn secret_like_destination_canary_survives_controlled_faults_without_logging() {
        let _guard = test_lock();
        reset();

        let handle = create(&options(2, 1, 40));
        let mut allocation_destination = secret_like_canary(128);
        let allocation_before = allocation_destination.clone();
        let mut metadata = df_spike_chunk_meta_v1 {
            sequence: u64::MAX,
            ..df_spike_chunk_meta_v1::default()
        };
        assert_eq!(df_spike_stream_arm_allocation_failure_v1(handle), STATUS_OK);
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                allocation_destination.as_mut_ptr(),
                allocation_destination.len() as u64,
                &mut metadata,
            ),
            STATUS_ALLOCATION_FAILED
        );
        assert_eq!(metadata, df_spike_chunk_meta_v1::default());
        assert_buffer_unchanged(&allocation_destination, &allocation_before);

        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                allocation_destination.as_mut_ptr(),
                allocation_destination.len() as u64,
                &mut metadata,
            ),
            STATUS_OK
        );
        assert_eq!(df_spike_stream_ack_v1(handle, metadata.sequence), STATUS_OK);
        assert_eq!(df_spike_stream_arm_panic_v1(handle), STATUS_OK);

        let mut panic_destination = secret_like_canary(128);
        let panic_before = panic_destination.clone();
        metadata = df_spike_chunk_meta_v1 {
            sequence: u64::MAX,
            ..df_spike_chunk_meta_v1::default()
        };
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                panic_destination.as_mut_ptr(),
                panic_destination.len() as u64,
                &mut metadata,
            ),
            STATUS_PANIC
        );
        assert_eq!(metadata, df_spike_chunk_meta_v1::default());
        assert_buffer_unchanged(&panic_destination, &panic_before);
        let mut failed_status = df_spike_stream_status_v1::default();
        assert_eq!(
            df_spike_stream_get_status_v1(handle, &mut failed_status),
            STATUS_OK
        );
        assert_eq!(failed_status.state, STATE_FAILED);
        assert_eq!(failed_status.terminal_error, STATUS_PANIC as u32);
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);

        let undersized_handle = create(&options(1, 1, 40));
        let mut undersized_destination = secret_like_canary(128);
        let undersized_before = undersized_destination.clone();
        metadata = df_spike_chunk_meta_v1::default();
        assert_eq!(
            df_spike_stream_next_v1(
                undersized_handle,
                undersized_destination.as_mut_ptr(),
                1,
                &mut metadata,
            ),
            STATUS_BUFFER_TOO_SMALL
        );
        assert_buffer_unchanged(&undersized_destination, &undersized_before);
        assert_eq!(
            df_spike_stream_ack_v1(undersized_handle, 1),
            STATUS_ACK_MISMATCH
        );
        assert_eq!(df_spike_stream_release_v1(undersized_handle), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn same_handle_next_cancel_release_races_are_linearizable() {
        let _guard = test_lock();
        for _iteration in 0..64 {
            reset();
            let handle = create(&options(4, 2, 80));
            let start = Arc::new(Barrier::new(4));
            let (next_sender, next_receiver) = mpsc::channel();
            let (cancel_sender, cancel_receiver) = mpsc::channel();
            let (release_sender, release_receiver) = mpsc::channel();

            let next_start = Arc::clone(&start);
            let next_thread = thread::spawn(move || {
                let mut destination = [0_u8; 128];
                let mut metadata = df_spike_chunk_meta_v1::default();
                next_start.wait();
                let status = df_spike_stream_next_v1(
                    handle,
                    destination.as_mut_ptr(),
                    destination.len() as u64,
                    &mut metadata,
                );
                let _ = next_sender.send((status, metadata));
            });

            let cancel_start = Arc::clone(&start);
            let cancel_thread = thread::spawn(move || {
                let mut outcome = df_spike_cancel_outcome_v1::default();
                cancel_start.wait();
                let status = df_spike_stream_cancel_v1(handle, &mut outcome);
                let _ = cancel_sender.send((status, outcome));
            });

            let release_start = Arc::clone(&start);
            let release_thread = thread::spawn(move || {
                release_start.wait();
                let status = df_spike_stream_release_v1(handle);
                let _ = release_sender.send(status);
            });

            start.wait();
            let next_result = match next_receiver.recv_timeout(Duration::from_secs(5)) {
                Ok(result) => result,
                Err(error) => panic!("next race worker did not finish: {error}"),
            };
            let cancel_result = match cancel_receiver.recv_timeout(Duration::from_secs(5)) {
                Ok(result) => result,
                Err(error) => panic!("cancel race worker did not finish: {error}"),
            };
            let release_result = match release_receiver.recv_timeout(Duration::from_secs(5)) {
                Ok(result) => result,
                Err(error) => panic!("release race worker did not finish: {error}"),
            };
            assert!(next_thread.join().is_ok());
            assert!(cancel_thread.join().is_ok());
            assert!(release_thread.join().is_ok());

            match next_result.0 {
                STATUS_OK => {
                    assert_eq!(cancel_result.0, STATUS_OK);
                    assert_eq!(cancel_result.1.outcome, CANCEL_PENDING_ACK);
                    assert_eq!(cancel_result.1.state, STATE_CANCEL_PENDING_ACK);
                    assert_eq!(release_result, STATUS_NEEDS_ACK);
                    assert_eq!(
                        df_spike_stream_ack_v1(handle, next_result.1.sequence),
                        STATUS_OK
                    );
                    assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
                }
                STATUS_CANCELLED => {
                    assert_eq!(cancel_result.0, STATUS_OK);
                    assert_eq!(cancel_result.1.outcome, CANCEL_ACCEPTED);
                    assert_eq!(cancel_result.1.state, STATE_CANCELLED);
                    assert_eq!(release_result, STATUS_OK);
                }
                STATUS_STALE_HANDLE => {
                    assert_eq!(release_result, STATUS_OK);
                    assert!(cancel_result.0 == STATUS_OK || cancel_result.0 == STATUS_STALE_HANDLE);
                    if cancel_result.0 == STATUS_OK {
                        assert_eq!(cancel_result.1.outcome, CANCEL_ACCEPTED);
                    } else {
                        assert_eq!(cancel_result.1, df_spike_cancel_outcome_v1::default());
                    }
                }
                status => panic!("unexpected next race status: {status}"),
            }
            assert_no_registry_leaks();
        }
    }

    #[test]
    fn cancel_and_release_attempts_wait_while_next_holds_registry_lock() {
        let _guard = test_lock();
        reset();
        let handle = create(&options(4, 2, 80));
        arm_next_registry_lock_pause(handle);

        let (next_sender, next_receiver) = mpsc::channel();
        let next_thread = thread::spawn(move || {
            let mut destination = [0_u8; 128];
            let mut metadata = df_spike_chunk_meta_v1::default();
            let status = df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut metadata,
            );
            let _ = next_sender.send((status, metadata));
        });
        wait_for_registry_hook(|state| state.next_holds_registry_lock);

        let (cancel_sender, cancel_receiver) = mpsc::channel();
        let cancel_thread = thread::spawn(move || {
            let mut outcome = df_spike_cancel_outcome_v1::default();
            let status = df_spike_stream_cancel_v1(handle, &mut outcome);
            let _ = cancel_sender.send((status, outcome));
        });
        let (release_sender, release_receiver) = mpsc::channel();
        let release_thread = thread::spawn(move || {
            let status = df_spike_stream_release_v1(handle);
            let _ = release_sender.send(status);
        });
        wait_for_registry_hook(|state| {
            state.next_holds_registry_lock && state.cancel_attempted && state.release_attempted
        });

        assert!(matches!(
            next_receiver.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        assert!(matches!(
            cancel_receiver.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        assert!(matches!(
            release_receiver.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));

        resume_paused_next();
        let next_result = match next_receiver.recv_timeout(Duration::from_secs(5)) {
            Ok(result) => result,
            Err(error) => panic!("paused next worker did not finish: {error}"),
        };
        let cancel_result = match cancel_receiver.recv_timeout(Duration::from_secs(5)) {
            Ok(result) => result,
            Err(error) => panic!("paused cancel worker did not finish: {error}"),
        };
        let release_result = match release_receiver.recv_timeout(Duration::from_secs(5)) {
            Ok(result) => result,
            Err(error) => panic!("paused release worker did not finish: {error}"),
        };
        assert!(next_thread.join().is_ok());
        assert!(cancel_thread.join().is_ok());
        assert!(release_thread.join().is_ok());

        assert_eq!(next_result.0, STATUS_OK);
        assert_eq!(cancel_result.0, STATUS_OK);
        assert_eq!(cancel_result.1.outcome, CANCEL_PENDING_ACK);
        assert_eq!(cancel_result.1.state, STATE_CANCEL_PENDING_ACK);
        assert_eq!(release_result, STATUS_NEEDS_ACK);
        assert_eq!(
            df_spike_stream_ack_v1(handle, next_result.1.sequence),
            STATUS_OK
        );
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn layout_and_handshake_are_stable() {
        let _guard = test_lock();
        reset();
        let request = df_spike_abi_request_v1 {
            struct_size: size_of::<df_spike_abi_request_v1>() as u32,
            abi_version: ABI_VERSION,
            required_features: FEATURE_MASK,
            optional_features: u64::MAX,
            reserved0: 0,
            reserved1: 0,
        };
        let mut response = df_spike_abi_info_v1::default();
        assert_eq!(
            df_spike_abi_negotiate_v1(&request, &mut response),
            STATUS_OK
        );
        assert_eq!(response.supported_features, FEATURE_MASK);
        assert_eq!(response.max_streams, MAX_STREAMS as u32);
        assert_eq!(response.max_chunk_rows, MAX_CHUNK_ROWS);
        assert_eq!(response.max_chunk_bytes, MAX_CHUNK_BYTES);
        let mut mismatch = request;
        mismatch.abi_version = ABI_VERSION + 1;
        assert_eq!(
            df_spike_abi_negotiate_v1(&mismatch, &mut response),
            STATUS_ABI_MISMATCH
        );
        let mut unsupported = request;
        unsupported.required_features = 1 << 63;
        assert_eq!(
            df_spike_abi_negotiate_v1(&unsupported, &mut response),
            STATUS_UNSUPPORTED_FEATURE
        );
        assert_no_registry_leaks();
    }

    #[test]
    fn pull_ack_enforces_byte_and_row_caps() {
        let _guard = test_lock();
        reset();
        let options = options(10, 2, 40);
        let handle = create(&options);
        let mut destination = [0_u8; 128];
        let mut meta = df_spike_chunk_meta_v1::default();
        assert_eq!(
            df_spike_stream_next_v1(handle, destination.as_mut_ptr(), 1, &mut meta),
            STATUS_BUFFER_TOO_SMALL
        );
        assert_eq!(meta.required_capacity, 24);
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_OK
        );
        assert_eq!(meta.row_count, 1);
        let sequence = meta.sequence;
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_NEEDS_ACK
        );
        assert_eq!(df_spike_stream_ack_v1(handle, sequence), STATUS_OK);
        assert_eq!(
            df_spike_stream_ack_v1(handle, sequence),
            STATUS_ACK_MISMATCH
        );
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn cancellation_waits_for_outstanding_ack() {
        let _guard = test_lock();
        reset();
        let options = options(4, 2, 80);
        let handle = create(&options);
        let mut destination = [0_u8; 128];
        let mut meta = df_spike_chunk_meta_v1::default();
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_OK
        );
        let sequence = meta.sequence;
        let mut outcome = df_spike_cancel_outcome_v1::default();
        assert_eq!(df_spike_stream_cancel_v1(handle, &mut outcome), STATUS_OK);
        assert_eq!(outcome.outcome, CANCEL_PENDING_ACK);
        assert_eq!(outcome.state, STATE_CANCEL_PENDING_ACK);
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_CANCELLED
        );
        assert_eq!(df_spike_stream_ack_v1(handle, sequence), STATUS_OK);
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn stale_handles_cannot_cross_slot_reuse() {
        let _guard = test_lock();
        reset();
        let never_issued = (1_u64 << 32) | 1;
        assert_eq!(
            df_spike_stream_release_v1(never_issued),
            STATUS_STALE_HANDLE
        );
        let first = create(&options(1, 1, 40));
        assert_eq!(df_spike_stream_release_v1(first), STATUS_OK);
        assert_eq!(df_spike_stream_release_v1(first), STATUS_OK);
        let next_generation_before_create = first + (1_u64 << 32);
        assert_eq!(
            df_spike_stream_release_v1(next_generation_before_create),
            STATUS_STALE_HANDLE
        );
        let second = create(&options(1, 1, 40));
        assert_ne!(first, second);
        let mut status = df_spike_stream_status_v1::default();
        assert_eq!(
            df_spike_stream_get_status_v1(first, &mut status),
            STATUS_STALE_HANDLE
        );
        assert_eq!(df_spike_stream_release_v1(first), STATUS_STALE_HANDLE);
        assert_eq!(df_spike_stream_release_v1(second), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn malformed_inputs_are_zeroed_and_never_advance_state() {
        let _guard = test_lock();
        reset();
        let request = df_spike_abi_request_v1 {
            struct_size: size_of::<df_spike_abi_request_v1>() as u32,
            abi_version: ABI_VERSION,
            required_features: 0,
            optional_features: 0,
            reserved0: 0,
            reserved1: 0,
        };
        let mut info = df_spike_abi_info_v1 {
            supported_features: u64::MAX,
            ..df_spike_abi_info_v1::default()
        };
        assert_eq!(
            df_spike_abi_negotiate_v1(ptr::null(), &mut info),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(info, df_spike_abi_info_v1::default());
        assert_eq!(
            df_spike_abi_negotiate_v1(&request, ptr::null_mut()),
            STATUS_INVALID_ARGUMENT
        );

        let mut handle = 42;
        assert_eq!(
            df_spike_stream_create_v1(ptr::null(), &mut handle),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(handle, 0);
        let mut invalid_options = options(1, 1, 40);
        invalid_options.reserved0 = 1;
        assert_eq!(
            df_spike_stream_create_v1(&invalid_options, &mut handle),
            STATUS_ABI_MISMATCH
        );
        let extreme_options = options(u64::MAX, 1, 40);
        assert_eq!(
            df_spike_stream_create_v1(&extreme_options, &mut handle),
            STATUS_LIMIT_EXCEEDED
        );

        let handle = create(&options(1, 1, 40));
        let mut metadata = df_spike_chunk_meta_v1 {
            sequence: u64::MAX,
            ..df_spike_chunk_meta_v1::default()
        };
        let mut guarded = [0xa5_u8; 64];
        assert_eq!(
            df_spike_stream_next_v1(handle, ptr::null_mut(), 40, &mut metadata),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(metadata, df_spike_chunk_meta_v1::default());
        let destination = guarded[8..].as_mut_ptr();
        assert_eq!(
            df_spike_stream_next_v1(handle, destination, 40, &mut metadata),
            STATUS_OK
        );
        assert!(guarded[..8].iter().all(|byte| *byte == 0xa5));
        assert!(guarded[48..].iter().all(|byte| *byte == 0xa5));
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_NEEDS_ACK);
        let sequence = metadata.sequence;
        assert_eq!(
            df_spike_stream_ack_v1(handle, sequence + 1),
            STATUS_ACK_MISMATCH
        );
        assert_eq!(df_spike_stream_ack_v1(handle, sequence), STATUS_OK);
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn panic_and_allocation_failures_are_contained() {
        let _guard = test_lock();
        reset();
        assert_eq!(df_spike_panic_probe_v1(), STATUS_PANIC);
        let handle = create(&options(2, 1, 40));
        assert_eq!(df_spike_stream_arm_allocation_failure_v1(handle), STATUS_OK);
        let mut destination = [0_u8; 64];
        let mut meta = df_spike_chunk_meta_v1::default();
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_ALLOCATION_FAILED
        );
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_OK
        );
        assert_eq!(df_spike_stream_ack_v1(handle, meta.sequence), STATUS_OK);
        assert_eq!(df_spike_stream_arm_panic_v1(handle), STATUS_OK);
        assert_eq!(
            df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta
            ),
            STATUS_PANIC
        );
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_no_registry_leaks();
    }

    #[test]
    fn registry_is_bounded_and_concurrent_calls_are_linearizable() {
        let _guard = test_lock();
        reset();
        let handles: Vec<u64> = (0..MAX_STREAMS)
            .map(|_| create(&options(0, 1, 40)))
            .collect();
        let mut extra = 0;
        let options = options(0, 1, 40);
        assert_eq!(
            df_spike_stream_create_v1(&options, &mut extra),
            STATUS_REGISTRY_FULL
        );
        let threads: Vec<_> = handles
            .into_iter()
            .map(|handle| thread::spawn(move || df_spike_stream_release_v1(handle)))
            .collect();
        for thread in threads {
            assert_eq!(thread.join().unwrap_or(STATUS_INTERNAL), STATUS_OK);
        }
        let mut stats = df_spike_registry_stats_v1::default();
        assert_eq!(df_spike_get_registry_stats_v1(&mut stats), STATUS_OK);
        assert_eq!(stats.live_streams, 0);
        assert_eq!(stats.created_streams, stats.released_streams);
        assert_no_registry_leaks();
    }

    #[test]
    fn one_million_rows_can_be_consumed_without_retained_chunk_memory() {
        let _guard = test_lock();
        reset();
        let handle = create(&options(1_000_000, 1_000, MAX_CHUNK_BYTES));
        let mut destination = vec![0_u8; MAX_CHUNK_BYTES as usize];
        let mut meta = df_spike_chunk_meta_v1::default();
        let mut rows = 0_u64;
        let mut digest = 0_u64;
        loop {
            let status = df_spike_stream_next_v1(
                handle,
                destination.as_mut_ptr(),
                destination.len() as u64,
                &mut meta,
            );
            if status == STATUS_TERMINAL {
                break;
            }
            assert_eq!(status, STATUS_OK);
            rows += u64::from(meta.row_count);
            digest ^= meta.checksum;
            assert_eq!(df_spike_stream_ack_v1(handle, meta.sequence), STATUS_OK);
        }
        assert_eq!(rows, 1_000_000);
        assert_ne!(digest, 0);
        assert_eq!(df_spike_stream_release_v1(handle), STATUS_OK);
        assert_no_registry_leaks();
    }
}
