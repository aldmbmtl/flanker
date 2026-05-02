# Plans

This folder contains architectural and migration plans for the Flanker project.

## Index

| File | Status | Summary |
|---|---|---|
| [python-authority-layer.md](./python-authority-layer.md) | Approved, not started | Replace the 9 core GDScript autoloads with a Python authority server. Godot keeps rendering; Python owns all game state and sync logic. Fixes multiplayer desync, entity registration fragility, win condition bugs, and untestable contracts. Est. 8–13 weeks. |

## How to read these plans

Each plan document contains:
- A problem statement with root cause analysis
- A decision log explaining why this approach was chosen over alternatives
- A phase-by-phase execution plan with clear exit criteria
- Code examples for the key patterns being introduced
- An effort estimate and risk register

## Adding a new plan

Create a new `.md` file in this folder and add a row to the index above.
