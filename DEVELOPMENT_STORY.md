# ScenePartner — Development Story

*A narrative account of how this app was built, the decisions made, and the problems solved.*

---

## The Idea

ScenePartner started from a specific, concrete problem: actors preparing self-tapes need a scene partner to read the other character's lines. In professional settings, you hire a reader. At home at midnight before an audition deadline, you don't have that option.

The vision was an app that could stand in for a human scene partner — one that understands the script, respects the writer's words, delivers lines with emotional intelligence, and listens to you so the rhythm feels like real acting rather than karaoke.

The guiding principle from the start: **this has to feel like acting, not like using software.**

---

## Phase 0: Architecture First

Before writing a single view, we spent time on architecture. The prompt that started this project was unusually detailed — it specified a hybrid offline/online system, a protocol-based voice abstraction, a deterministic state machine, and a tone engine. This level of upfront design paid off throughout development.

The key architectural decision was the `VoiceEngineProtocol`:

```swift
protocol VoiceEngineProtocol: AnyObject {
    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void)
    func stop()
    func pause()
    func resume()
    var isSpeaking: Bool { get }
}
```

By making the rehearsal engine call only this protocol, we could swap `AVSpeechSynthesizer` for ElevenLabs later without touching any rehearsal logic. This turned out to be exactly the right call — we swapped voice engines three times during development without breaking anything else.

The second key decision was the state machine. Rather than using booleans scattered through the UI, everything flows through a single `RehearsalStatus` enum:

```
idle → playingPartner → waitingForUser → paused → finished
```

This made debugging trivial — at any point you could ask "what state are we in?" and get a single clear answer.

---

## Phase 1: Getting It to Build

The first challenge was Xcode itself. The project was created with Xcode 26 beta, which ships with Swift 6 strict concurrency enabled by default. This caused a cascade of build failures that took significant time to resolve:

**Problem 1: Duplicate files.** When the source files were added to Xcode, they ended up in two folders (`Claude Code/` and `ScenePartner/`). Since Xcode 16 uses `PBXFileSystemSynchronizedRootGroup` — automatically including all files in a folder — every type was defined twice. Fix: delete the duplicate folder via git.

**Problem 2: `some Scene` conformance.** The `App` protocol's `body` property returning `some Scene` simply didn't compile in Xcode 26 beta with Swift 6's actor isolation rules. We tried `@MainActor`, `nonisolated`, `@SceneBuilder`, module-level singletons, `@Observable` — nothing worked. The fix that finally succeeded: returning the **concrete type** `WindowGroup<AppRootView>` instead of the opaque `some Scene`. This is a known Xcode 26 beta issue.

**Problem 3: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** The project file had this build setting enabled, which made every type implicitly `@MainActor` and caused cascading actor isolation errors. Removed via `sed` on the `.pbxproj`.

**Problem 4: `SWIFT_APPROACHABLE_CONCURRENCY`.** Another beta setting that rewrote the concurrency rules mid-compile. Removed.

**Problem 5: `@MainActor` on `RehearsalEngine` init.** Because the class is `@MainActor`, its `init` couldn't be called from `RehearsalView`'s `init` (which runs in a non-isolated context). Fix: make the speak callback use `Task { @MainActor in }` for the completion handler.

Each fix revealed the next problem. By the end, we had a clean build with `SWIFT_STRICT_CONCURRENCY = minimal` and concrete return types where opaque types failed.

---

## Phase 2: Core Rehearsal

With the build stable, the rehearsal engine came together quickly because the state machine was already designed. The parser was the most interesting piece — detecting character names required distinguishing between:

- `ALEX` (character name — no punctuation, 1-5 words, all caps)
- `SCENE 1` (scene heading — starts with known prefix)
- `I CAN'T BELIEVE YOU` (dialogue in a shouting character — would wrongly match ALL-CAPS detection)

The solution was a combination of checks: all-caps, word count ≤ 5, no sentence-ending punctuation, and position in the file (immediately before dialogue rather than inline).

The teleprompter scroll was solved with `ScrollViewReader` and `onChange`:

```swift
.onChange(of: engine.state.currentLineIndex) { _, newIndex in
    withAnimation(.easeInOut(duration: 0.4)) {
        proxy.scrollTo(newIndex, anchor: .center)
    }
}
```

---

## Phase 3: The Voice System

The offline voice (AVSpeechSynthesizer) worked immediately. The interesting design work was in `ToneEngine` — mapping emotional labels to TTS parameters:

```swift
"angry": VoiceProfile(rate: 0.60, pitch: 1.15, volume: 1.0, pauseAfterMs: 80)
"intimate": VoiceProfile(rate: 0.42, pitch: 0.95, volume: 0.75, pauseAfterMs: 200)
```

These numbers came from experimentation — what rate feels angry vs. intimate? The insight was that intimacy is about *slowing down and getting quieter*, while urgency is about *speeding up and getting louder*. These map directly to the AVSpeech parameters.

The ElevenLabs integration added a new dimension: rather than adjusting speech mechanics, we could adjust the model's *expressiveness* through `stability` and `style` parameters. Lower stability means more variation between utterances — more human, more unpredictable. Higher style means more exaggeration of the voice's characteristics.

