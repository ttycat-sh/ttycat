# ttycat's firmware. Which board it's for is a folder in boards/:
#   idf.py build                                  the Waveshare ESP32-C5-Touch-LCD-2.8
#   idf.py -B build-NAME -D BOARD=NAME build      any other, in its own build folder
cmake_minimum_required(VERSION 3.16)
set(PROJECT_VER "0.1.0")

set(BOARD "waveshare-esp32-c5-touch-lcd-2-8" CACHE STRING "A folder in boards/")
set(BOARD_DIR "${CMAKE_CURRENT_LIST_DIR}/boards/${BOARD}")
if(NOT EXISTS "${BOARD_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "No board called ${BOARD}: see the folders in firmware/boards")
endif()

set(EXTRA_COMPONENT_DIRS "${BOARD_DIR}")
set(COMPONENTS main ${BOARD})
set(SDKCONFIG_DEFAULTS "${CMAKE_CURRENT_LIST_DIR}/sdkconfig.defaults;${BOARD_DIR}/sdkconfig.defaults")
set(SDKCONFIG "${CMAKE_BINARY_DIR}/sdkconfig")  # so boards can't pick up each other's settings

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

idf_build_set_property(DEPENDENCIES_LOCK "${BOARD_DIR}/dependencies.lock")
project(ttycat)

# A build for the wrong chip wouldn't run. An old sdkconfig or an IDF_TARGET in the shell can cause one.
file(STRINGS "${BOARD_DIR}/sdkconfig.defaults" board_target REGEX "^CONFIG_IDF_TARGET=")
string(REGEX REPLACE "^CONFIG_IDF_TARGET=\"(.*)\"$" "\\1" board_target "${board_target}")
idf_build_get_property(build_target IDF_TARGET)
if(NOT board_target STREQUAL build_target)
  message(FATAL_ERROR "${BOARD} is an ${board_target}, but this build is for ${build_target}. "
                      "Delete firmware/sdkconfig and this build folder, and unset IDF_TARGET.")
endif()
