use zeroize::Zeroize;

pub struct WasmSecureBuffer {
    data: Vec<u8>,
}

impl WasmSecureBuffer {
    /// Allocates a standard Vec which will be zeroized on drop.
    /// Note: Browser sandboxes do not expose mlock() or mprotect() syscalls.
    /// The page locking and guard page protections are documented no-ops on Wasm.
    pub fn new(len: usize) -> Self {
        WasmSecureBuffer {
            data: vec![0u8; len],
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.data
    }

    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        &mut self.data
    }

    pub fn len(&self) -> usize {
        self.data.len()
    }
}

impl Drop for WasmSecureBuffer {
    fn drop(&mut self) {
        // Universal zeroize behavior works on Wasm
        self.data.zeroize();
    }
}
