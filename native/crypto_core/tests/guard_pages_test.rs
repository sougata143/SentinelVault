#[cfg(unix)]
#[test]
fn test_guard_page_segfault() {
    use std::env;
    use std::process::Command;

    // Check if we are the child process triggered to crash
    if env::var("RUN_GUARD_PAGE_CRASH").is_ok() {
        use crypto_core::secure_mem::SecureBuffer;
        
        let mut buffer = SecureBuffer::new(100);
        let slice = buffer.as_mut_slice();
        slice[0] = 42;
        
        // Out-of-bounds write (should hit the trailing guard page)
        unsafe {
            let ptr = slice.as_mut_ptr();
            let page_size = libc::sysconf(libc::_SC_PAGESIZE) as isize;
            // The data pages start after the first page (first guard page).
            // A write at page_size offset relative to the data pointer (ptr)
            // lands in the trailing guard page.
            let out_ptr = ptr.offset(page_size);
            std::ptr::write_volatile(out_ptr, 99);
        }
        // If we reach here, the guard page did not catch the write.
        std::process::exit(0);
    }

    // Parent test process: spawn the child
    let self_exe = env::current_exe().unwrap();
    let output = Command::new(self_exe)
        .arg("test_guard_page_segfault")
        .env("RUN_GUARD_PAGE_CRASH", "1")
        .output()
        .unwrap();

    // The child should crash (exit with failure / signal)
    assert!(!output.status.success(), "Child process succeeded but was expected to crash due to guard page SIGSEGV/SIGBUS");
    
    // Verify it crashed via signal on Unix
    use std::os::unix::process::ExitStatusExt;
    let signal = output.status.signal();
    assert!(signal.is_some(), "Expected child process to be terminated by a signal");
    let sig = signal.unwrap();
    assert!(sig == 11 || sig == 10 || sig == 6, "Expected signal 11 (SIGSEGV), 10 (SIGBUS) or 6 (SIGABRT), got {}", sig);
}
