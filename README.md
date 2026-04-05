# MiraApp

A SwiftUI iPhone app for controlling any AI agent that uses the [MiraBridge](../MiraBridge) protocol. It works in pure iCloud mode, and can optionally take faster local reads from a trusted LAN mirror when one is available.

## Tabs

- **Home** -- chat interface for requests and discussions, agent status, daily feeds (briefings, sparks, analysis)
- **Todo** -- shared todo list between you and the agent, with priority and follow-ups
- **Health** -- dashboard with Apple Health + Oura Ring data, daily GPT health insights, anomaly alerts, trend charts, symptom/checkup input
- **Artifacts** -- browse files the agent produces (writings, reports, research, audio)
- **Settings** -- profile selection, bridge workspace, agent heartbeat/debug info

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

## Notifications

The app sends local notifications for:

- `needs-input` items
- content review / approval requests with Approve and Reject actions
- completed user requests
- new feed items such as briefings, sparks, and health alerts

Review and health/trading alerts can be raised as time-sensitive notifications.

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

1. The app asks you to select your workspace on iCloud Drive
2. Choose either the `MtJoy` root or the `Mira-Bridge` folder your agent writes to
3. Select your profile from `profiles.json` or the built-in defaults
4. The app starts polling for updates and caching items locally for offline use

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
- iCloud-first sync with optional LAN heartbeat / manifest / item reads when a local mirror is reachable

## License

MIT
