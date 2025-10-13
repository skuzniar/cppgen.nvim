cmake_minimum_required(VERSION 3.20)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

project(examples)

add_compile_options(-Wno-unknown-attributes)

add_executable(cppgen-example cppgen-example.cpp)
target_include_directories(cppgen-example PUBLIC .)
