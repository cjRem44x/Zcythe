# TODO

# Heap
```
# explicit pointers only
heap H {
    p: *i32,
    p2: *[]i8,
    p3: *imu f32,
    p4: *imu i32[],

    a: *i32, b: *i32,
    imu c: *i32,
}

@main {
    H.p.alo() # alloc a default value 0/0.0 for nums and "0" for strs
    defer H.p.free() # free
    H.p.* = 4
    @pl(H.p.len()) # => 1 

    N :: 100 # needs size
    H.p2.alo(N)
    @pl(H.p2.len()) # => N
    p2[0].* = 5

    H.p3.alo()
    defer H.p3.free()
    p3.* = 5.4 # init val
    p3.* += 1.0 # it will err here bec once the val is set ^, it becomes immut

    H.p4.alo(10)
    defer H.p4.free()
    p4[i].* = 5 # set val once then it becomes immut

    H.a.alo()
    H.a.* = 5
    H.b.alo()
    H.b.set(H.a.get()) # set address b = get address a; b = a
    @pl(H.b.*)
    H.a.free()
    H.b.free()

    H.c.alo()
    defer H.c.free()
    H.c.set(H.a.get()) # will err becaus c was decl immut and only alloc to init addrs
}
```

## Stack Refs
```
@main {
    # ref pass vars must be explicit, will err otherwise
    x: i32 = 44
    y: str = "Hello"
    foo(x, y, 45)
    
    # passing rets or lits
    foo(x, "f", 25) # this will err, cannot pass literal to ref

    foo(x, y2 = "f", 25) # assign val to stack var in call, the type is inferred based on the func param it is being pass to
    foo(x, y2 = bar(), 25) # in a case where you pass a ret func
}

fn foo(x: &i32, y: &imu str, z) { # ref pass is decl in func params, must be explicit
    x += 1
    y = "Hello" # will err bec your pass y as immut ref
    z = 44 # normal stack var
}
```
