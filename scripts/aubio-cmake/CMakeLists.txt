cmake_minimum_required(VERSION 3.20)
project(SongbirdAubioVendor LANGUAGES C)

if(NOT DEFINED AUBIO_SOURCE_ROOT)
    message(FATAL_ERROR "Pass -DAUBIO_SOURCE_ROOT=/absolute/path/to/Vendor/aubio/src")
endif()

file(GLOB_RECURSE AUBIO_SOURCES CONFIGURE_DEPENDS
    "${AUBIO_SOURCE_ROOT}/src/*.c"
)

configure_file(config.h.in config.h @ONLY)
add_library(aubio SHARED ${AUBIO_SOURCES})
target_compile_features(aubio PRIVATE c_std_99)
target_compile_definitions(aubio PRIVATE HAVE_CONFIG_H=1)
target_include_directories(aubio PRIVATE
    "${AUBIO_SOURCE_ROOT}/src"
    "${CMAKE_CURRENT_BINARY_DIR}"
)
set_target_properties(aubio PROPERTIES
    OUTPUT_NAME aubio
    VERSION 5.4.8
    SOVERSION 5
    INSTALL_NAME_DIR "@rpath"
    MACOSX_RPATH ON
)

