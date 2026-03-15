# Cryptography — `@sodium::`

The `@sodium::` namespace wraps [libsodium](https://libsodium.org/) to provide password hashing and symmetric file encryption. The library is linked automatically when `@sodium::` usage is detected.

To use the alias syntax, import the library:

```
@import(sodium = @zcy.sodium)
```

After this import you can write `sodium.hash(…)` instead of `@sodium::hash(…)`.

> **Prerequisite:** libsodium must be installed on the system.
> - Fedora/RHEL: `sudo dnf install libsodium-devel`
> - Debian/Ubuntu: `sudo apt install libsodium-dev`
> - macOS: `brew install libsodium`

---

## Password Hashing

### `@sodium::hash(password)` — Hash a Password

Hashes `password` using **Argon2id** (the recommended algorithm for password storage). Returns the hash as a `str`.

```
@import(sodium = @zcy.sodium)

@main {
    pw   := "my-secret-password"
    hash := sodium.hash(pw)
    @pf("hash: {hash}\n")
}
```

The returned string is self-describing (includes algorithm, parameters, and salt) — you can store it directly in a database.

### `@sodium::hash_auth(plain, hash)` — Verify a Password

Returns `true` if `plain` matches the previously stored `hash`, `false` otherwise. Use this to verify login attempts.

```
@import(sodium = @zcy.sodium)

@main {
    pw   := "hunter2"
    hash := sodium.hash(pw)

    ok := sodium.hash_auth(pw, hash)
    if ok {
        @pl("password correct")
    } else {
        @pl("wrong password")
    }

    ok2 := sodium.hash_auth("wrong", hash)
    @pl(ok2)    # false
}
```

> **Security note:** `hash_auth` uses a constant-time comparison internally to prevent timing attacks.

---

## File Encryption

Both functions operate **in-place**: the original file is replaced with the encrypted (or decrypted) version, keeping the same filename and extension.

### `@sodium::enc_file(path, key)` — Encrypt a File

Encrypts the file at `path` using `key` (a `str`). The key is hashed with BLAKE2b internally, so any string length is accepted.

```
@import(sodium = @zcy.sodium)

@main {
    key := "my-encryption-key-32-bytes-long!"
    @fs::mkfile("secret.dat")
    # ... write data to secret.dat ...
    sodium.enc_file("secret.dat", key)
    @pl("file encrypted")
}
```

### `@sodium::dec_file(path, key)` — Decrypt a File

Decrypts the file at `path` using the same `key` that was used for encryption.

```
sodium.dec_file("secret.dat", key)
@pl("file decrypted")
```

> **Important:** Use the same key for encryption and decryption. If the key is wrong, decryption will produce garbage or fail silently — always verify file integrity after decryption in production code.

---

## Complete Example: Secure Password Vault

```
@import(sodium = @zcy.sodium)

@main {
    key := "vault-master-key-keep-this-safe!"

    # Simulate storing a user password
    raw_pw   := @input("Set password: ")
    pw_hash  := sodium.hash(raw_pw)

    # Write hash to encrypted vault file
    f := @fs::FileWriter::open("vault.enc") catch |_| { _ => { @sysexit(1) } }
    f.w(pw_hash) catch |_| {}
    f.cl()

    sodium.enc_file("vault.enc", key)
    @pl("Vault saved and encrypted.")

    # Later: verify login
    sodium.dec_file("vault.enc", key)

    g := @fs::FileReader::open("vault.enc") catch |_| { _ => { @sysexit(1) } }
    stored_hash := g.rall() catch |_| { _ => { "" } }
    g.cl()

    attempt := @input("Enter password to verify: ")
    if sodium.hash_auth(attempt, stored_hash) {
        @pl("Access granted.")
    } else {
        @pl("Access denied.")
    }

    # Re-encrypt after use
    sodium.enc_file("vault.enc", key)
}
```

---

## Quick Reference

| Call | Description |
|------|-------------|
| `sodium.hash(pw)` | Argon2id hash of `pw` → `str` |
| `sodium.hash_auth(pw, hash)` | Verify `pw` against stored `hash` → `bool` |
| `sodium.enc_file(path, key)` | Encrypt file in-place |
| `sodium.dec_file(path, key)` | Decrypt file in-place |

All four are also available as `@sodium::hash(…)` etc. without an import alias.
