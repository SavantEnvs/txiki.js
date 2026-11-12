# Wrapper project for the sanitized fuzz build: builds upstream's CMake project in place and links
# the harness against its `tjs` library target. Upstream's file is not modified.
cmake_minimum_required(VERSION 3.18)
project(tjs_fuzz LANGUAGES C CXX)

set(BUILD_WITH_MIMALLOC OFF CACHE BOOL "" FORCE)
set(TJS_SRC "${CMAKE_CURRENT_SOURCE_DIR}/..")
add_subdirectory(${TJS_SRC} tjs EXCLUDE_FROM_ALL)

# WAMR performs misaligned loads/stores throughout the interpreter (upstream ships ubsan.supp for
# the same files); relax only that one UBSan check, and only on WAMR plus src/wasm.c, which reads
# WAMR's misaligned table/instance structs.
if(TARGET vmlib)
    target_compile_options(vmlib PRIVATE -fno-sanitize=alignment)
endif()
set_source_files_properties(${TJS_SRC}/src/wasm.c TARGET_DIRECTORY tjs
    PROPERTIES COMPILE_OPTIONS -fno-sanitize=alignment)

foreach(t IN ITEMS wasm url webcrypto text inflate js)
    foreach(kind IN ITEMS fuzz standalone)
        set(exe fuzz_${t}_${kind})
        add_executable(${exe} EXCLUDE_FROM_ALL harness_tjs.c lsan_off.cc)
        target_compile_definitions(${exe} PRIVATE DRIVER_FILE="${CMAKE_CURRENT_SOURCE_DIR}/drivers/${t}.js")
        target_compile_options(${exe} PRIVATE $<$<COMPILE_LANGUAGE:C>:-std=gnu2x>)
        target_include_directories(${exe} PRIVATE ${TJS_SRC}/src)
        target_link_libraries(${exe} PRIVATE tjs)
        if(kind STREQUAL "fuzz")
            target_link_libraries(${exe} PRIVATE $ENV{LIB_FUZZING_ENGINE})
            set_target_properties(${exe} PROPERTIES OUTPUT_NAME fuzz_${t})
        else()
            target_sources(${exe} PRIVATE $ENV{STANDALONE_FUZZ_MAIN})
            set_target_properties(${exe} PROPERTIES OUTPUT_NAME fuzz_${t}-standalone)
        endif()
        set_target_properties(${exe} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out")
    endforeach()
endforeach()
