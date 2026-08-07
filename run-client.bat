@echo off
setlocal EnableDelayedExpansion

:: Define ANSI escape sequences for colors (Windows 10+)
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "C_GREEN=%ESC%[0;32m"
set "C_RED=%ESC%[0;31m"
set "C_YELLOW=%ESC%[0;33m"
set "C_RESET=%ESC%[0m"

:: Get absolute path to the directory this script lives in
set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

set SKIP_RUST=false
set SKIP_WASM=false
set SKIP_TESTS=false
set CHECK_ONLY=false
set DEVICE=

:parse_args
if "%~1"=="" goto after_args
if "%~1"=="--skip-rust" set SKIP_RUST=true & shift & goto parse_args
if "%~1"=="--skip-wasm" set SKIP_WASM=true & shift & goto parse_args
if "%~1"=="--skip-tests" set SKIP_TESTS=true & shift & goto parse_args
if "%~1"=="--check" set CHECK_ONLY=true & shift & goto parse_args
if "%~1"=="--help" (
    echo Options:
    echo   --skip-rust      Skip building the native crypto core entirely
    echo   --skip-wasm      Build the native crate but skip the Wasm/web target
    echo   --skip-tests     Skip cargo test after building ^(faster, less safe^)
    echo   --device NAME    Run directly on this device ^(e.g. chrome, windows,
    echo                    "iPhone 16", emulator-5554^) instead of prompting
    echo   --check          Only verify prerequisites, then exit
    echo   --help           Show this help text
    exit /b 0
)
if "%~1"=="--device" (
    set "DEVICE=%~2"
    shift
    shift
    goto parse_args
)
echo Unknown option: %~1 (see --help)
exit /b 1

:after_args

:: ---------------------------------------------------------------------------
:: 1. Prerequisites
:: ---------------------------------------------------------------------------
echo == Checking prerequisites ==
set all_ok=true

where cargo >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    echo !C_RED!X cargo not found - install via https://rustup.rs!C_RESET!
    set all_ok=false
) else (
    for /f "tokens=*" %%i in ('cargo --version 2^>^&1') do set CARGO_VER=%%i
    echo !C_GREEN!v cargo found ^(!CARGO_VER!^)!C_RESET!
)

where flutter >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    echo !C_RED!X flutter not found - install from https://flutter.dev!C_RESET!
    set all_ok=false
) else (
    for /f "tokens=*" %%i in ('call flutter --version 2^>^&1') do (
        set FLUTTER_VER=%%i
        goto flutter_ver_done
    )
    :flutter_ver_done
    echo !C_GREEN!v flutter found ^(!FLUTTER_VER!^)!C_RESET!
)

where rustup >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo !C_GREEN!v rustup found!C_RESET!
    set HAVE_RUSTUP=true
) else (
    echo !C_YELLOW!WARNING: rustup not found - Wasm/web build step will be skipped!C_RESET!
    set HAVE_RUSTUP=false
)

where wasm-bindgen >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    for /f "tokens=*" %%i in ('wasm-bindgen --version 2^>^&1') do set WASM_VER=%%i
    echo !C_GREEN!v wasm-bindgen-cli found ^(!WASM_VER!^)!C_RESET!
    set HAVE_WASM_BINDGEN=true
) else (
    echo !C_YELLOW!WARNING: wasm-bindgen-cli not found - will attempt to install a
    echo   matching version automatically during the Wasm build step!C_RESET!
    set HAVE_WASM_BINDGEN=false
)

if "!all_ok!"=="false" (
    echo !C_RED!Missing prerequisites - install the above, then re-run.!C_RESET!
    exit /b 1
)

if "!CHECK_ONLY!"=="true" (
    echo !C_GREEN!All required prerequisites satisfied.!C_RESET!
    exit /b 0
)

