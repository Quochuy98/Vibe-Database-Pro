#![deny(unsafe_op_in_unsafe_fn)]

use std::array;
use std::mem::size_of;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::{Mutex, MutexGuard, OnceLock};

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

const _: [(); 32] = [(); size_of::<df_spike_abi_request_v1>()];
const _: [(); 40] = [(); size_of::<df_spike_abi_info_v1>()];
const _: [(); 40] = [(); size_of::<df_spike_stream_options_v1>()];
const _: [(); 64] = [(); size_of::<df_spike_chunk_meta_v1>()];
const _: [(); 48] = [(); size_of::<df_spike_stream_status_v1>()];
const _: [(); 24] = [(); size_of::<df_spike_cancel_outcome_v1>()];
const _: [(); 48] = [(); size_of::<df_spike_registry_stats_v1>()];

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
        let mut registry = lock_registry();
        if registry.released_streams == u64::MAX {
            let slot = &registry.slots[slot_index];
            if slot.stream.is_none() && slot.last_released == handle {
                return STATUS_OK;
            }
            if slot.retired || slot.generation != generation {
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
    use std::sync::OnceLock;
    use std::thread;

    static TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    fn test_lock() -> MutexGuard<'static, ()> {
        match TEST_LOCK.get_or_init(|| Mutex::new(())).lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    fn reset() {
        lock_registry().reset();
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
    }

    #[test]
    fn stale_handles_cannot_cross_slot_reuse() {
        let _guard = test_lock();
        reset();
        let first = create(&options(1, 1, 40));
        assert_eq!(df_spike_stream_release_v1(first), STATUS_OK);
        assert_eq!(df_spike_stream_release_v1(first), STATUS_OK);
        let second = create(&options(1, 1, 40));
        assert_ne!(first, second);
        let mut status = df_spike_stream_status_v1::default();
        assert_eq!(
            df_spike_stream_get_status_v1(first, &mut status),
            STATUS_STALE_HANDLE
        );
        assert_eq!(df_spike_stream_release_v1(first), STATUS_STALE_HANDLE);
        assert_eq!(df_spike_stream_release_v1(second), STATUS_OK);
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
    }
}
