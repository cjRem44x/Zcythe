# Updates for the lang

# A Union type,

## Standard
```
dat Person {...}

unn X {
    x: i32,
    f: f32,
    p: Person, # defined dat
    anon: .{a: str, b: str}, # anon dat
}

@main {
    x : X = X.x{4}
    x2 := X.f{3.145}
    x3 := X.p{...init fields, .foo = ..., etc.}
    x4 := X.anon{.a="", .b=""}
}
```

## Union(Enum)
```
unn Y => enum {
    a: i32,
    b: f32,
    c: .{...anon dat}
}

# Just like Zig's union(enum)
@main {
    y :Y = Y.a{53}

    switch y {
        .a => |a| {@pl(a)},
        .b => |b| {@pl(b)},
        .c => |c| {...}
    }
}
```

# New Heap/Stack Method
I no longer like the Heap and Stack ref struck and want a more C flavored default.
REMOVE all curr heap and heap struct, stack pass by ref from lang and replace with...

```
@main {
    x :i32 = 3 # this val must be explicit
    pX :*i32 = &x # pointers are allowed on stack now
    @pl(pX) # print addrs
    @pl(pX.*) # print underlining val

    y :f32: 3.145
    pY :*imu f32 = &y # mut ptr to a immut val
    
    z :str: "word"
    pZ :*imu str: &z # immut ptr to immut val

    # and so on...
    # Pointers And there Ref Vals MUST be explicit or it warns.

    # New Heap Method
    nums :*[]i32 = @alo(i32, N) # alloc a arr of i32's of size N
    defer @free(nums)
    nums[i] # addrs
    nums[i].* # underlining val

    @pf("{nums[n]} is {nums[n].*}\n") # should work in pl/pf/cout

    # Now, this is our default C way of alloc/free on the heap.

    foo(pX, nums) # pass by pointer

    # OR
    L  :i32   = 5
    L2 :[]i32 = {1,2,3,4,5}
    foo(&L, &L2) # pass the ref of val
}

# very simple, explicit, pointer params
fn foo(x: *i32, y: *[]i32) {} # the ptrs params are explicit to, here *i32 could be a stack var ptr, and *[]i32 stack/heap.

# For str
strings :*[]str = @alo(str, N) # basic arr alloc
s :*str = @alo::str("word") # single str alloc
...free it

# Dats/Structs/Cls follow the same principle
foo :*[]foo = @alo(foo, N)
b :*[]Bar = @alo(Bar, 10) # for dat/struct/cls

p  :*Person = @alo::dat(Person) # alloc dat inst
p2 :*Person2 = @alo::struct(Person2) # alloc struct inst
p3 :*Person3 = @alo::cls(Person3) # alloc cls inst
```

Int, Floats, and Chars are alloc to arr using `@alo`, a single instance of them has really no need to be allocated to the heap. Whereas, larger types like str/dat/struct/cls allow for both `@alo` arr init and `@alo::<type>` instance init.

## Logging
As we dev more, there is a need for a better compiler log sys to explain warnings/errors/etc. If a Zig log spawns it comes first, then a divider, then the Zcyther log.

For instance, here with the strict explicit nature of pointers and ref vals, we want a sys to warn about issues.



## Builtin Updates
`@getArgs` => `@args`
```
@main {
    args :: @args
    ...
}
```

## Update in Lambdas
`(params... => ret) {code...}`
```
foo := (bar: str, baz: i32 => _) { # use _ for void rets
    @pl(bar)
    @pl(baz)
}

fn x(y) {}

@main {
    x((z: f32 => f32) { # pass lambdas to func as ret val
        ret z * 53.2
    })
}
```
