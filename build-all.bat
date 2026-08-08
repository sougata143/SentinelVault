@echo off
SETLOCAL EnableDelayedExpansion

set "ESC="
set "RED=%ESC%[91m"
set "GREEN=%ESC%[92m"
set "BLUE=%ESC%[94m"
set "NC=%ESC%[0m"

echo %BLUE%===============================================%NC%
echo %BLUE%  SentinelVault Unified Build Suite (Windows v8) %NC%
echo %BLUE%===============================================%NC%

:: Check prerequisites
where docker >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo %RED%Error: docker is required but not installed.%NC%
    exit /b 1
)

where rustup >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo %RED%Error: Rust rustup is required but not installed.%NC%
    exit /b 1
)

where cargo >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo %RED%Error: Cargo is required but not installed.%NC%
    exit /b 1
)

:: Step 1: Compile Native Crypto Core to WASM (No --locked on host to resolve mismatched lockfiles)
echo.
echo %BLUE%[Step 1/3] Compiling Native Crypto Core to WASM on host...%NC%
cd native\crypto_core
call rustup target add wasm32-unknown-unknown
if %ERRORLEVEL% neq 0 goto :failed
call cargo build --release --target wasm32-unknown-unknown --features wasm
if %ERRORLEVEL% neq 0 goto :failed
cd ..\..
echo %GREEN%^o^/ Native Crypto Core WASM build complete.%NC%

:: Step 2: Build Flutter Web Frontend Image using Dockerfile-v7
echo.
echo %BLUE%[Step 2/3] Packaging Flutter Web Frontend Container...%NC%
docker build ^
  -t sentinelvault-frontend:latest ^
  -t sentinelvault-frontend:3.12.2 ^
  -f Dockerfile .
if %ERRORLEVEL% neq 0 goto :failed
echo %GREEN%^o^/ Flutter Web Frontend containerized successfully.%NC%

:: Step 3: Build Backend Microservice Images
echo.
echo %BLUE%[Step 3/3] Packaging Backend NestJS Microservice Containers...%NC%

echo Building sentinelvault-auth...
docker build -t sentinelvault-auth:latest -f Dockerfile .\backend\auth-service
if %ERRORLEVEL% neq 0 goto :failed

echo Building sentinelvault-sync...
docker build -t sentinelvault-sync:latest -f Dockerfile .\backend\sync-api
if %ERRORLEVEL% neq 0 goto :failed

echo Building sentinelvault-security-analysis...
docker build -t sentinelvault-security-analysis:latest -f Dockerfile .\backend\security-analysis-service
if %ERRORLEVEL% neq 0 goto :failed

echo Building sentinelvault-sharing...
docker build -t sentinelvault-sharing:latest -f Dockerfile .\backend\sharing-service
if %ERRORLEVEL% neq 0 goto :failed

echo.
echo %GREEN%===============================================%NC%
echo %GREEN%  All SentinelVault builds completed successfully!  %NC%
echo %GREEN%===============================================%NC%
exit /b 0

:failed
echo.
echo %RED%===============================================%NC%
echo %RED%  Build Failed! Check error messages above.     %NC%
echo %RED%===============================================%NC%
exit /b 1
