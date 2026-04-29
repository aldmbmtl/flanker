# Contributing to Flankers

## Fork Resync (Important — History Rewrite)

This repo underwent a history rewrite (git-filter-repo) to remove large `.zip` files.
**If you forked before April 2026, your fork has diverged history.**

### Option A: Fresh Fork (Recommended)
1. Delete your fork on GitHub
2. Re-fork `aldmbmtl/flanker`

### Option B: Reset Existing Fork
```bash
git fetch origin
git reset --hard origin/main
git push --force-with-lease
```
⚠️ This destroys any unmerged commits in your fork.

---

## How to Contribute

1. **Fork** the repo
2. **Create a branch**: `git checkout -b feature/my-feature`
3. **Make changes** following the [Code Style](#code-style) rules
4. **Run tests**: `make test` — must pass with zero failures
5. **Commit**: use conventional commits (`feat:`, `fix:`, `refactor:`)
6. **Push**: `git push origin feature/my-feature`
7. **Open PR** against `aldmbmtl/flanker:main`

---

## Code Style

- **GDScript**: explicit types on loop variables, array reads, ternary results
  ```gdscript
  var x: float = some_array[i]   # correct
  # var x := some_array[i]        # breaks — untyped array
  ```
- **Base classes DO NOT MODIFY** without explicit instruction:
  - `BasePlayer.gd`, `PlayerManager.gd`, `TowerBase.gd`, `ProjectileBase.gd`, `MinionBase.gd`
- **No comments** unless explicitly requested
- **No editor GUI** — edit `.tscn`/`.tres` files by hand
- **Always `add_child` before `global_position`**

---

## Testing (MANDATORY)

**Run `make test` after every code change — no exceptions.**

```bash
make test
```

Requirements:
- Zero failing tests (pending/risky allowed — must be documented known bugs)
- New features/bug fixes require new tests
- Never silence failures with `pending()` without justification

Current baseline: **591 passing, 8 pending/risky**

---

## Pull Request Guidelines

- PR against `main` branch
- Include: what changed, why, how to test
- Link any related issues
- Ensure `make test` passes before requesting review
- Keep PRs focused — one feature/fix per PR

---

## Development Setup

```bash
git clone https://github.com/<you>/flanker.git
cd flanker
make test   # verify setup
```

Requirements: Godot 4.6.2+, Vulkan 1.1+ GPU

---

## License

This project currently has no license. Consider adding one before distributing.