We mapped emotional tones to these parameters:
- **Expressive tones** (angry, desperate, urgent) → `stability: 0.28`, `style: 0.60`
- **Calm tones** (intimate, sad, vulnerable) → `stability: 0.55`, `style: 0.15`

The ElevenLabs audio crash took two attempts to fix. The first crash was `IsFormatSampleRateAndChannelCountValid` — we were using `outputFormat(forBus:)` on the input node, which returns an incompatible format. Switching to `inputFormat(forBus:)` fixed it.

---

## Phase 4: Listen Mode

Listen mode was the most technically complex feature. `SFSpeechRecognizer` requires:
1. Microphone permission
2. Speech recognition permission
3. A configured `AVAudioSession` in `.playAndRecord` mode
4. A correctly formatted audio tap on the input node

The audio session conflict was the main challenge: ElevenLabs uses `.playback` mode, but speech recognition needs `.playAndRecord`. Every time the user finished speaking and the partner started, the session had to be reconfigured. We fixed this by explicitly restoring the `.playback` session in `stopListening()`.

The silence detection approach evolved:
1. **v1:** Fixed 1.5s timer after any recognition result — too slow, felt robotic
2. **v2:** Reset timer on each new word, 0.6s threshold — better, but cut off mid-sentence
3. **v3:** 0.8s threshold with `hasHeardSpeech` flag — only starts counting silence after the first word is detected

The simulator problem: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` silently fails on the simulator (no real microphone). The log showed `Max silence reached — giving up` with empty transcription. Fix: detect simulator via `#if targetEnvironment(simulator)` and skip listen mode entirely, falling back to tap-to-advance.

---

## Phase 5: Character Direction

The character direction feature came from the actor's perspective. The problem with AI-generated voice isn't the technology — ElevenLabs sounds genuinely human. The problem is *context*. Without knowing that JAMIE is "desperate and trying to hide their guilt," the voice sounds technically correct but emotionally vacant.

The solution was a director's notes layer before rehearsal:
- **Emotional state** — how the character feels internally
- **Scene objective** — what the character wants in this scene
- **Tone chips** — 15 preset labels with emoji for quick selection
- **Director's notes** — free text for anything else

These feed into ElevenLabs parameters at call time. The design principle: the *actor* gives direction, the *AI* executes it. The app stays in service of the performance, not the other way around.

---

## Git Workflow

The project used a shared GitHub repository for collaboration. The environment couldn't use SSH directly, but HTTPS with a classic Personal Access Token worked. Key git operations during development:

- Aggressive use of `git checkout -- <file>` to discard local Xcode modifications (`.xcuserstate`, `.pbxproj`) that blocked pulls
- `sed` on the `.pbxproj` to modify build settings without opening Xcode
- Tags for milestone preservation: `git tag -a v0.1-milestone`

The most common failure pattern was: make a fix → push to remote → Xcode auto-modifies `.pbxproj` → next pull fails. Solution: always run `git checkout -- *.pbxproj` before pulling.

---

## What We Learned

**On Swift 6 / Xcode 26 beta:** The strict concurrency system is correct in principle but the beta compiler has rough edges — particularly around `App` protocol conformance and actor isolation in `@main` structs. Concrete return types over opaque types (`WindowGroup<T>` over `some Scene`) is a useful workaround.

**On audio sessions:** iOS has one audio session per app. Every feature that touches audio (TTS, speech recognition, ElevenLabs playback) must be designed with session ownership in mind. The pattern that works: whoever is about to use audio reconfigures the session, and whoever just finished restores it to a neutral state.

**On timing:** Human conversation rhythm is around 300-800ms between lines. The initial 1.5s silence threshold felt like the partner was thinking too hard. 0.8s feels like a human pause. The ElevenLabs `pauseAfterMs` default of 300ms was also cut to 150ms for the same reason.

**On protocols:** `VoiceEngineProtocol` saved us multiple times. When ElevenLabs was crashing, we could instantly fall back to `SpeechManager` with one line change. When we added the direction feature, only `ElevenLabsVoiceEngine` needed to change. Protocol-first design paid for itself.

---

## Milestone: v0.1

Tagged `v0.1-milestone` on February 28, 2026.

At this point the app can:
- Import and parse a script
- Let you pick your character
- Set emotional direction for the AI partner
- Run a full rehearsal with ElevenLabs neural voice
- Listen for your lines and auto-advance
- Fall back gracefully to device TTS when offline

What it cannot yet do:
- Record video
- Manage takes
- Export to Camera Roll
- Import PDFs or Word documents natively

These are the next phases.

---

## Next: Self-Tape Recording (v0.2)

The camera and recording system will be built on `AVCaptureSession` and `AVAssetWriter`. The key design challenge is mixing the ElevenLabs audio stream into the video recording — since ElevenLabs returns an MP3 file, we'll need to decode it and feed the PCM audio into the asset writer alongside the camera feed.

The take management system will store recordings in the app's Documents directory, indexed by script ID and take number. A thumbnail will be extracted at the first frame using `AVAssetImageGenerator`.

The goal remains the same as day one: **make it feel like acting.**
