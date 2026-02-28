# ScenePartner — Complete Build Plan & Architecture

---

## 1. Feature Checklist

### MVP (Implemented in this starter)
- [x] Paste script or import .txt file
- [x] Script parsing: dialogue, stage directions, scene headings
- [x] Local JSON persistence per script
- [x] Character roster extraction
- [x] Role selection (user picks their character(s))
- [x] State machine: idle → playingPartner → waitingForUser → paused → finished
- [x] Partner lines spoken via AVSpeechSynthesizer (offline, 100%)
- [x] Tap-to-advance for user lines
- [x] Teleprompter: scrollable, highlighted current line
- [x] Teleprompter: adjustable font size, mirror mode, user-lines-only toggle
- [x] Jump to scene
- [x] Back / Next controls
- [x] Pause / Resume
- [x] Connectivity monitor (banner when offline)
- [x] Settings: Local Only Mode, font defaults, speech rate/pitch
- [x] VoiceEngine protocol (swap implementations without touching RehearsalEngine)
- [x] ToneEngine: tone-tag → TTS parameter mapping (offline presets)
- [x] NetworkAIService: full stub with pseudocode for all 4 online features
- [x] Improv Mode toggle (UI only in MVP; AI call in NetworkAIService stub)

### Next Iteration
- [ ] Apple Speech recognition → auto-advance on user speech (offline Listen Mode)
- [ ] Find My Place: live LLM line recovery
- [ ] Tone Analysis: online AI → ToneAnalysis JSON → ToneEngine
- [ ] Coaching Feedback screen (post-run)
- [ ] Improv Mode: live AI line generation
- [ ] Per-character voice assignment in Settings
- [ ] iCloud sync (opt-in)
- [ ] Rich text import (.fountain, .fdx)

---

## 2. Architecture Overview (MVVM)

```
┌──────────────────────────────────────────────────────────┐
│                        VIEWS (SwiftUI)                    │
│  ScriptListView  RoleSelectionView  RehearsalView         │
│  TeleprompterView  SettingsView  ScenePickerView          │
└───────────┬──────────────────────────────────────────────┘
            │ @StateObject / @EnvironmentObject
┌───────────▼──────────────────────────────────────────────┐
│                    VIEW MODELS / ENGINES                   │
│  RehearsalEngine (state machine, @MainActor ObservableObj)│
│  TeleprompterEngine (scroll, font, mirror)                │
│  AppSettings (@AppStorage)                                │
└───────────┬──────────────────────────────────────────────┘
            │ protocol calls / async
┌───────────▼──────────────────────────────────────────────┐
│                      SERVICE LAYER                         │
│  ScriptStore      ─── ScriptParser                        │
│  VoiceEngineProtocol ◄── SpeechManager (AVSpeech)         │
│                       ◄── NeuralVoiceEngine (future)      │
│  ToneEngine (offline preset merge)                        │
│  ConnectivityMonitor (NWPathMonitor)                      │
│  NetworkAIService (stub → real API calls)                 │
└───────────┬──────────────────────────────────────────────┘
            │
┌───────────▼──────────────────────────────────────────────┐
│                    DATA LAYER                              │
│  Script  Scene  Line  Character  RehearsalState           │
│  VoiceProfile  ToneAnalysis                               │
│  Persistence: Documents/<uuid>.json                       │
└──────────────────────────────────────────────────────────┘
```

---

## 3. File Structure

```
ScenePartner/
└── ScenePartner/
    ├── App.swift                  Entry point, environment injection
    ├── AppSettings.swift          @AppStorage user prefs
    ├── ScriptModels.swift         Data models: Script, Scene, Line, etc.
    ├── ScriptParser.swift         Raw text → Script
    ├── ScriptStore.swift          CRUD + local JSON persistence
    ├── RehearsalEngine.swift      Core state machine
    ├── TeleprompterEngine.swift   Display state (scroll, font, mirror)
    ├── VoiceEngine.swift          Protocol + SpeechManager (AVSpeech)
    ├── ToneEngine.swift           Tone → TTS parameter mapping
    ├── ConnectivityMonitor.swift  NWPathMonitor wrapper
    ├── NetworkAIService.swift     Async AI stubs + pseudocode
    ├── ScriptListView.swift       Home screen
    ├── RoleSelectionView.swift    Character picker
    ├── RehearsalView.swift        Main rehearsal screen
    ├── TeleprompterView.swift     Scrolling script display
    └── SettingsView.swift         User preferences
```

