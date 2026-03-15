# SQLite3 — `db.*`

Zcythe provides first-class SQLite3 support through the `@zcy.sqlite` package. Import it with an alias and use the alias everywhere — no `@sqlite::` prefix at call sites.

```
@import(db = @zcy.sqlite)
```

The library is linked automatically (`-lsqlite3`) when `@zcy.sqlite` usage is detected.

> **Prerequisite:** SQLite3 must be installed on the system.
> - Fedora/RHEL: `sudo dnf install sqlite-devel`
> - Debian/Ubuntu: `sudo apt install libsqlite3-dev`
> - macOS: `brew install sqlite` (or use the system-provided version)

---

## Opening a Connection

### `db.open(path)` — Open or Create a Database

Opens the SQLite3 database at `path`. Use `":memory:"` for an in-memory database. Returns a `_Sqlite3` connection object.

```
@import(db = @zcy.sqlite)

@main {
    conn := db.open(":memory:")
    # ... use conn ...
    conn.close()
}
```

---

## Connection Methods

All methods are called on the connection object returned by `db.open(...)`.

### `conn.exec(sql)` — Execute SQL

Runs a SQL statement that returns no rows (e.g. `CREATE TABLE`, `INSERT`, `UPDATE`, `DELETE`).

```
conn.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)")
conn.exec("INSERT INTO users VALUES (1, 'Alice', 30)")
```

### `conn.prepare(sql)` — Prepare a Statement

Compiles a SQL query into a reusable prepared statement. Returns a `_Sqlite3Stmt` object.

```
stmt := conn.prepare("SELECT id, name, age FROM users ORDER BY age")
```

### `conn.errmsg()` — Get Last Error Message

Returns the most recent SQLite3 error message as a `str`.

```
@pl(conn.errmsg())
```

### `conn.close()` — Close the Connection

Releases the database connection. Always call this when done.

```
conn.close()
```

---

## Statement Methods

All methods are called on the `_Sqlite3Stmt` object returned by `conn.prepare(...)`.

### `stmt.step()` — Advance to Next Row

Returns `true` if a row is available, `false` when the result set is exhausted. Use in a `while` loop to iterate over rows.

```
while stmt.step() {
    # read columns here
}
```

### Column Accessors

| Method | Return type | Description |
|--------|-------------|-------------|
| `stmt.col_str(col)` | `str` | Text value of column `col` |
| `stmt.col_int(col)` | `i32` | Integer value of column `col` |
| `stmt.col_i64(col)` | `i64` | 64-bit integer value of column `col` |
| `stmt.col_f64(col)` | `f64` | Floating-point value of column `col` |
| `stmt.col_name(col)` | `str` | Column name at index `col` |
| `stmt.col_count()` | `i32` | Number of columns in the result set |

Column indices are zero-based.

```
while stmt.step() {
    id   := stmt.col_int(0)
    name := stmt.col_str(1)
    age  := stmt.col_int(2)
    @pf("id={id}  name={name}  age={age}\n")
}
```

### Bind Parameters

Bind values to `?` placeholders in prepared statements. Parameter indices are **one-based**.

| Method | Description |
|--------|-------------|
| `stmt.bind_str(idx, val)` | Bind a text value |
| `stmt.bind_int(idx, val)` | Bind an `i32` |
| `stmt.bind_i64(idx, val)` | Bind an `i64` |
| `stmt.bind_f64(idx, val)` | Bind a `f64` |
| `stmt.bind_null(idx)` | Bind SQL NULL |

```
stmt2 := conn.prepare("SELECT name FROM users WHERE age > ?")
stmt2.bind_int(1, 28)
while stmt2.step() {
    @pl(stmt2.col_str(0))
}
stmt2.finalize()
```

### `stmt.finalize()` — Release Statement

Destroys the prepared statement and frees its resources. Always call when done with a statement.

### `stmt.reset()` — Reset for Re-execution

Resets the statement back to its initial state so it can be executed again (with new bindings if desired).

---

## Complete Example

```
@import(db = @zcy.sqlite)

@main {
    conn := db.open(":memory:")

    # Schema
    conn.exec("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL)")
    conn.exec("INSERT INTO products VALUES (1, 'Widget', 9.99)")
    conn.exec("INSERT INTO products VALUES (2, 'Gadget', 24.50)")
    conn.exec("INSERT INTO products VALUES (3, 'Doohickey', 4.75)")

    # List all products
    stmt := conn.prepare("SELECT id, name, price FROM products ORDER BY price")
    while stmt.step() {
        id    := stmt.col_int(0)
        name  := stmt.col_str(1)
        price := stmt.col_f64(2)
        @pf("#{id}  {name}  ${price}\n")
    }
    stmt.finalize()

    # Filter by price
    @pl("--- under $10 ---")
    cheap := conn.prepare("SELECT name FROM products WHERE price < ?")
    cheap.bind_f64(1, 10.0)
    while cheap.step() {
        @pl(cheap.col_str(0))
    }
    cheap.finalize()

    conn.close()
}
```

Output:
```
#3  Doohickey  $4.75
#1  Widget  $9.99
#2  Gadget  $24.5
--- under $10 ---
Doohickey
Widget
```

---

## Quick Reference

| Call | Description |
|------|-------------|
| `db.open(path)` | Open/create database → connection |
| `conn.exec(sql)` | Run non-query SQL |
| `conn.prepare(sql)` | Compile query → statement |
| `conn.errmsg()` | Last error message → `str` |
| `conn.close()` | Close connection |
| `stmt.step()` | Advance to next row → `bool` |
| `stmt.col_str(i)` | Text column at index `i` |
| `stmt.col_int(i)` | Integer column at index `i` |
| `stmt.col_i64(i)` | 64-bit integer column at index `i` |
| `stmt.col_f64(i)` | Float column at index `i` |
| `stmt.col_name(i)` | Column name at index `i` |
| `stmt.col_count()` | Number of result columns |
| `stmt.bind_str(i, v)` | Bind text to parameter `i` (1-based) |
| `stmt.bind_int(i, v)` | Bind integer to parameter `i` |
| `stmt.bind_i64(i, v)` | Bind 64-bit integer to parameter `i` |
| `stmt.bind_f64(i, v)` | Bind float to parameter `i` |
| `stmt.bind_null(i)` | Bind NULL to parameter `i` |
| `stmt.finalize()` | Destroy statement |
| `stmt.reset()` | Reset for re-execution |
