# Superwhisper Takeaways — what's worth stealing, what isn't

Source: `Superwhisper-Analysis/` (audit of the 7 public repos under
`github.com/superultrainc`, conducted 2026-05-05).

The Superwhisper macOS app itself is **closed source**. Their
public org is a thin client SDK by example — Raycast extension,
OpenCode plugin, Pi plugin, Claude Code wrapper, docs. The
*integration patterns* in those plugins ARE the spec, since
nothing else is documented.

This doc filters those patterns through our identity:
**privacy-first, local-first, open source, native macOS.** We
steal patterns; we reject anything that contradicts the promise.

---

## tl;dr — the priority list

| Priority | Idea | Source | Cost | Why |
|---|---|---|---|---|
| **P0 (v1)** | Modes system (per-mode prompts, language, model, AI processing) | Superwhisper's killer UX feature | ~1 week | Polish tab is too coarse; modes generalise it cleanly |
| **P0 (v1)** | URL scheme — `cyphrwhispr://record`, `mode?key=X`, `settings` | Three plugins reimplement same protocol | ~½ day | Trivial; unlocks Raycast / Alfred / Shortcuts integration overnight |
| **P1 (v1.5)** | Auto-activation rules (bind modes to apps / window titles) | Documented in their modes UI | 2-3 days | "Slack mode auto-activates in Slack" — power-user delight |
| **P1 (v1.5)** | Custom vocabulary editor (initial-prompt seeding) | Their docs reference it; not in our plan | 2-3 days | Fixes proper-noun / jargon accuracy without retraining |
| **P1 (v1.5)** | Raycast extension (URL-scheme client) | 159 LOC in their repo | ~½ day | Once URL scheme exists, this is a stub |
| **P2 (v2)** | Agent integration: JSON inbox + response file polling | OpenCode + Pi plugins use exact same protocol 3× | 1-2 weeks | Killer differentiator; lets Claude Code / Cursor etc. ASK voice questions and HEAR answers |
| **P3 (later)** | History retention UI (auto-delete after N days) | They make users set up cron jobs (!) | ~1 day | Trivial improvement on their UX |

What we **explicitly do NOT steal**:
- Cloud transcription proxy / "anonymising" relay — contradicts local-first.
- Closed `claude-hook` binary pattern — we'll ship hook logic openly.
- Their `~/Documents/superwhisper/recordings/` plain-text storage — ours is encrypted.

---

## P0 — Modes system

### What Superwhisper does

A "mode" bundles together: voice model, language, AI processing
prompt, audio settings (mute media, system audio capture, speaker
ID), and output behaviour. User picks per-session via dropdown
or auto-activation rules. Stored as plain JSON files at
`~/Documents/superwhisper/modes/*.json` — Raycast reads them
directly off disk.

```jsonc
// Inferred shape from the Raycast extension
{
  "key": "abc123",
  "name": "Email mode",
  "voiceModel": "...",
  "language": "en",
  "aiPrompt": "Format the dictation as a professional email...",
  "audioSettings": { "muteWhileRecording": true, ... },
  "autoActivate": { "apps": ["com.apple.Mail"], "websites": [...] }
}
```

### What we should do

Generalise our current `Settings → Polish` tab. Right now we have
a single global Polish prompt; modes turn that into N named
configurations. Each mode owns:

- **Name + key** (uuid; key used in URL scheme)
- **Active model ID** (override of the global default)
- **Polish enabled + prompt** (per-mode override of the global Polish toggle)
- **Language hint** (whisper `language` parameter)
- **Sanitiser overrides** (e.g. allow specific bracketed text)
- **Auto-activation rules** (P1, see below)

**Storage:** mirror Superwhisper's pattern with one improvement —
keep modes inside our app's sandboxed app-support dir (better
permissions story) AND export/import as JSON for sharing.

```
~/Library/Application Support/CyphrWhispr/modes/<uuid>.json
```

Bundled defaults shipped read-only:
- `Voice to Text` (no AI processing, raw transcript)
- `Email` (Polish on, professional tone)
- `Slack message` (Polish on, casual tone)
- `Code comment` (Polish on, technical, no formatting fluff)
- `Notes` (Polish on, light cleanup only)

User-created modes are read/write. UI: replace the Polish tab
with a `Modes` tab — list view + detail editor.

### Why this beats a single Polish prompt

A coder dictating a Slack message wants different cleanup from
the same coder dictating a code comment. Today they'd have to
manually toggle Polish + edit the prompt every time. With modes:
hotkey → pick mode → speak. Or with auto-activation: hotkey in
Slack → Slack mode auto-engages.

---

## P0 — URL scheme

### What Superwhisper does

```
superwhisper://record
superwhisper://mode?key=<MODE_KEY>
superwhisper://agent-wake
superwhisper-debug://<...>     (auto-detected when running from DerivedData)
```

