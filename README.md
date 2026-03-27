# MiraApp

A generic iOS client for any AI agent that uses the [MiraBridge](../MiraBridge) protocol. Control your local agent from your iPhone — no server required.

## What It Does

MiraApp is a ready-to-use iPhone app that connects to any agent running on your Mac via iCloud Drive. It provides:

- **Chat interface** — send requests, have discussions, see agent responses
- **Todo list** — shared between you and the agent
- **Artifacts browser** — browse files the agent produces (writings, reports, etc.)
- **Real-time status** — see if the agent is online, busy, or idle
- **Notifications** — get notified when the agent needs your input or finishes a task

## Setup

### Prerequisites

- iPhone running iOS 17+
- A Mac running a Python agent using [MiraBridge](../MiraBridge)
- Both devices on the same Apple ID with iCloud Drive enabled

### Building

1. Clone this repo alongside MiraBridge:
   ```
   your-workspace/
   ├── MiraBridge/    ← clone this first
   └── MiraApp/       ← this repo
   ```

2. Open `Mira.xcodeproj` in Xcode
3. The MiraBridge Swift package is referenced as a local dependency at `../MiraBridge/swift`
4. Build and run on your device

### First Launch

1. The app asks you to select your Bridge folder on iCloud Drive
2. Choose the folder your agent writes to (the one with `heartbeat.json`)
3. Select your profile (defined in `profiles.json` by the agent)
4. You're connected — the app starts polling for updates

## For Agent Developers

MiraApp works with any agent that follows the MiraBridge protocol. Your agent just needs to:

```python
from mira_bridge import Bridge

bridge = Bridge("/path/to/icloud/bridge", user_id="default")

# Write a profiles.json so the app knows about you
profiles = [{"id": "default", "displayName": "My Agent", "agentName": "Agent"}]

# Start your loop
while True:
    bridge.heartbeat()
    for cmd in bridge.poll_commands():
        # handle commands...
    time.sleep(30)
```

The app automatically adapts to your agent's name, shows your items, and routes commands back.

## Customization

The app uses a tag-based color system for feed items. Tag your items to get appropriate colors:

| Tags | Color | Icon |
|------|-------|------|
| `explore`, `briefing`, `news` | Blue | Globe |
| `analysis`, `market`, `research` | Green | Chart |
| `alert`, `error`, `crash` | Amber | Warning |
| `reflect`, `journal` | Gold | Brain |

## Architecture

```
MiraApp (this repo)
   ↓ imports
MiraBridge (Swift package — models, sync, commands)
   ↓ iCloud files
Your Agent (Python — uses mira_bridge.Bridge)
```

## License

MIT
