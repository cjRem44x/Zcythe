# Raylib — `rl.*`

> **Note:** For most graphical applications, `@xi::` is the recommended built-in graphics framework — no import or package install needed. See [Graphics & Windowing — `@xi::`](17_xi.md). The raw `rl.*` API documented here is still fully supported for direct raylib access and 3D use cases.

Zcythe has first-class support for [raylib](https://www.raylib.com/), a simple 2D/3D game and graphics library. Import it with:

```
@import(rl = @zcy.raylib)
```

Add it to your project with:

```
zcy add raylib
```

After importing, **everything** is accessed through the `rl` alias — constructors, input helpers, and all raylib functions alike. There is no `@rl::` prefix needed at call sites.

---

## Constructors

These helpers produce raylib struct values with a concise syntax.

### Vectors

```
v2 := rl.vec2(1.0, 2.0)                  # rl.Vector2
v3 := rl.vec3(1.0, 2.0, 3.0)             # rl.Vector3
v4 := rl.vec4(1.0, 2.0, 3.0, 1.0)        # rl.Vector4
```

### Rectangle

```
rect := rl.rect(x, y, width, height)      # rl.Rectangle
```

### Color

```
red  := rl.color(255, 0, 0)               # opaque red
semi := rl.color(0, 0, 255, 128)          # semi-transparent blue
```

Named colors are available as constants:

```
bg := rl.Color.ray_white
fg := rl.Color.dark_gray
```

### Camera 2D

```
cam := rl.cam2d(offset, target)
cam := rl.cam2d(offset, target, rotation, zoom)
```

---

## Input

### Keyboard

```
if rl.isKeyDown(rl.key(Space)) {
    @pl("space held")
}

if rl.isKeyPressed(rl.key(Enter)) {
    @pl("enter pressed")
}
```

Common key names: `Space`, `Enter`, `Escape`, `Left`, `Right`, `Up`, `Down`, `A`–`Z`, `Zero`–`Nine`, `F1`–`F12`.

### Mouse

```
if rl.isMouseButtonDown(rl.btn(Left)) {
    pos := rl.getMousePosition()
    @pf("click at ({pos.x}, {pos.y})\n")
}
```

Mouse button names: `Left`, `Right`, `Middle`.

### Gamepad

```
if rl.isGamepadButtonDown(0, rl.gamepad(LeftFaceUp)) {
    @pl("D-pad up")
}
```

---

## Full Raylib API

Any raylib function is called directly through the `rl` alias:

```
rl.initWindow(800, 600, "My Game")
rl.setTargetFPS(60)

while !rl.windowShouldClose() {
    rl.beginDrawing()
    rl.clearBackground(rl.Color.ray_white)
    rl.drawText("Hello!", 200, 250, 40, rl.Color.dark_gray)
    rl.endDrawing()
}

rl.closeWindow()
```

String arguments are automatically converted to null-terminated C strings for raylib compatibility.

---

## Complete Example: Bouncing Ball

```
@import(rl = @zcy.raylib)

@main {
    W :: 800
    H :: 600

    rl.initWindow(W, H, "Bouncing Ball")
    rl.setTargetFPS(60)

    bx : f32 = 400.0
    by : f32 = 300.0
    vx : f32 = 4.0
    vy : f32 = 3.0
    r  : f32 = 20.0

    while !rl.windowShouldClose() {
        # Update
        bx += vx
        by += vy
        if bx - r < 0.0 or bx + r > @f32(W) { vx = -vx }
        if by - r < 0.0 or by + r > @f32(H) { vy = -vy }

        # Draw
        rl.beginDrawing()
        rl.clearBackground(rl.Color.ray_white)
        rl.drawCircle(@i32(bx), @i32(by), r, rl.color(200, 50, 50))
        rl.drawFPS(10, 10)
        rl.endDrawing()
    }

    rl.closeWindow()
}
```

---

## Complete Example: Color Picker

```
@import(rl = @zcy.raylib)

@main {
    rl.initWindow(400, 400, "Color Picker")
    rl.setTargetFPS(60)

    hue : f32 = 0.0

    while !rl.windowShouldClose() {
        if rl.isKeyDown(rl.key(Right)) { hue += 1.0 }
        if rl.isKeyDown(rl.key(Left))  { hue -= 1.0 }
        if hue > 360.0 { hue = 0.0 }
        if hue <   0.0 { hue = 360.0 }

        col := rl.colorFromHSV(hue, 1.0, 1.0)

        rl.beginDrawing()
        rl.clearBackground(col)
        rl.drawText("Use ← → to change hue", 60, 180, 20, rl.Color.white)
        rl.endDrawing()
    }

    rl.closeWindow()
}
```

---

## Quick Reference

| Call | Result type | Description |
|------|-------------|-------------|
| `rl.vec2(x, y)` | `rl.Vector2` | 2D vector |
| `rl.vec3(x, y, z)` | `rl.Vector3` | 3D vector |
| `rl.vec4(x, y, z, w)` | `rl.Vector4` | 4D vector |
| `rl.rect(x, y, w, h)` | `rl.Rectangle` | Rectangle |
| `rl.color(r, g, b)` | `rl.Color` | Opaque color |
| `rl.color(r, g, b, a)` | `rl.Color` | Color with alpha |
| `rl.cam2d(off, tgt)` | `rl.Camera2D` | 2D camera |
| `rl.key(Name)` | `rl.KeyboardKey` | Keyboard key constant |
| `rl.btn(Name)` | `rl.MouseButton` | Mouse button constant |
| `rl.gamepad(Name)` | `rl.GamepadButton` | Gamepad button constant |
| `rl.anyFunc(…)` | — | Any other raylib function |