Three plugins (Raycast, OpenCode, Pi) all hit these schemes via
`open superwhisper://...`. Bundle ID:
`com.superduper.superwhisper`.

### What we should do

Register a `cyphrwhispr://` URL scheme in Info.plist. Implement
these handlers:

| URL | Action |
|---|---|
| `cyphrwhispr://record` | Toggle dictation (push-to-talk start, or toggle-mode start/stop) |
| `cyphrwhispr://record?mode=<key>` | Switch to mode + start recording in one shot |
| `cyphrwhispr://mode?key=<KEY>` | Switch active mode without recording |
| `cyphrwhispr://settings` | Open Settings window |
| `cyphrwhispr://settings?tab=modes` | Deep-link into a specific tab |
| `cyphrwhispr-debug://<...>` | Same as above, only honoured when bundle path contains `/build/derived/` (our repo-local DerivedData) |

The debug scheme is genuinely clever — it means you can wire
Raycast / Shortcuts to BOTH the production app AND the dev build
without conflict. Steal this one verbatim.

### Cost

Maybe 50 LOC. Add `CFBundleURLTypes` to Info.plist, implement
`application(_:open:options:)` in `CyphrWhisprApp`, route to
existing AppCoordinator handlers.

---

## P1 — Auto-activation rules

### What Superwhisper does

