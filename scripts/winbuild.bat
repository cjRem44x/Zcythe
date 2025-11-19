@echo off 

set proj="%cd%/.."

set zig_src=%proj%/src/main/zig
set bin=%proj%/bin

cd %zig_src%
zig build
zig build run

cd %proj%
pause
