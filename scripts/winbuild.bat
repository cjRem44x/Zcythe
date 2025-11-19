@echo off 

set proj="%cd%/.."

set odin_src=%proj%/src/main/odin
set rust_src=%proj%/src/main/rust
set zig_src=%proj%/src/main/zig
set java_src=%proj%/src/main/java
set bin=%proj%/bin

@REM cd %java_src%
@REM javac -d %bin% ^
@REM     *.java
@REM java -cp %bin% main.java.Main

@REM cd %odin_src%
@REM odin run .

@REM cd %rust_src%
@REM cargo build
@REM cargo run

cd %zig_src%
zig build
zig build run

pause
