# `@zcy.sodium` — Cryptography (libsodium)

**Type:** NativeSysPkg
**Install:** `dnf install libsodium-devel` / `apt install libsodium-dev` / `pacman -S libsodium` / `brew install libsodium`

```
@import(sodium = @zcy.sodium)
```

---

## Function Calls

| Call | Returns | Description |
|------|---------|-------------|
| `sodium.hash(password)` | `str` | Hash a password using Argon2id (interactive parameters). Returns an encoded hash string suitable for storage |
| `sodium.hash_auth(plain, hash)` | `bool` | Verify a plaintext password against a hash produced by `sodium.hash()`. Returns `true` if they match |
| `sodium.enc_file(path, key)` | `void` | Encrypt a file in-place using the given key string. Replaces the original file contents |
| `sodium.dec_file(path, key)` | `void` | Decrypt a file in-place using the given key string. Reverses `sodium.enc_file()` |

---

## Notes

- `sodium.hash()` uses **Argon2id** with interactive memory/ops limits — suitable for login flows, not bulk operations
- `sodium.hash_auth()` is constant-time to prevent timing attacks
- `enc_file` / `dec_file` operate on the filesystem path directly — the original file is overwritten

---

## Example

```
@import(sodium = @zcy.sodium)

@main {
    pw   := @input("Enter password: ")
    hash := sodium.hash(pw)
    @pf("stored hash: {hash}\n")

    guess := @input("Verify: ")
    if sodium.hash_auth(guess, hash) {
        @pl("OK")
    } else {
        @pl("wrong password")
    }

    sodium.enc_file("vault.dat", "my-secret-key")
    # vault.dat is now encrypted
    sodium.dec_file("vault.dat", "my-secret-key")
    # vault.dat restored
}
```
