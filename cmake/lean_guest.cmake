# Lean runtime + Init for a riscv64 guest, and lean_guest_executable() for user programs.
include(FetchContent)

find_program(LEAN_EXE lean REQUIRED NO_CMAKE_FIND_ROOT_PATH)
find_program(LAKE_EXE lake REQUIRED NO_CMAKE_FIND_ROOT_PATH)
execute_process(COMMAND ${LEAN_EXE} --short-version OUTPUT_VARIABLE _host_lean OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _host_lean STREQUAL LEAN_VERSION)
	message(FATAL_ERROR "host lean is ${_host_lean}, LEAN_VERSION is ${LEAN_VERSION}; generated C must match the runtime")
endif()
# Lean's own source tree carries an elan override to stage0, so Init is compiled by the toolchain binary itself.
execute_process(COMMAND ${LEAN_EXE} --print-prefix OUTPUT_VARIABLE _prefix OUTPUT_STRIP_TRAILING_WHITESPACE)
set(LEAN_TOOLCHAIN_LEAN ${_prefix}/bin/lean)
execute_process(COMMAND ${LEAN_EXE} --githash OUTPUT_VARIABLE LEAN_GITHASH OUTPUT_STRIP_TRAILING_WHITESPACE)

# patch(1), not git apply: inside another git work tree, git apply skips paths outside it without an error.
find_program(PATCH_EXE patch REQUIRED NO_CMAKE_FIND_ROOT_PATH)
FetchContent_Declare(lean4
	URL https://github.com/leanprover/lean4/archive/refs/tags/v${LEAN_VERSION}.tar.gz
	DOWNLOAD_EXTRACT_TIMESTAMP TRUE
	SOURCE_SUBDIR no-cmake-entry
	PATCH_COMMAND ${PATCH_EXE} -p2 --forward --batch -i ${CMAKE_CURRENT_LIST_DIR}/../patches/runtime-guest.patch)
FetchContent_Declare(libuv
	URL https://github.com/libuv/libuv/archive/refs/tags/v${LIBUV_VERSION}.tar.gz
	DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
set(LIBUV_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(LIBUV_BUILD_TESTS OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(lean4 libuv)

set(LEAN_SRC ${lean4_SOURCE_DIR}/src)
set(LEAN_GEN ${CMAKE_BINARY_DIR}/lean-gen)
file(MAKE_DIRECTORY ${LEAN_GEN}/include/lean)
file(WRITE ${LEAN_GEN}/include/lean/config.h "#pragma once\n#include <lean/version.h>\n#define LEAN_IS_STAGE0 0\n")
file(WRITE ${LEAN_GEN}/include/githash.h "#define LEAN_GITHASH \"${LEAN_GITHASH}\"\n")
configure_file(${_prefix}/include/lean/version.h ${LEAN_GEN}/include/lean/version.h COPYONLY)

set(LEAN_GUEST_DEFS NDEBUG LEAN_EXPORTING LEAN_MULTI_THREAD LEAN_NO_UV LEAN_NO_OPENSSL LEAN_BUILD_TYPE="Release")
set(LEAN_GUEST_FLAGS -O2 -ffp-contract=off -ffunction-sections -fdata-sections -w)

file(GLOB LEAN_RT_SRC ${LEAN_SRC}/runtime/*.cpp ${LEAN_SRC}/runtime/uv/*.cpp)
add_library(leanrt_guest STATIC ${LEAN_RT_SRC})
target_compile_features(leanrt_guest PUBLIC cxx_std_20)
target_compile_definitions(leanrt_guest PRIVATE ${LEAN_GUEST_DEFS})
target_compile_options(leanrt_guest PRIVATE ${LEAN_GUEST_FLAGS})
target_include_directories(leanrt_guest PRIVATE ${LEAN_SRC} ${LEAN_GEN}/include)
target_include_directories(leanrt_guest PUBLIC ${LEAN_GEN}/include ${LEAN_SRC}/include)
target_link_libraries(leanrt_guest PUBLIC uv_a)

# Init's C is emitted by the host lean from the matching release's sources.
file(GLOB_RECURSE _init_lean RELATIVE ${LEAN_SRC} ${LEAN_SRC}/Init/*.lean)
list(APPEND _init_lean Init.lean)
set(_init_c)
foreach(_f IN LISTS _init_lean)
	string(REGEX REPLACE "\\.lean$" "" _m ${_f})
	string(REPLACE "/" "." _m ${_m})
	set(_c ${LEAN_GEN}/init/${_m}.c)
	add_custom_command(OUTPUT ${_c}
		COMMAND ${CMAKE_COMMAND} -E make_directory ${LEAN_GEN}/init
		COMMAND ${LEAN_TOOLCHAIN_LEAN} -c ${_c} ${_f}
		WORKING_DIRECTORY ${LEAN_SRC}
		DEPENDS ${LEAN_SRC}/${_f}
		VERBATIM)
	list(APPEND _init_c ${_c})
endforeach()
add_library(leaninit_guest STATIC ${_init_c})
target_compile_definitions(leaninit_guest PRIVATE NDEBUG)
target_compile_options(leaninit_guest PRIVATE ${LEAN_GUEST_FLAGS})
target_link_libraries(leaninit_guest PUBLIC leanrt_guest)

# lean_guest_executable(<name> LAKE_DIR <dir> MODULES <Mod>...)
function(lean_guest_executable name)
	cmake_parse_arguments(ARG "" "LAKE_DIR" "MODULES" ${ARGN})
	set(_c_files)
	foreach(_m IN LISTS ARG_MODULES)
		string(REPLACE "." "/" _p ${_m})
		set(_c ${ARG_LAKE_DIR}/.lake/build/ir/${_p}.c)
		file(GLOB_RECURSE _deps ${ARG_LAKE_DIR}/*.lean)
		list(FILTER _deps EXCLUDE REGEX "/\\.lake/")
		add_custom_command(OUTPUT ${_c}
			COMMAND ${LAKE_EXE} build ${_m}:c
			WORKING_DIRECTORY ${ARG_LAKE_DIR}
			DEPENDS ${_deps}
			VERBATIM)
		list(APPEND _c_files ${_c})
	endforeach()
	add_executable(${name} ${_c_files})
	set_target_properties(${name} PROPERTIES SUFFIX ".elf" LINKER_LANGUAGE CXX)
	target_compile_definitions(${name} PRIVATE NDEBUG)
	target_compile_options(${name} PRIVATE ${LEAN_GUEST_FLAGS})
	target_link_options(${name} PRIVATE -static -Wl,--gc-sections -s)
	target_link_libraries(${name} PRIVATE leaninit_guest pthread)
endfunction()
