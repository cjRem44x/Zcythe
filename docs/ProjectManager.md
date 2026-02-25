# Project Manager for Zcythe

## Starting a new Project
```
mkdir Porject
cd Porject

zcy init
```

`zcy` is the CLI call to the Zcythe env.

## Project Structure
For right now, we have a simple structure. We will add more later. This is what `zcy init` creates.
```
/proj
    /src
        /zcyout # transpiled src code goes here.
        /main
            /zcy
                main.zcy
```

## Building a Project
```
zcy build
```
Transpiles `src/main/zcy/main.zcy` → `src/zcyout/main.zig`, then compiles it with `zig`.
The resulting binary is written to `./main` in the project root.

## Running a Project
```
zcy run
```
Builds the project (same as `zcy build`) and immediately executes the compiled binary.
The program's stdin/stdout/stderr are connected to your terminal normally.
