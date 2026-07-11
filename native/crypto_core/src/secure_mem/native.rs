use std::ptr;
use zeroize::Zeroize;

pub struct NativeSecureBuffer {
    base_ptr: *mut u8,
    data_ptr: *mut u8,
    len: usize,
    page_size: usize,
    num_data_pages: usize,
}

unsafe impl Send for NativeSecureBuffer {}
unsafe impl Sync for NativeSecureBuffer {}

impl NativeSecureBuffer {
    pub fn new(len: usize) -> Self {
        unsafe {
            let page_size = libc::sysconf(libc::_SC_PAGESIZE) as usize;
            let num_data_pages = (len + page_size - 1) / page_size;
            let total_size = (num_data_pages + 2) * page_size;

            let mut base_ptr: *mut libc::c_void = ptr::null_mut();
            let res = libc::posix_memalign(&mut base_ptr, page_size, total_size);
            if res != 0 || base_ptr.is_null() {
                panic!("Failed to allocate page-aligned memory: {}", res);
            }

            let base_ptr = base_ptr as *mut u8;
            let data_ptr = base_ptr.add(page_size);

            // Install guard pages: set first and last page to PROT_NONE
            let first_guard = base_ptr;
            let last_guard = base_ptr.add((1 + num_data_pages) * page_size);

            let res_first = libc::mprotect(
                first_guard as *mut libc::c_void,
                page_size,
                libc::PROT_NONE,
            );
            let res_last = libc::mprotect(
                last_guard as *mut libc::c_void,
                page_size,
                libc::PROT_NONE,
            );
            if res_first != 0 || res_last != 0 {
                panic!("Failed to set guard pages via mprotect");
            }

            // Lock data pages in memory to prevent swap
            // NOTE: On some desktop test environments without appropriate permissions, mlock might fail.
            // However, for small secrets (e.g. Vault Key, Argon2id output) we attempt to lock it.
            let _res_lock = libc::mlock(
                data_ptr as *const libc::c_void,
                num_data_pages * page_size,
            );

            NativeSecureBuffer {
                base_ptr,
                data_ptr,
                len,
                page_size,
                num_data_pages,
            }
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.data_ptr, self.len) }
    }

    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.data_ptr, self.len) }
    }

    pub fn len(&self) -> usize {
        self.len
    }
}

impl Drop for NativeSecureBuffer {
    fn drop(&mut self) {
        unsafe {
            // zeroize before release
            let data_slice = std::slice::from_raw_parts_mut(self.data_ptr, self.len);
            data_slice.zeroize();

            // Unlock data pages
            let _res_unlock = libc::munlock(
                self.data_ptr as *const libc::c_void,
                self.num_data_pages * self.page_size,
            );

            // Restore PROT_READ | PROT_WRITE to guard pages so free() does not crash
            let first_guard = self.base_ptr;
            let last_guard = self.base_ptr.add((1 + self.num_data_pages) * self.page_size);

            libc::mprotect(
                first_guard as *mut libc::c_void,
                self.page_size,
                libc::PROT_READ | libc::PROT_WRITE,
            );
            libc::mprotect(
                last_guard as *mut libc::c_void,
                self.page_size,
                libc::PROT_READ | libc::PROT_WRITE,
            );

            libc::free(self.base_ptr as *mut libc::c_void);
        }
    }
}
