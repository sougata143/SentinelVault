#[cfg(unix)]
mod native;

#[cfg(not(unix))]
mod wasm;

pub struct SecureBuffer {
    #[cfg(unix)]
    inner: native::NativeSecureBuffer,
    #[cfg(not(unix))]
    inner: wasm::WasmSecureBuffer,
}

impl SecureBuffer {
    /// Allocates a new SecureBuffer of the given length.
    pub fn new(len: usize) -> Self {
        #[cfg(unix)]
        {
            SecureBuffer {
                inner: native::NativeSecureBuffer::new(len),
            }
        }
        #[cfg(not(unix))]
        {
            SecureBuffer {
                inner: wasm::WasmSecureBuffer::new(len),
            }
        }
    }

    /// Returns a read-only slice of the secure buffer.
    pub fn as_slice(&self) -> &[u8] {
        self.inner.as_slice()
    }

    /// Returns a mutable slice of the secure buffer.
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        self.inner.as_mut_slice()
    }

    /// Returns the length of the secure buffer.
    pub fn len(&self) -> usize {
        self.inner.len()
    }
}
