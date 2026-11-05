idf_component_register(
    SRCS "main.c" "gfx.c" "fonts.c" "ui.c" "link.c" "sound.c" "pet.c" "keyboard.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_usb_serial_jtag esp_driver_uart esp_timer esp_hw_support json mbedtls nvs_flash)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-format-truncation)

# Who this build says it is: see FW_NAME in model.h. Editing any of these sources gives it a new name.
file(GLOB fw_sources "${CMAKE_CURRENT_LIST_DIR}/*.c" "${CMAKE_CURRENT_LIST_DIR}/*.h"
                     "${BOARD_DIR}/*.c" "${BOARD_DIR}/*.h" "${BOARD_DIR}/sdkconfig.defaults")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${fw_sources})
set(fw_hashes "")
foreach(fw_source ${fw_sources})
  file(SHA256 "${fw_source}" fw_hash)
  string(APPEND fw_hashes "${fw_hash}")
endforeach()
string(SHA256 fw_build_id "${fw_hashes}")
string(SUBSTRING "${fw_build_id}" 0 8 fw_build_id)
set(fw_defines "FW_BUILD_ID=\"${fw_build_id}\"" "FW_BOARD=\"${BOARD}\"")
if(FW_RELEASE)
  list(APPEND fw_defines FW_RELEASE)
endif()
set_source_files_properties(ui.c PROPERTIES COMPILE_DEFINITIONS "${fw_defines}")
