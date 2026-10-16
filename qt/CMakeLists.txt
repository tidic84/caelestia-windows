cmake_minimum_required(VERSION 3.21)
project(ilot LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.9 REQUIRED COMPONENTS Gui Quick ShaderTools)
qt_standard_project_setup(REQUIRES 6.9)

qt_add_executable(ilot WIN32
    src/main.cpp
    src/core.h
    src/backend.h src/backend.cpp
    src/shell.h src/shell.cpp
    ilot.rc
)

# QML et modules JavaScript, a la racine du module (sinon chaque fichier
# importe son dossier `qml/`, et les singletons ne sont plus uniques)
file(GLOB QML_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml qml/*.mjs)
foreach(f IN LISTS QML_FILES)
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
set_source_files_properties(qml/Theme.qml qml/Ilot.qml qml/Api.qml qml/Watch.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(ilot
    URI Ilot
    VERSION 1.0
    QML_FILES ${QML_FILES}
    SOURCES src/winctl.h src/winctl.cpp src/backdrop.h src/backdrop.cpp src/tray.h src/tray.cpp
)

# Rubik et Material Symbols Rounded (fonts/README.md)
file(GLOB FONT_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS fonts/*.ttf)
qt_add_resources(ilot "fonts" PREFIX "/" FILES ${FONT_FILES})

qt_add_shaders(ilot "shaders"
    PREFIX "/"
    FILES shaders/round.frag
)

# coeur Rust (cargo build --release a la racine du depot)
set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../target/release)
add_library(ilot_core SHARED IMPORTED)
set_target_properties(ilot_core PROPERTIES
    IMPORTED_IMPLIB ${CORE_DIR}/ilot_core.dll.lib
    IMPORTED_LOCATION ${CORE_DIR}/ilot_core.dll)

target_include_directories(ilot PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(ilot PRIVATE QT_NO_KEYWORDS WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_compile_options(ilot PRIVATE /permissive- /EHsc /utf-8)
target_link_libraries(ilot PRIVATE Qt6::Gui Qt6::Quick ilot_core user32 shell32 dwmapi d2d1 windowsapp CoreMessaging)

add_custom_command(TARGET ilot POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CORE_DIR}/ilot_core.dll $<TARGET_FILE_DIR:ilot>)
