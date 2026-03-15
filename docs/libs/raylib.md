# `@zcy.raylib` — 2D/3D Graphics (raylib)

**Type:** ZcytheAddLinkPkg
**Setup:** `zcy add raylib` (clones raylib-zig into `zcy-pkgs/` — no system install needed)

```
@import(rl = @zcy.raylib)
```

---

## Structs

Construct these with Zcythe convenience helpers or with struct literal syntax.

| Type | Fields | Description |
|------|--------|-------------|
| `rl.Vector2` | `x, y: f32` | 2D vector |
| `rl.Vector3` | `x, y, z: f32` | 3D vector |
| `rl.Vector4` | `x, y, z, w: f32` | 4-component vector / quaternion |
| `rl.Color` | `r, g, b, a: u8` | RGBA colour |
| `rl.Rectangle` | `x, y, width, height: f32` | Axis-aligned rectangle |
| `rl.Camera2D` | `offset, target: Vector2`, `rotation, zoom: f32` | 2D camera |
| `rl.Camera3D` | `position, target, up: Vector3`, `fovy: f32`, `projection: CameraProjection` | 3D camera |
| `rl.Texture` | `id: u32`, `width, height, mipmaps, format: i32` | GPU texture |
| `rl.Image` | `data: *anyopaque`, `width, height, mipmaps, format: i32` | CPU-side image |
| `rl.Mesh` | *(managed)* | Vertex/index buffers for a 3D mesh |
| `rl.Model` | `transform: Matrix`, `meshCount, materialCount: i32`, `meshes, materials: *` | 3D model |
| `rl.BoundingBox` | `min, max: Vector3` | Axis-aligned bounding box |
| `rl.Ray` | `position, direction: Vector3` | Ray for 3D picking |
| `rl.RayCollision` | `hit: bool`, `distance: f32`, `point, normal: Vector3` | Ray–mesh hit result |

---

## Zcythe Convenience Constructors

Zcythe-specific shorthands that build common structs without writing field names.

| Call | Returns | Description |
|------|---------|-------------|
| `rl.vec2(x, y)` | `rl.Vector2` | 2D vector — values cast to `f32` |
| `rl.vec3(x, y, z)` | `rl.Vector3` | 3D vector — values cast to `f32` |
| `rl.vec4(x, y, z, w)` | `rl.Vector4` | 4-component vector — values cast to `f32` |
| `rl.rect(x, y, w, h)` | `rl.Rectangle` | Rectangle — values cast to `f32` |
| `rl.color(r, g, b)` | `rl.Color` | RGB colour, alpha = 255 |
| `rl.color(r, g, b, a)` | `rl.Color` | RGBA colour |
| `rl.cam2d(offset, target, rot, zoom)` | `rl.Camera2D` | 2D camera (`rot` / `zoom` optional, default 0 / 1) |
| `rl.key(Name)` | `rl.KeyboardKey` | Keyboard key constant — PascalCase name e.g. `rl.key(Space)` |
| `rl.btn(Name)` | `rl.MouseButton` | Mouse button constant e.g. `rl.btn(Left)` |
| `rl.gamepad(Name)` | `rl.GamepadButton` | Gamepad button constant e.g. `rl.gamepad(LeftFaceUp)` |

For `Camera3D`, use a struct literal:

```
cam := rl.Camera3D{
    .position   = rl.vec3(10.0, 8.0, 10.0),
    .target     = rl.vec3(0.0, 0.0, 0.0),
    .up         = rl.vec3(0.0, 1.0, 0.0),
    .fovy       = 45.0,
    .projection = .perspective,
}
```

---

## Window

| Call | Returns | Description |
|------|---------|-------------|
| `rl.initWindow(w, h, title)` | `void` | Open a window of size `w × h` with the given title |
| `rl.closeWindow()` | `void` | Close the window and free resources |
| `rl.windowShouldClose()` | `bool` | True when the user closes the window or presses Escape |
| `rl.setTargetFPS(fps)` | `void` | Cap the frame rate |
| `rl.setWindowTitle(title)` | `void` | Change the window title at runtime |
| `rl.setWindowSize(w, h)` | `void` | Resize the window |
| `rl.getScreenWidth()` | `i32` | Current window width in pixels |
| `rl.getScreenHeight()` | `i32` | Current window height in pixels |
| `rl.isWindowResized()` | `bool` | True if the window was resized this frame |
| `rl.toggleFullscreen()` | `void` | Toggle fullscreen mode |
| `rl.disableCursor()` | `void` | Hide and lock cursor (for FPS-style camera) |
| `rl.enableCursor()` | `void` | Restore cursor visibility |
| `rl.hideCursor()` | `void` | Hide cursor without locking it |
| `rl.showCursor()` | `void` | Unhide cursor |

