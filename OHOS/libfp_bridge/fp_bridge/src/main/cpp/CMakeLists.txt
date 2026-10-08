# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(fp_bridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(fp_bridge SHARED napi_init.cpp fp_bridge.cpp binder_bridge.cpp arkts_invoke.cpp)

# 链接 NAPI 和 OHOS 运行时库（与 fpGUIApp/libentry.so 相同）
target_link_libraries(fp_bridge PUBLIC
    libace_napi.z.so
    libace_ndk.z.so
    libhilog_ndk.z.so
    libnative_window.so
    libnative_display_manager.so
    libpasteboard.so
    libudmf.so
    #libohenvironment.so
    # Binder (IPC Kit)：OH_Ability_CreateNativeChildProcess + OH_IPCRemoteProxy_*
    libchild_process.so
    libipc_capi.so)