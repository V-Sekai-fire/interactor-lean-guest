# Lean 4 programs as static riscv64 Linux guest ELFs for godot-sandbox (libriscv).
# The host toolchain (elan) emits C; this build cross-compiles that C, Init's C and the Lean runtime.
cmake_minimum_required(VERSION 3.20)
project(interactor_lean_guest C CXX)

set(LEAN_VERSION "4.34.1" CACHE STRING "Lean release; must match the host toolchain that emits the C")
set(LIBUV_VERSION "1.48.0" CACHE STRING "libuv release the Lean runtime pins")

include(cmake/lean_guest.cmake)

lean_guest_executable(hello
	LAKE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/examples/hello
	MODULES Main)

enable_testing()
find_program(LEAN_GUEST_EMULATOR NAMES rvlinux qemu-riscv64 qemu-riscv64-static)
if(LEAN_GUEST_EMULATOR)
	add_test(NAME hello COMMAND ${CMAKE_COMMAND}
		-DEMULATOR=${LEAN_GUEST_EMULATOR} -DELF=$<TARGET_FILE:hello>
		-DEXPECTED=${CMAKE_CURRENT_SOURCE_DIR}/examples/hello/expected.txt
		-P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_guest.cmake)
	add_test(NAME hello_control_must_fail COMMAND ${CMAKE_COMMAND}
		-DEMULATOR=${LEAN_GUEST_EMULATOR} -DELF=$<TARGET_FILE:hello>
		-DEXPECTED=${CMAKE_CURRENT_SOURCE_DIR}/examples/hello/expected-wrong.txt
		-P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_guest.cmake)
	set_tests_properties(hello_control_must_fail PROPERTIES WILL_FAIL TRUE)
endif()
