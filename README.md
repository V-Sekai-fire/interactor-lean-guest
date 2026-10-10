# interactor-lean-guest

Build Lean 4 programs as static riscv64 Linux ELF files for godot-sandbox (libriscv) guests.

## How it works

1. The host Lean toolchain (elan) compiles your Lake project to C (`lake build <Module>:c`).
2. The host Lean also compiles the matching release's `Init` sources to C.
3. A riscv64 cross compiler builds that C, the Lean runtime and libuv, and links one static ELF.

The Lean release and libuv version are pinned in `CMakeLists.txt`. The host toolchain must be the same release, because the generated C and the runtime must match. The build checks this.

## Runtime changes

`patches/runtime-guest.patch` changes the Lean runtime for a guest:

- `LEAN_NO_UV` keeps libuv for file calls (`uv_fs_*`, `uv_strerror`) but removes the event loop, timers, sockets and DNS. A guest has no epoll or pipes, and the loop start-up aborts without them.
- `LEAN_NO_OPENSSL` removes the OpenSSL version query.
- It fixes two stub signatures that did not match their headers.

`Std.Internal.UV` (async timers, TCP, UDP, DNS) returns errors in a guest. `IO.println`, `Nat` bignums, tasks and threads work.

## Build and run

Use the goal manifest's sysroot (`5-repository/riscv64-sysroot`) with Homebrew or apt `clang` and `lld`:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=../../5-repository/riscv64-sysroot/toolchain.cmake
cmake --build build
ctest --test-dir build --output-on-failure
```

`ctest` runs `build/hello.elf` under `rvlinux` (libriscv's emulator) or `qemu-riscv64`, whichever it finds. Set `LEAN_GUEST_EMULATOR` to choose one. The `hello_control_must_fail` test compares against a wrong answer and must fail.

## Your own program

```cmake
lean_guest_executable(my_guest
  LAKE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/my_guest
  MODULES Main MyGuest.Logic)
```

List every module of the program. Only `Init` is linked; a program that imports `Std` or `Lean` does not link yet.

## Known limits

- glibc's static ifunc table (`.iplt`) is outside `.text`. Run `rvlinux` with `-I` (use segments, not `.text`). Check the godot-sandbox loader for the same limit before you load a guest in the engine.
- `rvlinux` on a macOS host fails `CLOCK_MONOTONIC`, because it compares Linux clock ids with macOS clock ids. Lean's runtime reads that clock at start-up. `patches/libriscv-macos-clock.patch` fixes libriscv.
- Nothing here calls the godot-sandbox API yet. A Lean guest reaches it through `@[extern]` C functions.

## Licence

Apache-2.0, the same as Lean 4. The patch modifies Lean 4 runtime sources.