Each mode can declare a list of bundle IDs and/or website URL
patterns. When the user fires the hotkey, the foreground app's
bundle ID is checked against every mode's auto-activation list;
the first match wins. (Their docs warn: once a mode auto-activates,
the system doesn't switch back — a sharp edge worth fixing.)

### What we should do

Same idea, with the sharp edge filed off:

- Mode auto-activation rules list bundle IDs and (optionally)
  window-title regex patterns.
- When the hotkey fires: NSWorkspace.frontmostApplication.bundleIdentifier
  → match against mode rules → use matched mode for this session
  only. After session ends, revert to the user's manually-selected
  default mode (don't sticky-auto-switch).
- "Default mode" is a separate concept the user picks in Settings;
  auto-activation is a per-session override.

### Risks

- Permission scope: reading window titles requires Accessibility,
  which we already need for paste injection. So no new permissions.
- Performance: NSWorkspace lookup is microseconds. Fine.

---

## P1 — Custom vocabulary

### What Superwhisper does

Their docs reference "vocabulary editor" but the public repos
don't show the implementation. Inferred: a list of words / phrases
fed into Whisper as the `initial_prompt` parameter, which biases
the decoder toward those tokens.

### What we should do

`Settings → Vocabulary` tab. Plain text editor (one phrase per
line). Stored at:

```
~/Library/Application Support/CyphrWhispr/vocabulary.txt
```

On WhisperKit init, concatenate the user's vocabulary with the
mode's optional vocabulary into the `initial_prompt` parameter
(WhisperKit supports this — confirm in their API).

UI affordances:
- "Common technical terms" template (kubectl, GraphQL, OAuth, etc.)
- Per-mode override (a mode can ADD vocabulary on top of global)
- Live test field: speak, see what Whisper does with vs without

**Why this matters:** the #1 accuracy complaint with Whisper is
proper nouns and domain jargon. This is a 100% local fix that
costs nothing per-inference.

---

## P1 — Raycast extension

### What Superwhisper does

159 LOC TypeScript across 4 files. `select-mode` reads JSON files
off disk; `toggle-record` opens the URL scheme; `open-settings`
opens the URL scheme. Bundle ID check ensures the app is installed
before firing.

### What we should do

Once we have the URL scheme + modes-as-JSON-files, this is a
copy-paste-and-rename job. Create a `cyphrwhispr-raycast`
sibling repo (or subdir), publish to the Raycast Store later.

Files needed:
- `package.json` (Raycast manifest)
- `src/toggle-record.ts` (~10 LOC)
- `src/select-mode.tsx` (~50 LOC, reads our app-support modes dir)
- `src/open-settings.ts` (~5 LOC)
- `src/utils.ts` (bundle ID detection)

Total: ~80 LOC TypeScript.

---

## P2 — Agent integration (the killer feature)

### What Superwhisper does

This is the single most original thing in their public code. The
OpenCode and Pi plugins wire a coding agent to a voice UI:

1. Agent emits an event (e.g. "asking permission to run command",
   "task done", "asking the user a question").
2. Plugin writes a `<key>-message.txt` with the agent's full
   message, and writes a JSON payload to
   `~/Library/Application Support/superwhisper/agent/inbox/<uuid>.json`.
3. Plugin atomically `tmp → rename`s the JSON file. Closed app
   watches the dir via FSEvents.
4. Plugin polls `<key>-response.txt` at 1 Hz with a 30-min timeout.
5. User sees notification, hits hotkey, speaks reply.
6. Closed app writes the transcribed reply to `<key>-response.txt`.
7. Plugin reads the reply, deletes the temp files, feeds the reply
   back into the agent as a new user message.

The protocol is plain text + JSON over filesystem. No SDK
required, survives agent CLI restarts, works across processes.

### What we should do

Build this open. We'd be the first OPEN-SOURCE local-first speech-
to-text app with this capability. Minimum viable agent integration:

1. CyphrWhispr exposes an `agent` mode where the pill renders a
   message excerpt + waveform instead of just live transcript.
2. CLI tool `cyphrwhispr-agent send --message-file ... --response-file ...`
   that writes to our inbox dir, fires `cyphrwhispr://agent-wake`,
   blocks until the response file is written, then prints it.
3. Hook scripts for Claude Code, OpenCode, Cursor (TUI mode) that
   wrap the CLI tool. These can live in a sibling repo.
4. "Mark as bypassed" mechanism so user can disable per-cwd
   without uninstalling the hook.

### Why v2

The core dictation app needs to be solid first. Agent integration
adds significant complexity (message UI, multi-turn state, hook
distribution story). Worth doing, but not until the v1 feature
set lands and we have happy daily-driver usage.

---

## P3 — History retention UI

### What Superwhisper does

Genuinely funny: their official answer to "how do I auto-delete
old recordings" is **"set up a cron job."** They include a
copy-paste cron line in their docs.

### What we should do

A `Retention` section in `Settings → History`:

- Radio: Keep forever / Auto-delete after [N days dropdown] / Keep last [N entries]
- "Delete all history now" with confirmation
- Show current storage used (sum of recording sizes if we keep audio,
  encrypted DB size always)

Trivial. Strictly better UX. One-line entry in our pitch:
"Privacy-first means giving you the controls — not telling you
to write cron jobs."

---

## What we explicitly DON'T steal

| Their thing | Why we don't |
|---|---|
| Cloud transcription proxy | Contradicts local-first promise. If users want OpenAI/ElevenLabs/Deepgram, they can use those products directly. |
| Plain `~/Documents/<recordings>` storage | Ours is encrypted by BIP-39-derived key. Plain storage defeats the privacy promise. |
| Closed `claude-hook` binary | Ours ships open. The whole repo is auditable. |
| Bundling whisper.cpp directly | We use WhisperKit (Swift-native, Core ML compiled). Their fork is 0 ahead / 830 behind upstream — clearly not the live source. |
| User-pays SaaS gates | We're open source. Pricing is a future "Pro features" question, not a v1 question. |

---

## How this slots into the existing plan

Original v1 plan (from `~/.claude/plans/let-s-first-create-a-cheeky-cook.md`):

```
Phase 1 — Skeleton, menu bar, hotkey, audio, pill        ✅ DONE
Phase 2 — Streaming transcription + paste                 ✅ DONE
Phase 3 — Hardware detect, model picker, downloader       🟡 PARTIAL
Phase 4 — Encrypted history + BIP-39 + onboarding         ⏳ PENDING
```

**Recommended amendment:**

```
Phase 3 (revised) — Modes + URL scheme + model picker + custom models
  ├─ Modes system (replaces Polish tab as the primary AI-config surface)
  ├─ URL scheme + Raycast extension
  ├─ Hardware detect + model picker + downloader (as originally planned)
  └─ Custom vocabulary editor

Phase 4 (unchanged) — Encrypted history + BIP-39 + onboarding polish

Phase 5 (NEW, post-v1) — Auto-activation rules + retention UI

Phase 6 (NEW, v2) — Agent integration (CLI tool + Claude Code hook)
```

This keeps the v1 ship date roughly the same — modes generalise
work we'd be doing anyway in the Polish tab, and URL scheme is
a half-day. The agent integration deliberately defers until v2
because it's a separate-product-sized feature.

---

## What I recommend doing next, concretely

Three options, ranked:

1. **Modes system** (P0, ~1 week). Highest leverage for v1 quality.
   Generalises Polish, ships better defaults, sets up auto-activation.
2. **URL scheme** (P0, ~½ day). Cheapest big win. Unblocks the
   Raycast extension and any future external integrations.
3. **Phase 4 (encrypted history)** as originally planned. Biggest
   remaining v1 feature; doesn't depend on any Superwhisper-derived
   ideas but ALSO doesn't conflict with them.

If the goal is "land v1 ASAP," do (3) and add modes/URL scheme as
v1.1. If the goal is "make v1 actually better than Superwhisper at
the things that matter," do (1) and (2) before shipping.

I'd do **(2) first** (cheap, unblocking) then **(1)** (the big
quality lever), then **(3)** (privacy promise). Six weeks total.
