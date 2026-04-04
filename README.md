# MiraApp

A SwiftUI iPhone app for controlling any AI agent that uses the [MiraBridge](../MiraBridge) protocol. Chat with your agent, monitor your health, manage tasks, and browse artifacts -- no server required.

## Tabs

- **Home** -- chat interface for requests and discussions, agent status, daily feeds (briefings, sparks, analysis)
- **Todo** -- shared todo list between you and the agent, with priority and follow-ups
- **Health** -- dashboard with Apple Health + Oura Ring data, daily GPT health insights, anomaly alerts, trend charts, symptom/checkup input
- **Artifacts** -- browse files the agent produces (writings, reports, research, audio)
- **Settings** -- profile selection, bridge folder, notification preferences

## Health Tab

The health tab connects two data sources:

1. **Apple HealthKit** -- reads weight, sleep, steps, heart rate, HRV, blood oxygen, body fat directly from the Health app
2. **Bridge summary** -- reads Oura Ring scores, stress/recovery data, and agent-generated notes from `health_summary.json`

Features:
- Dashboard cards for 16 metrics (vitals, body composition, Oura scores, activity)
- 30-day trend charts (weight, sleep, HRV, body fat, blood oxygen, heart rate)
- Daily GPT health insight card (tappable for full analysis)
- Health alert banner with anomaly warnings (tappable for details)
- Manual input for symptoms, blood pressure/sugar, and checkup report photos
- Background export of Apple Health data to the agent for analysis

## Setup

### Prerequisites

- iPhone running iOS 17+
- A Mac running a Python agent using [MiraBridge](../MiraBridge)
- Both devices on the same Apple ID with iCloud Drive enabled

### Building

1. Clone this repo alongside MiraBridge:
   ```
   your-workspace/
   ├── MiraBridge/    <- clone this first
   └── MiraApp/       <- this repo
   ```

2. Open `Mira.xcodeproj` in Xcode
3. The MiraBridge Swift package is referenced as a local dependency at `../MiraBridge/swift`
4. Build and run on your device

### First Launch

1. The app asks you to select your Bridge folder on iCloud Drive
2. Choose the folder your agent writes to (the one with `heartbeat.json`)
3. Select your profile
4. You're connected -- the app starts polling for updates

## For Agent Developers

MiraApp works with any agent that follows the MiraBridge protocol. Tag your items to get appropriate styling:

| Tags | Color | Icon |
|------|-------|------|
| `explore`, `briefing` | Blue | Globe |
| `analysis`, `market` | Green | Chart |
| `health`, `alert` | Orange | Warning triangle |
| `health`, `insight` | Green | Brain |
| `health`, `symptom` | Amber | Stethoscope |
| `reflect`, `journal` | Gold | Brain |
| `writing`, `article` | Purple | Doc |

## Architecture

```
MiraApp (this repo)
   | imports
MiraBridge (Swift package -- models, sync, commands)
   | iCloud files
Your Agent (Python -- uses mira_bridge.Bridge)
```

Key resilience features:
- `MiraItem` and `ItemMessage` use fault-tolerant decoding (missing fields get defaults, legacy `role` key falls back to `sender`)
- Local cache for offline access
- Background refresh for health data export

## License

MIT
