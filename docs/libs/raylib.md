# `@zcy.raylib` — 2D/3D Graphics (raylib)

**Type:** ZcytheAddLinkPkg
**Setup:** `zcy add raylib` (clones raylib-zig into `zcy-pkgs/` — no system install needed)

```
@import(rl = @zcy.raylib)
```

Zcythe provides convenience constructors via the `rl` alias. Everything — constructors, input helpers, and all raylib functions — is accessed through the alias.

---

## Zcythe Convenience Constructors

These are Zcythe-specific shorthands. They construct raylib value types without writing struct literals.

| Call | Returns | Description |
|------|---------|-------------|
| `rl.vec2(x, y)` | `rl.Vector2` | 2D vector `{ x, y }` — values cast to `f32` |
| `rl.vec3(x, y, z)` | `rl.Vector3` | 3D vector `{ x, y, z }` — values cast to `f32` |
| `rl.vec4(x, y, z, w)` | `rl.Vector4` | 4-component vector — values cast to `f32` |
| `rl.rect(x, y, w, h)` | `rl.Rectangle` | Rectangle `{ x, y, width, height }` — values cast to `f32` |
| `rl.color(r, g, b)` | `rl.Color` | RGB colour with alpha `255` — values cast to `u8` |
| `rl.color(r, g, b, a)` | `rl.Color` | RGBA colour — values cast to `u8` |
| `rl.cam2d(offset, target, rot, zoom)` | `rl.Camera2D` | 2D camera. `rot` defaults to `0`, `zoom` defaults to `1` if omitted |
| `rl.key(Name)` | `rl.KeyboardKey` | Keyboard key constant e.g. `rl.key(Space)`, `rl.key(LeftShift)` |
| `rl.btn(Name)` | `rl.MouseButton` | Mouse button constant e.g. `rl.btn(Left)`, `rl.btn(Right)` |
| `rl.gamepad(Name)` | `rl.GamepadButton` | Gamepad button constant e.g. `rl.gamepad(LeftFaceUp)` |

Key/button names use PascalCase: `Space`, `Enter`, `LeftShift`, `Left`, `Right`, `LeftFaceUp`, etc.

---

## Direct raylib API

Any raylib function not listed above is called directly through the alias:

```
rl.initWindow(800, 600, "Game")
rl.setTargetFPS(60)

while !rl.windowShouldClose() {
    rl.beginDrawing()
    rl.clearBackground(rl.Color.ray_white)
    rl.drawText("Hello", 10, 10, 20, rl.Color.black)
    rl.endDrawing()
}

rl.closeWindow()
```

Colour constants are accessed as `rl.Color.ray_white`, `rl.Color.black`, `rl.Color.red`, etc.

---

## Example — Moving Square

```
@import(rl = @zcy.raylib)

@main {
    rl.initWindow(640, 480, "Square")
    rl.setTargetFPS(60)

    x: f32 = 300.0
    y: f32 = 200.0

    while !rl.windowShouldClose() {
        if rl.isKeyDown(rl.key(Right)) { x += 3.0 }
        if rl.isKeyDown(rl.key(Left))  { x -= 3.0 }
        if rl.isKeyDown(rl.key(Up))    { y -= 3.0 }
        if rl.isKeyDown(rl.key(Down))  { y += 3.0 }

        rl.beginDrawing()
        rl.clearBackground(rl.Color.ray_white)
        rl.drawRectangle(@as(i32, @intFromFloat(x)), @as(i32, @intFromFloat(y)), 40, 40, rl.Color.red)
        rl.endDrawing()
    }

    rl.closeWindow()
}
```
