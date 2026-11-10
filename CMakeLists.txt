# ttycat's firmware. Which board it's for is a folder, in boards/ or anywhere else:
#   idf.py build                                         the Waveshare ESP32-C5-Touch-LCD-2.8
#   idf.py -B build-NAME -D BOARD=NAME build             another folder in boards/
#   idf.py -B build-NAME -D BOARD_DIR=/path/NAME build   a folder of your own, outside this repo
cmake_minimum_required(VERSION 3.16)

# The version in the image's own header is FW_VERSION, so there's only one to bump: main/model.h.
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/main/model.h" fw_version REGEX "^#define FW_VERSION ")
string(REGEX REPLACE "^#define FW_VERSION \"([^\"]+)\".*$" "\\1" PROJECT_VER "${fw_version}")

# The ESP-IDF every release is built with. A release says so, and the Mac app builds with it.
set(TTYCAT_IDF "5.5")
include($ENV{IDF_PATH}/tools/cmake/version.cmake)
if(NOT "${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR}" STREQUAL TTYCAT_IDF)
  message(FATAL_ERROR "ttycat builds with ESP-IDF ${TTYCAT_IDF}, and this is "
                      "${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR}.${IDF_VERSION_PATCH}")
endif()

set(BOARD_DIR "" CACHE PATH "A board's folder outside boards/")
if(BOARD_DIR)
  get_filename_component(BOARD_DIR "${BOARD_DIR}" ABSOLUTE)
  get_filename_component(BOARD "${BOARD_DIR}" NAME)  # a folder's name is its component's
else()
  set(BOARD "waveshare-esp32-c5-touch-lcd-2-8" CACHE STRING "A folder in boards/")
  set(BOARD_DIR "${CMAKE_CURRENT_LIST_DIR}/boards/${BOARD}")
endif()
if(NOT EXISTS "${BOARD_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "No board folder at ${BOARD_DIR}: see the folders in boards")
endif()

# A folder made for another board interface wouldn't build, or worse, would and then misbehave.
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/main/board.h" core_api REGEX "^#define BOARD_API ")
string(REGEX REPLACE "^#define BOARD_API ([0-9]+).*$" "\\1" core_api "${core_api}")
file(STRINGS "${BOARD_DIR}/CMakeLists.txt" board_api REGEX "^set\\(BOARD_API ")
string(REGEX REPLACE "^set\\(BOARD_API ([0-9]+)\\).*$" "\\1" board_api "${board_api}")
if(NOT board_api STREQUAL core_api)
  message(FATAL_ERROR "${BOARD} was made for board interface '${board_api}', and this is ${core_api}: "
                      "see BOARD_API in main/board.h")
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
                      "Delete sdkconfig and this build folder, and unset IDF_TARGET.")
endif()
