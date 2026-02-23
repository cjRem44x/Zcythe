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
```
