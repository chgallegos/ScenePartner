# ScenePartner

An iPhone/iPad app for actors to rehearse scenes and record self-tapes with an AI scene partner.

---

## Current Version: v0.1-milestone

> To restore this state at any time: `git checkout v0.1-milestone`

---

## What It Does (v0.1)

ScenePartner lets you import a script, select your character, and rehearse with an AI partner that speaks the other characters' lines. The app works fully offline using on-device TTS, with optional neural voice via ElevenLabs when online.

---

## Feature Status

### ✅ Implemented (v0.1)

**Script Management**
- Paste script as plain text
- Import `.txt` files
- Import `.docx` Word documents (via file picker)
- Local JSON persistence — one file per script in Documents directory
- Scripts sorted by last updated

**Script Parsing**
- Scene headings (`SCENE 1`, `INT.`, `EXT.`)
- Character names (ALL-CAPS detection)
- Dialogue lines
- Stage directions `(in parentheses)` or `[brackets]`
- Resilient to inconsistent formatting

**Role Selection**
- Pick which character(s) you play
- AI automatically plays all others
- Improv mode toggle (partner may paraphrase)

**Character Direction**
- Set emotional state per AI character ("desperate, hiding guilt")
- Set scene objective ("convince Alex to stay")
- Tone chips with emoji — 15 presets (tense, playful, intimate, angry, etc.)
- Director's free-form notes
- Direction feeds directly into ElevenLabs voice parameters

**Teleprompter**
- Full script display with current line highlighted
- Auto-scroll to current line
- Adjustable font size (14–72pt)
- Mirror mode (for teleprompter glass setups)
- User-lines-only toggle

**Rehearsal Engine**
- State machine: `idle → playingPartner → waitingForUser → paused → finished`
- Deterministic `currentLineIndex` — never jumps randomly
- Play / Pause / Resume
- Back (previous dialogue line)
- Jump to scene
- Tap-to-advance (manual fallback)

**Voice System**
- `VoiceEngineProtocol` — swap implementations without touching engine
- `SpeechManager` — AVSpeechSynthesizer (offline, always works)
- `ElevenLabsVoiceEngine` — neural TTS with emotional direction
  - `eleven_turbo_v2_5` model (low latency)
  - Stability mapped from tone (expressive tones → lower stability)
  - Style mapped from emotional intensity
  - Falls back to AVSpeech on network error

**Listen Mode**
- `SFSpeechRecognizer` — on-device + server recognition
- 0.8s silence detection after last word
- Live audio level meter in UI
- Auto-disabled on simulator (no real mic)
- Graceful fallback to tap-to-advance if recognition fails

**Connectivity**
- `NWPathMonitor` — real-time network state
- Offline banner on home screen
- All online features silently skip when offline

**Settings**
- Local Only Mode (disables all network calls)
- ElevenLabs API key (stored in UserDefaults, never in code)
- Voice selection (Daniel / Bella)
- Use AI Voice toggle
- Font size default
- Speech rate / pitch for fallback TTS
- Mirror mode default

---

### 🔲 Planned (v0.2 — Self-Tape Recording)

**Phase 1: Camera + Recording**
- [ ] `AVCaptureSession` — live camera preview
- [ ] Front/back camera toggle
- [ ] `AVAssetWriter` — record video + audio
- [ ] Mix ElevenLabs audio into recording
- [ ] Save to Camera Roll
- [ ] 3-2-1 countdown before recording
- [ ] Slate card (name, scene, take number)

**Phase 2: Take Management**
- [ ] Multiple takes per scene
- [ ] Take browser with thumbnails
- [ ] Mark hero take
- [ ] Delete unwanted takes
- [ ] Trim start/end

**Phase 3: Export & Share**
- [ ] Export to Camera Roll
- [ ] AirDrop share sheet
- [ ] Audio-only export option
- [ ] Casting platform deep links

**Phase 4: Professional Polish**
- [ ] PDF sides import (parse character names)
- [ ] `.docx` sides import (already partially supported)
- [ ] Framing grid overlay
- [ ] Casting session mode (group scenes)
- [ ] Post-run coaching feedback (via AI)
- [ ] Find My Place (AI line recovery)

---

## Architecture

```
Views (SwiftUI)
  ScriptListView → RoleSelectionView → DirectionView → RehearsalView
                                                      → TeleprompterView

Engines / ViewModels
  RehearsalEngine    — state machine, drives playback
  TeleprompterEngine — scroll, font, mirror
  SpeechRecognizer   — listen mode (SFSpeechRecognizer)
  AppSettings        — @AppStorage user prefs

Service Layer
  ScriptStore        — CRUD + JSON persistence
  ScriptParser       — raw text → Script model
  VoiceEngineProtocol ← SpeechManager (AVSpeech, offline)
                      ← ElevenLabsVoiceEngine (neural, online)
  ToneEngine         — tone tags → TTS parameters
  ConnectivityMonitor — NWPathMonitor

Data Models
  Script, Scene, Line, Character
  RehearsalState, VoiceProfile
  SceneDirection, CharacterDirection
  ToneAnalysis (online AI, future)
```

---

## Setup

### Requirements
- Xcode 16+ (built with Xcode 26 beta)
- iOS 17+ deployment target
- Physical device for listen mode (simulator mic unreliable)

### Run
1. Clone: `git clone https://github.com/chgallegos/ScenePartner.git`
2. Open `ScenePartner/ScenePartner/ScenePartner.xcodeproj`
3. Select your device or simulator
4. **⌘R** to build and run

### ElevenLabs Voice (optional)
1. Sign up at [elevenlabs.io](https://elevenlabs.io)
2. Create an API key with **Text to Speech** access
3. In the app: Settings → Use AI Voice → paste key

---

## Script Format

```
SCENE 1

ALEX
I can't believe you did that.
(beat)

JAMIE
I had to. There was no other way.
```

- ALL-CAPS name alone on a line = character speaker
- `(parenthetical)` or `[bracket]` = stage direction
- `SCENE N`, `INT.`, `EXT.` = scene heading
- Blank lines reset the current speaker

---

## Restoring the Milestone

```bash
git checkout v0.1-milestone
```

To return to latest:
```bash
git checkout main
```

---

## Tech Stack
- Swift 5 / SwiftUI
- AVFoundation (TTS, audio session, future: recording)
- Speech framework (SFSpeechRecognizer)
- Network framework (NWPathMonitor)
- ElevenLabs REST API (optional)
- No third-party dependencies
