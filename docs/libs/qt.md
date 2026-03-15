# `@zcy.qt` — Qt5/Qt6 Widget Toolkit

**Type:** NativeSysPkg
**Install:** `dnf install qt6-qtbase-devel` / `apt install qt6-base-dev` / `pacman -S qt6-base` / `brew install qt`

```
@import(qt = @zcy.qt)
```

Qt uses a **polling model** — no callbacks. Check widget state each iteration of your event loop.

---

## Application

| Call | Returns | Description |
|------|---------|-------------|
| `qt.app()` | `app` | Create the Qt application object. Must be called before any widgets |
| `app.run()` | `void` | Enter Qt's event loop — blocks until all windows are closed |
| `app.process_events()` | `void` | Process all pending Qt events. Call each frame in a manual loop |
| `app.should_quit()` | `bool` | True when all windows have been closed |

---

## Window

| Call | Returns | Description |
|------|---------|-------------|
| `qt.window(title, w, h)` | `win` | Create a top-level window with the given title and pixel dimensions |
| `win.show()` | `void` | Make the window visible |
| `win.set_layout(layout)` | `void` | Set the root layout for the window |
| `win.set_title(title)` | `void` | Change the window title |
| `win.resize(w, h)` | `void` | Resize the window to `w` × `h` pixels |

---

## Widgets

### Label

| Call | Returns | Description |
|------|---------|-------------|
| `qt.label(text)` | `lbl` | Create a text label |
| `lbl.set_text(text)` | `void` | Update the label's displayed text |
| `lbl.text()` | `str` | Get the label's current text |

### Button

| Call | Returns | Description |
|------|---------|-------------|
| `qt.button(text)` | `btn` | Create a push button |
| `btn.clicked()` | `bool` | True once per click — resets after being read |
| `btn.set_text(text)` | `void` | Change the button label |

### Text Input

| Call | Returns | Description |
|------|---------|-------------|
| `qt.input()` | `field` | Create a single-line text input field |
| `field.text()` | `str` | Get the current input text |
| `field.set_text(text)` | `void` | Set the input text programmatically |
| `field.set_placeholder(text)` | `void` | Set the placeholder hint shown when empty |

### Checkbox

| Call | Returns | Description |
|------|---------|-------------|
| `qt.checkbox(text)` | `cb` | Create a labelled checkbox |
| `cb.checked()` | `bool` | Current checked state |
| `cb.set_checked(v)` | `void` | Set the checked state programmatically |
| `cb.changed()` | `bool` | True once per state change — resets after being read |

### Spin Box

| Call | Returns | Description |
|------|---------|-------------|
| `qt.spinbox(min, max)` | `spin` | Create an integer spin box with the given range |
| `spin.value()` | `i32` | Current value |
| `spin.set_value(v)` | `void` | Set the value programmatically |
| `spin.changed()` | `bool` | True once per value change — resets after being read |

---

## Layouts

Layouts arrange widgets. Pass a layout to `win.set_layout()`.

### Vertical Box — `qt.vbox()`

| Call | Returns | Description |
|------|---------|-------------|
| `qt.vbox()` | `layout` | Create a vertical box layout |
| `layout.add(item)` | `void` | Add a widget or nested layout |
| `layout.add_stretch()` | `void` | Insert a flexible spacer |
| `layout.set_spacing(n)` | `void` | Set pixel gap between items |
| `layout.set_margin(n)` | `void` | Set border margin in pixels |

### Horizontal Box — `qt.hbox()`

| Call | Returns | Description |
|------|---------|-------------|
| `qt.hbox()` | `layout` | Create a horizontal box layout |
| `layout.add(item)` | `void` | Add a widget or nested layout |
| `layout.add_stretch()` | `void` | Insert a flexible spacer |
| `layout.set_spacing(n)` | `void` | Set pixel gap between items |
| `layout.set_margin(n)` | `void` | Set border margin in pixels |

`add()` accepts both widgets and nested layouts — it detects the type automatically.

---

## Event Loop Pattern

```
@import(qt = @zcy.qt)

@main {
    app := qt.app()
    win := qt.window("My App", 400, 300)

    lbl := qt.label("Hello")
    btn := qt.button("Click me")

    layout := qt.vbox()
    layout.add(lbl)
    layout.add(btn)
    layout.set_spacing(8)
    layout.set_margin(16)

    win.set_layout(layout)
    win.show()

    while !app.should_quit() {
        app.process_events()
        if btn.clicked() {
            lbl.set_text("Clicked!")
        }
    }
}
```
