# Testing Notes

## Cin casting issue
I tested a piece of code,
```
    x :i32 = undef
    @cout << "enter a num: "
    @cin >> x
    @pf("the num was {x}\n")
```
Issue with `@cin` arose bec it was not inferring it as the vars type. We use casting for `@input`, bec this builtin rets str by default. `@cin` should find the type of the var it is setting like C++.

## Raylib pkg issue
```
╰─❯ zcy build
install
+- install main
   +- compile exe main Debug native 1 errors
src/zcyout/raylib.zig:1:1: error: unable to load 'raylib.zig': FileNotFound
src/zcyout/main.zig:81:20: note: file imported here
const rl = @import("raylib.zig");
                   ^~~~~~~~~~~~
error: the following command failed with 1 compilation errors:
/snap/zig/15308/zig build-exe -ODebug --dep raylib -Mroot=/home/cjrem/Prog/Proj/ZcyProg/src/z
cyout/main.zig .zig-cache/o/7314d51a175ae41cca815e01702a1e3e/libraylib.a -ODebug -I .zig-cach
e/o/226c04e1752b84b80053a6c9c8248cfe -Mraylib=/home/cjrem/Prog/Proj/ZcyProg/zcy-pkgs/raylib-z
ig/raylib-zig/lib/raylib.zig -lGLX -lX11 -lXcursor -lXext -lXfixes -lXi -lXinerama -lXrandr -
lXrender -lX11 -lc --cache-dir .zig-cache --global-cache-dir /home/cjrem/.cache/zig --name ma
in --zig-lib-dir /snap/zig/15308/lib/ --listen=-

Build Summary: 3/6 steps succeeded; 1 failed
install transitive failure
+- install main transitive failure
   +- compile exe main Debug native 1 errors

error: the following build command failed with
.zig-cache/o/44cae7e690022faaf8e2989db4496fc6/build /snap/zig/15308/zig /snap/zig/15308/lib /
home/cjrem/Prog/Proj/ZcyProg .zig-cache /home/cjrem/.cache/zig --seed 0x8fe15ba2 -Z43a669f1c9
809b1b
error: compilation failed
```
