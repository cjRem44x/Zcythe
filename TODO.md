# TODO

# XI Lib is a builtin graphics frame work that compiles into OpenGL
```
@main {
    custom_color := @xi::color(<R, G, B, A> | <HEX>) # make custom val color

    win := @xi::window(X, Y, TITLE) # init with i32, i32, str
    win.fps(N) # set FPS
    win.center() # center the window
    win.show() # launch window

    while win.loop {
        win.frame { # control frame
            # win.default passes the def val or setting
            close => {win.default}, # hits close
            min => {win.default}, # hits minimize
            max => {win.default}, # hits maximize
            open => {win.default} # opens window again after minimizing, opening from icon, or tabbing into
        }

        win.keys {
            key_press => {
                @pl(win.key.char)
                # make a full list of enum codes
                n := win.key.code
                
                if n == win.keyval.A {...}
                else if n == win.keyval.ESC {...}

                switch n {
                    win.keyval.B => {},
                    win.keyval.UP => {},
                    ...
                }
            },
            key_release => {},
            key_type => {},
        }

        win.mouse {# fill it in}
        # and what ever else listener needed.

        win.draw {
            win.clearbg(win.color.black) # windows have builtin 32 default colors
            win.text("Hello". x, y, w, h, custom_color)
            win.img(path, x, y, w, h)

            win.border(win.img(...), thicknes, color) # .border(comp, i32_thickness, colo_val) uses x,y,w,h of comp and adds border to it
        }
    }
}
```
