# `@zcy.sqlite` — SQLite3 Embedded Database

**Type:** NativeSysPkg
**Install:** `dnf install sqlite-devel` / `apt install libsqlite3-dev` / `pacman -S sqlite` / `brew install sqlite`

```
@import(db = @zcy.sqlite)
```

---

## Connection

| Call | Returns | Description |
|------|---------|-------------|
| `db.open(path)` | `conn` | Open or create a database at `path`. Use `":memory:"` for an in-memory database |
| `conn.exec(sql)` | `void` | Execute a SQL statement that returns no rows (`CREATE`, `INSERT`, `UPDATE`, `DELETE`) |
| `conn.prepare(sql)` | `stmt` | Compile a SQL query into a reusable prepared statement |
| `conn.errmsg()` | `str` | Most recent SQLite3 error message |
| `conn.close()` | `void` | Close the connection and release its resources |

---

## Statement — Stepping

| Call | Returns | Description |
|------|---------|-------------|
| `stmt.step()` | `bool` | Advance to the next row. Returns `true` if a row is available, `false` when exhausted. Use in a `while` loop |
| `stmt.reset()` | `void` | Reset the statement to its initial state so it can be re-executed |
| `stmt.finalize()` | `void` | Destroy the prepared statement and free its resources. Always call when done |

---

## Statement — Column Accessors

Column indices are **zero-based**.

| Call | Returns | Description |
|------|---------|-------------|
| `stmt.col_str(i)` | `str` | Text value of column `i` |
| `stmt.col_int(i)` | `i32` | Integer value of column `i` |
| `stmt.col_i64(i)` | `i64` | 64-bit integer value of column `i` |
| `stmt.col_f64(i)` | `f64` | Floating-point value of column `i` |
| `stmt.col_name(i)` | `str` | Column name at index `i` |
| `stmt.col_count()` | `i32` | Number of columns in the result set |

---

## Statement — Bind Parameters

Bind values to `?` placeholders. Parameter indices are **one-based**.

| Call | Returns | Description |
|------|---------|-------------|
| `stmt.bind_str(i, val)` | `void` | Bind a text value to parameter `i` |
| `stmt.bind_int(i, val)` | `void` | Bind an `i32` to parameter `i` |
| `stmt.bind_i64(i, val)` | `void` | Bind an `i64` to parameter `i` |
| `stmt.bind_f64(i, val)` | `void` | Bind a `f64` to parameter `i` |
| `stmt.bind_null(i)` | `void` | Bind SQL NULL to parameter `i` |

---

## Example

```
@import(db = @zcy.sqlite)

@main {
    conn := db.open(":memory:")
    conn.exec("CREATE TABLE users (name TEXT, age INTEGER)")
    conn.exec("INSERT INTO users VALUES ('Alice', 30)")
    conn.exec("INSERT INTO users VALUES ('Bob', 25)")

    stmt := conn.prepare("SELECT name, age FROM users WHERE age > ? ORDER BY age")
    stmt.bind_int(1, 20)
    while stmt.step() {
        name := stmt.col_str(0)
        age  := stmt.col_int(1)
        @pf("{name}: {age}\n")
    }
    stmt.finalize()
    conn.close()
}
```