---

## 4. State Machine

```
                    start()
     ┌─────────────────────────────────────┐
     │                                     ▼
  [idle] ──────────────────────► [playingPartner]
     ▲                                     │
     │                           utterance complete
     │                                     │
     │                                     ▼
     │                           [waitingForUser]
     │                                     │
     │    advance()                        │ advance()
     │    (next partner) ◄─────────────────┘
     │
     │    pause() from either active state:
     │    ─────────────────────────► [paused]
     │                                     │ resume()
     │    ◄────────────────────────────────┘
     │
     │    (end of script)
     └──────────────────────── [finished]
                                     │ start(from:0)
                                     └─────────────► (restart)
```

---

## 5. Script Format Reference

```
SCENE 1

ALEX
I can't believe you did that.
(beat)

JAMIE
I had to.
(quietly)
There was no other way.

ALEX
Then we're done here.
```

### Parser Rules
- `SCENE N`, `INT.`, `EXT.` → sceneHeading
- ALL-CAPS word(s) alone on a line (≤5 words) → character name (speaker for next lines)
- Lines starting with `(` or `[` → stageDirection
- Anything following a known speaker → dialogue

---

## 6. VoiceEngine — Extension Guide

### Add a Neural Voice Provider

```swift
final class ElevenLabsVoiceEngine: VoiceEngineProtocol {

    var isSpeaking: Bool { /* track state */ false }

    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        // 1. Map VoiceProfile → ElevenLabs voice_id + stability/similarity settings
        // 2. POST to https://api.elevenlabs.io/v1/text-to-speech/{voice_id}
        // 3. Stream/play audio via AVPlayer
        // 4. Call completion() when playback ends
    }

    func stop()   { /* cancel request + stop AVPlayer */ }
    func pause()  { /* pause AVPlayer */ }
    func resume() { /* resume AVPlayer */ }
}

// Inject in RehearsalView init:
let voiceEngine: VoiceEngineProtocol = isOnline ? ElevenLabsVoiceEngine() : SpeechManager()
```

### Add User-Recorded Voices

```swift
final class RecordedVoiceEngine: VoiceEngineProtocol {
    private let fallback = SpeechManager()
    // recordings keyed by "SPEAKER:lineIndex"
    private var recordings: [String: URL] = [:]

    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        let key = "\(profile.voiceIdentifier ?? ""):..."
        if let url = recordings[key] {
            // play via AVAudioPlayer, call completion on finish
        } else {
            fallback.speak(text: text, profile: profile, completion: completion)
        }
    }
    // ...
}
```

---

## 7. Online AI Integration Steps

1. Get an OpenAI (or compatible) API key.
2. In `NetworkAIService.swift`, implement the `callLLM` method using the pseudocode.
3. Store your API key in Keychain (never hardcode).
4. In `RehearsalView`, after scene load: `if connectivity.isConnected && !settings.localOnlyMode { engine.injectToneAnalysis(try await aiService.analyzeTone(...)) }`
5. Coaching screen: show result of `aiService.getCoachingFeedback(...)` in a sheet after `state.status == .finished`.

---

## 8. Run Instructions

### Xcode Setup

1. Create a new Xcode project: **File → New → Project → App**
   - Product Name: `ScenePartner`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum Deployment: iOS 16

2. Delete the default `ContentView.swift` generated by Xcode.

3. Add all `.swift` files from this archive to the project target.

4. In `Info.plist`, add:
   - `NSSpeechRecognitionUsageDescription` (for future Listen Mode)
   - `NSMicrophoneUsageDescription` (for future Listen Mode)

5. Build & run on simulator or device (no API keys needed for MVP).

### Testing With Sample Script

Paste this into "Add Script":

```
SCENE 1

ALEX
I can't believe you did that.
(beat)

JAMIE
I had to. There was no other way.

ALEX
Then explain it to me.

JAMIE
Not here. Not now.
(moves toward door)

ALEX
Don't you walk away from me.
```

Set yourself as ALEX. The partner will speak JAMIE's lines automatically.
