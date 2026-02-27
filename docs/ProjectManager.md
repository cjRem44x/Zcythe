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
    /zcy-bin    # compiled binaries go here.
```

## Building a Project
```
zcy build [-name=NAME]
```
Transpiles `src/main/zcy/main.zcy` → `src/zcyout/main.zig`, then compiles it with `zig`.
The resulting binary is written to `zcy-bin/<NAME>` (default: `zcy-bin/main`).

Examples:
```
zcy build              # produces zcy-bin/main
zcy build -name=greet  # produces zcy-bin/greet
```

## Running a Project
```
zcy run [-name=NAME]
```
Builds the project (same as `zcy build`) and immediately executes `zcy-bin/<NAME>`.
The program's stdin/stdout/stderr are connected to your terminal normally.

Examples:
```
zcy run              # builds and runs zcy-bin/main
zcy run -name=greet  # builds and runs zcy-bin/greet
```
