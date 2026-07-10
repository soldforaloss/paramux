cmake_minimum_required(VERSION 3.19)
project(c-vt-cmake LANGUAGES C)

include(FetchContent)
FetchContent_Declare(paramux
    GIT_REPOSITORY https://github.com/soldforaloss/paramux.git
    GIT_TAG paramux
)
FetchContent_MakeAvailable(paramux)

add_executable(c_vt_cmake src/main.c)
target_link_libraries(c_vt_cmake PRIVATE ghostty-vt)
