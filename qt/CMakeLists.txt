cmake_minimum_required(VERSION 3.21)
project(ilot_qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Quick)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(ilot-qt WIN32
    src/main.cpp
    src/island.h src/island.cpp
    src/media.h src/media.cpp
    src/sysmon.h src/sysmon.cpp
    src/viz.h src/viz.cpp
)

set(QML_FILES Theme Main Pill Panel HomeTab MediaTab Gauge Ear RoundArt Progress Controls VizBars)
list(TRANSFORM QML_FILES PREPEND qml/)
list(TRANSFORM QML_FILES APPEND .qml)
# a la racine du module : sinon chaque fichier importe son dossier `qml/`, ou
# Theme n'est pas un singleton
foreach(f IN LISTS QML_FILES)
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(ilot-qt
    URI Ilot
    VERSION 1.0
    QML_FILES ${QML_FILES}
)

# C++/WinRT (GSMTC) : sans les mots-cles Qt (signals, slots, emit) qui
# entrent en conflit avec ses en-tetes
target_compile_definitions(ilot-qt PRIVATE QT_NO_KEYWORDS WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(ilot-qt PRIVATE /permissive- /EHsc /utf-8)
target_link_libraries(ilot-qt PRIVATE Qt6::Gui Qt6::Quick windowsapp ole32 dwmapi)