---

## Drawing — Frame Control

| Call | Returns | Description |
|------|---------|-------------|
| `rl.beginDrawing()` | `void` | Start the render frame |
| `rl.endDrawing()` | `void` | End the render frame and swap buffers |
| `rl.clearBackground(color)` | `void` | Fill the framebuffer with `color` |
| `rl.beginMode2D(cam)` | `void` | Enter 2D camera transform |
| `rl.endMode2D()` | `void` | Leave 2D camera transform |
| `rl.beginMode3D(cam)` | `void` | Enter 3D projection with `cam: Camera3D` |
| `rl.endMode3D()` | `void` | Leave 3D projection |
| `rl.beginScissorMode(x, y, w, h)` | `void` | Restrict drawing to a pixel rectangle |
| `rl.endScissorMode()` | `void` | Remove scissor restriction |

---

## Drawing — 2D Shapes

| Call | Returns | Description |
|------|---------|-------------|
| `rl.drawPixel(x, y, color)` | `void` | Draw a single pixel |
| `rl.drawLine(x1, y1, x2, y2, color)` | `void` | Draw a line between two points |
| `rl.drawLineV(start, end, color)` | `void` | Line with `Vector2` endpoints |
| `rl.drawLineEx(start, end, thick, color)` | `void` | Thick line |
| `rl.drawCircle(cx, cy, r, color)` | `void` | Filled circle (integer centre) |
| `rl.drawCircleV(center, r, color)` | `void` | Filled circle with `Vector2` centre |
| `rl.drawCircleLines(cx, cy, r, color)` | `void` | Circle outline |
| `rl.drawRectangle(x, y, w, h, color)` | `void` | Filled rectangle (integer coords) |
| `rl.drawRectangleV(pos, size, color)` | `void` | Filled rectangle with `Vector2` pos + size |
| `rl.drawRectangleRec(rec, color)` | `void` | Filled rectangle from `Rectangle` |
| `rl.drawRectangleLines(x, y, w, h, color)` | `void` | Rectangle outline |
| `rl.drawRectangleLinesEx(rec, thick, color)` | `void` | Thick rectangle outline |
| `rl.drawRectangleRounded(rec, round, segs, color)` | `void` | Filled rounded rectangle |
| `rl.drawTriangle(v1, v2, v3, color)` | `void` | Filled triangle with `Vector2` vertices |
| `rl.drawTriangleLines(v1, v2, v3, color)` | `void` | Triangle outline |
| `rl.drawPoly(center, sides, r, rot, color)` | `void` | Regular polygon |

---

## Drawing — Text

| Call | Returns | Description |
|------|---------|-------------|
| `rl.drawText(text, x, y, size, color)` | `void` | Draw text with the default font |
| `rl.drawFPS(x, y)` | `void` | Draw the current FPS counter |
| `rl.measureText(text, size)` | `i32` | Width of `text` in pixels at `size` |

---

## Drawing — Textures & Images

| Call | Returns | Description |
|------|---------|-------------|
| `rl.loadTexture(path)` | `rl.Texture` | Load a texture from an image file |
| `rl.unloadTexture(tex)` | `void` | Free a texture |
| `rl.drawTexture(tex, x, y, tint)` | `void` | Draw texture at integer position |
| `rl.drawTextureV(tex, pos, tint)` | `void` | Draw texture at `Vector2` position |
| `rl.drawTextureEx(tex, pos, rot, scale, tint)` | `void` | Draw texture with rotation and scale |
| `rl.drawTextureRec(tex, src, pos, tint)` | `void` | Draw a sub-region of a texture |
| `rl.loadImage(path)` | `rl.Image` | Load an image from file (CPU side) |
| `rl.unloadImage(img)` | `void` | Free a CPU image |
| `rl.loadTextureFromImage(img)` | `rl.Texture` | Upload an image to the GPU |

---

## Drawing — 3D Geometry