:: ---------------------------------------------------------------------------
:: 2. Native crypto core
:: ---------------------------------------------------------------------------
if "!SKIP_RUST!"=="false" (
    echo == Building native crypto core ==
    pushd "%ROOT_DIR%\native\crypto_core"
    
    cargo build --release

    if "!SKIP_TESTS!"=="false" (
        echo Running crypto core tests...
        cargo test
    ) else (
        echo !C_YELLOW!Skipping cargo test (--skip-tests)!C_RESET!
    )

    if "!SKIP_WASM!"=="false" (
        if "!HAVE_RUSTUP!"=="true" (
            rustup target list --installed | findstr /b /c:"wasm32-unknown-unknown" >nul
            if !ERRORLEVEL! NEQ 0 (
                echo Adding wasm32-unknown-unknown target...
                rustup target add wasm32-unknown-unknown
            )
            echo Building wasm32 target ^(required for the Web build^)...
            rustup run stable cargo build --target wasm32-unknown-unknown --features wasm --release

            :: --- Generate JS glue with wasm-bindgen -----------------------------
            :: Use PowerShell to cleanly extract the wasm-bindgen version from Cargo.lock
            set WASM_BINDGEN_VERSION=
            for /f "usebackq tokens=*" %%v in (`powershell -NoProfile -Command "(Get-Content Cargo.lock | Select-String -Pattern 'name = \"wasm-bindgen\"' -Context 0,1).Context.PostContext -match 'version = \"(.*?)\"' | Out-Null; $Matches[1]"`) do set WASM_BINDGEN_VERSION=%%v

            if "!WASM_BINDGEN_VERSION!"=="" (
                echo !C_RED!X Could not determine wasm-bindgen version from Cargo.lock
                echo   Is 'wasm-bindgen' a dependency of native/crypto_core?!C_RESET!
                popd
                exit /b 1
            )

            set INSTALLED_VERSION=
            if "!HAVE_WASM_BINDGEN!"=="true" (
                for /f "tokens=2" %%v in ('wasm-bindgen --version 2^>^&1') do set INSTALLED_VERSION=%%v
            )

            if "!INSTALLED_VERSION!" NEQ "!WASM_BINDGEN_VERSION!" (
                echo Installing wasm-bindgen-cli !WASM_BINDGEN_VERSION! ^(matching Cargo.lock^)...
                cargo install wasm-bindgen-cli --version "!WASM_BINDGEN_VERSION!" --force
            ) else (
                echo !C_GREEN!v wasm-bindgen-cli !INSTALLED_VERSION! already matches Cargo.lock!C_RESET!
            )

            set "WEB_PKG_DIR=%ROOT_DIR%\app\web\pkg"
            echo Running wasm-bindgen -^> !WEB_PKG_DIR! ...
            if exist "!WEB_PKG_DIR!" rmdir /s /q "!WEB_PKG_DIR!"
            mkdir "!WEB_PKG_DIR!"
            
            wasm-bindgen "target\wasm32-unknown-unknown\release\crypto_core.wasm" --target web --out-dir "!WEB_PKG_DIR!" --out-name crypto_core

            echo !C_GREEN!v Generated crypto_core.js + crypto_core_bg.wasm in app\web\pkg\!C_RESET!
            echo !C_YELLOW!Reminder: crypto_core.js must be imported with a RELATIVE path
            echo ^(e.g. './pkg/crypto_core.js'^) in your Dart/JS interop loader -
            echo an absolute 'http://localhost:^<port^>/...' URL will break every
            echo time 'flutter run -d chrome' picks a new random port.!C_RESET!
        ) else (
            echo !C_YELLOW!WARNING: Skipping Wasm build - rustup not available. Native
            echo   targets are unaffected; Web needs rustup installed to build this target.!C_RESET!
        )
    ) else (
        echo !C_YELLOW!Skipping Wasm build (--skip-wasm)!C_RESET!
    )
    popd
) else (
    echo !C_YELLOW!Skipping native crypto core build entirely (--skip-rust)!C_RESET!
)

:: ---------------------------------------------------------------------------
:: 3. Flutter app
:: ---------------------------------------------------------------------------
echo == Preparing Flutter app ==
pushd "%ROOT_DIR%\app"
call flutter pub get

if "%DEVICE%"=="" (
    echo Available devices:
    call flutter devices
    echo.
    echo Choose a target to run:
    echo 1. iOS Simulator
    echo 2. Android Emulator
    echo 3. Chrome ^(Web^)
    echo 4. Windows Desktop
    
    choice /C 1234 /M "Select your choice: "
    if !ERRORLEVEL! EQU 1 set DEVICE=iPhone 16
    if !ERRORLEVEL! EQU 2 set DEVICE=emulator-5554
    if !ERRORLEVEL! EQU 3 set DEVICE=chrome
    if !ERRORLEVEL! EQU 4 set DEVICE=windows
)

if "%DEVICE%"=="emulator-5554" (
    echo !C_YELLOW!Reminder: the Android Emulator can't reach the backend via
    echo 'localhost' - it needs 10.0.2.2 instead. If API calls fail,
    echo check your app's backend base URL config for this target.!C_RESET!
)

echo !C_YELLOW!Reminder: successful account login does NOT unlock the vault -
echo the Master Password unlock step is always required separately.!C_RESET!

if "%DEVICE%"=="chrome" (
    call flutter run -d "!DEVICE!" --web-port=59468
) else (
    call flutter run -d "!DEVICE!"
)

popd
exit /b 0