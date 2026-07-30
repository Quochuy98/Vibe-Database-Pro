//! Disposable DF-M0-006 nested-library probe.
//!
//! This crate deliberately exports one fixed value. It is not a production
//! FFI contract and must be deleted with the rest of the spike.

const PROBE_ABI_VERSION: u32 = 0x0001_0000;

/// Returns the fixed distribution-probe ABI marker.
#[unsafe(no_mangle)]
pub extern "C" fn dataforge_distribution_core_version() -> u32 {
    PROBE_ABI_VERSION
}

#[cfg(test)]
mod tests {
    use super::{PROBE_ABI_VERSION, dataforge_distribution_core_version};

    #[test]
    fn exported_marker_is_stable_for_the_spike() {
        assert_eq!(dataforge_distribution_core_version(), PROBE_ABI_VERSION);
    }
}