| Call | Returns | Description |
|------|---------|-------------|
| `rl.drawGrid(slices, spacing)` | `void` | Draw an XZ-plane grid centred at origin |
| `rl.drawLine3D(start, end, color)` | `void` | Line between two `Vector3` points |
| `rl.drawPoint3D(pos, color)` | `void` | Single point in 3D space |
| `rl.drawCube(pos, w, h, d, color)` | `void` | Solid cube centred at `pos` |
| `rl.drawCubeV(pos, size, color)` | `void` | Solid cube with `Vector3` size |
| `rl.drawCubeWires(pos, w, h, d, color)` | `void` | Cube wireframe |
| `rl.drawCubeWiresV(pos, size, color)` | `void` | Cube wireframe with `Vector3` size |
| `rl.drawSphere(pos, r, color)` | `void` | Solid sphere |
| `rl.drawSphereEx(pos, r, rings, slices, color)` | `void` | Sphere with explicit ring/slice count |
| `rl.drawSphereWires(pos, r, rings, slices, color)` | `void` | Sphere wireframe |
| `rl.drawCylinder(pos, rTop, rBot, h, slices, color)` | `void` | Solid cylinder / cone |
| `rl.drawCylinderWires(pos, rTop, rBot, h, slices, color)` | `void` | Cylinder wireframe |
| `rl.drawPlane(pos, size, color)` | `void` | Flat XZ-plane quad at `pos` with `Vector2` `size` |
| `rl.drawRay(ray, color)` | `void` | Visual ray (line from origin along direction) |

---

## Drawing — 3D Models

| Call | Returns | Description |
|------|---------|-------------|
| `rl.genMeshCube(w, h, d)` | `rl.Mesh` | Generate a cube mesh |
| `rl.genMeshSphere(r, rings, slices)` | `rl.Mesh` | Generate a sphere mesh |
| `rl.genMeshPlane(w, d, resX, resZ)` | `rl.Mesh` | Generate a flat plane mesh |
| `rl.genMeshCylinder(r, h, slices)` | `rl.Mesh` | Generate a cylinder mesh |
| `rl.loadModelFromMesh(mesh)` | `rl.Model` | Upload a mesh to the GPU as a model |
| `rl.loadModel(path)` | `rl.Model` | Load a model from an OBJ / GLTF / etc. file |
| `rl.unloadModel(model)` | `void` | Free a model |
| `rl.drawModel(model, pos, scale, tint)` | `void` | Draw a model |
| `rl.drawModelEx(model, pos, axis, angle, scale, tint)` | `void` | Draw model with rotation axis + angle |
| `rl.drawModelWires(model, pos, scale, tint)` | `void` | Draw model wireframe |
| `rl.getModelBoundingBox(model)` | `rl.BoundingBox` | Axis-aligned bounding box of a model |

---

## Input — Keyboard

Key names are PascalCase identifiers passed to `rl.key(Name)`.

| Call | Returns | Description |
|------|---------|-------------|
| `rl.isKeyDown(key)` | `bool` | True while the key is held |
| `rl.isKeyPressed(key)` | `bool` | True on the frame the key was first pressed |
| `rl.isKeyReleased(key)` | `bool` | True on the frame the key was released |
| `rl.isKeyUp(key)` | `bool` | True while the key is not held |
| `rl.getKeyPressed()` | `i32` | Key code of the most recently pressed key (0 if none) |

Common key names: `Up`, `Down`, `Left`, `Right`, `W`, `A`, `S`, `D`, `Space`, `Enter`, `Escape`, `LeftShift`, `LeftControl`, `LeftAlt`, `F1`–`F12`, `Zero`–`Nine`, `A`–`Z`.

---

## Input — Mouse

| Call | Returns | Description |
|------|---------|-------------|
| `rl.isMouseButtonDown(btn)` | `bool` | True while the button is held |
| `rl.isMouseButtonPressed(btn)` | `bool` | True on the frame the button was first pressed |
| `rl.isMouseButtonReleased(btn)` | `bool` | True on the frame the button was released |
| `rl.getMousePosition()` | `rl.Vector2` | Current cursor position in window space |
| `rl.getMouseDelta()` | `rl.Vector2` | Cursor movement since last frame |
| `rl.getMouseWheelMove()` | `f32` | Scroll wheel delta this frame |
| `rl.setMousePosition(x, y)` | `void` | Warp the cursor to a position |

Button names: `Left`, `Right`, `Middle`, `Side`, `Extra`, `Forward`, `Back`.

---

## Input — Gamepad

| Call | Returns | Description |
|------|---------|-------------|
| `rl.isGamepadAvailable(pad)` | `bool` | True if gamepad `pad` (0-based) is connected |
| `rl.isGamepadButtonDown(pad, btn)` | `bool` | True while a button is held |
| `rl.isGamepadButtonPressed(pad, btn)` | `bool` | True on first-press frame |
| `rl.isGamepadButtonReleased(pad, btn)` | `bool` | True on release frame |
| `rl.getGamepadAxisMovement(pad, axis)` | `f32` | Axis value in `−1.0 … 1.0` |

---

## Camera Utilities

