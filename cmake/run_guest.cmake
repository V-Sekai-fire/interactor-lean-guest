# Run a guest ELF under an emulator and compare its stdout with a file.
# rvlinux bounds jumps by .text by default; glibc's static .iplt sits beside it, so use segments (-I).
set(emu_args)
get_filename_component(emu_name ${EMULATOR} NAME)
if(emu_name STREQUAL "rvlinux")
	set(emu_args -I)
endif()
execute_process(COMMAND ${EMULATOR} ${emu_args} ${ELF} a b
	OUTPUT_VARIABLE out ERROR_VARIABLE err RESULT_VARIABLE rc)
file(READ ${EXPECTED} want)
string(FIND "${out}" "${want}" at)
if(NOT rc EQUAL 0 OR at EQUAL -1)
	message(FATAL_ERROR "guest rc=${rc}\n--- got\n${out}${err}\n--- want\n${want}")
endif()