| Call | Returns | Description |
|------|---------|-------------|
| `rl.updateCamera(cam, mode)` | `void` | Auto-update a `*Camera3D` with a built-in movement mode |
| `rl.getCameraForward(cam)` | `rl.Vector3` | Forward direction vector of `*Camera3D` |
| `rl.getCameraRight(cam)` | `rl.Vector3` | Right direction vector |
| `rl.getCameraUp(cam)` | `rl.Vector3` | Up direction vector |
| `rl.getScreenToWorldRay(pos, cam)` | `rl.Ray` | Screen pixel → world ray for picking |
| `rl.getWorldToScreen(pos, cam)` | `rl.Vector2` | World position → screen pixel |

Camera modes for `updateCamera`: `.free`, `.orbital`, `.first_person`, `.third_person`.

---

## 3D Collision

| Call | Returns | Description |
|------|---------|-------------|
| `rl.getRayCollisionBox(ray, box)` | `rl.RayCollision` | Ray vs axis-aligned bounding box |
| `rl.getRayCollisionMesh(ray, mesh, transform)` | `rl.RayCollision` | Ray vs mesh |
| `rl.getRayCollisionSphere(ray, center, r)` | `rl.RayCollision` | Ray vs sphere |
| `rl.checkCollisionBoxes(a, b)` | `bool` | AABB vs AABB |
| `rl.checkCollisionSpheres(c1, r1, c2, r2)` | `bool` | Sphere vs sphere |
| `rl.checkCollisionRecs(a, b)` | `bool` | 2D rectangle vs rectangle |
| `rl.checkCollisionCircles(c1, r1, c2, r2)` | `bool` | 2D circle vs circle |

---

## Timing

| Call | Returns | Description |
|------|---------|-------------|
| `rl.getFrameTime()` | `f32` | Seconds elapsed since the last frame (delta time) |
| `rl.getTime()` | `f64` | Seconds elapsed since `initWindow` |
| `rl.getFPS()` | `i32` | Current frames per second |

---

## Colour Utilities

| Call | Returns | Description |
|------|---------|-------------|
| `rl.colorBrightness(color, factor)` | `rl.Color` | Adjust brightness (`factor` in `−1.0 … 1.0`) |
| `rl.colorContrast(color, factor)` | `rl.Color` | Adjust contrast |
| `rl.colorTint(color, tint)` | `rl.Color` | Multiply colour channels by `tint` |
| `rl.colorAlpha(color, alpha)` | `rl.Color` | Set alpha (`0.0 … 1.0`) |
| `rl.fade(color, alpha)` | `rl.Color` | Alias for `colorAlpha` |
| `rl.colorToHSV(color)` | `rl.Vector3` | Convert to HSV |
| `rl.colorFromHSV(h, s, v)` | `rl.Color` | Convert from HSV |

---

## Colour Constants

Accessed as `rl.Color.<name>`:

| Constant | RGBA |
|----------|------|
| `ray_white` | 245 245 245 255 |
| `white` | 255 255 255 255 |
| `black` | 0 0 0 255 |
| `blank` | 0 0 0 0 |
| `light_gray` | 200 200 200 255 |
| `gray` | 130 130 130 255 |
| `dark_gray` | 80 80 80 255 |
| `yellow` | 253 249 0 255 |
| `gold` | 255 203 0 255 |
| `orange` | 255 161 0 255 |
| `red` | 230 41 55 255 |
| `maroon` | 190 33 55 255 |
| `green` | 0 228 48 255 |
| `lime` | 0 158 47 255 |
| `dark_green` | 0 117 44 255 |
| `sky_blue` | 102 191 255 255 |
| `blue` | 0 121 241 255 |
| `dark_blue` | 0 82 172 255 |
| `purple` | 200 122 255 255 |
| `violet` | 135 60 190 255 |
| `dark_purple` | 112 31 126 255 |
| `beige` | 211 176 131 255 |
| `brown` | 127 106 79 255 |
| `dark_brown` | 76 63 47 255 |
| `pink` | 255 109 194 255 |
| `magenta` | 255 0 255 255 |

---

## Enums

| Type | Values |
|------|--------|
| `rl.CameraProjection` | `.perspective`, `.orthographic` |
| `rl.CameraMode` | `.free`, `.orbital`, `.first_person`, `.third_person` |
| `rl.KeyboardKey` | Use `rl.key(Name)` — see Input section |
| `rl.MouseButton` | Use `rl.btn(Name)` — see Input section |
| `rl.GamepadButton` | Use `rl.gamepad(Name)` — see Input section |
| `rl.TextureFilter` | `.point`, `.bilinear`, `.trilinear`, `.anisotropic_4x`, `.anisotropic_8x`, `.anisotropic_16x` |
| `rl.BlendMode` | `.alpha`, `.additive`, `.multiplied`, `.add_colors`, `.subtract_colors`, `.custom` |
