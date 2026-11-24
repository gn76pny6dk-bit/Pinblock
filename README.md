# Pinblock

Pinblock is a native iOS and iPadOS piano tuning aid for Jordan. It listens through the microphone, shows a strobe and a cents readout, and builds a stretch curve from the piano’s own inharmonicity. It is meant to sit next to the usual aural work: mute to one string, tune that string to the strobe, then tune the unisons by ear.

It is not CyberTuner, and it does not use that app’s name, assets, or code. The ideas it shares with professional tuners are the public ones: partial selection, a strobe, inharmonicity, and a calculated stretch.

Requires iOS 17 or later. An iPhone 15 is a fine target.

## Features

- Live pitch from the microphone, aimed at about 0.1 cent on a steady tone. The fine reading is a quadrature demodulator (heterodyne) centered on an FFT peak, which is the right tool for a stiff, inharmonic piano tone.
- Listen on partial 1, 2, 3, 4, 5, 6, or 8. The app suggests 6 in the deep bass, 4 in the low tenor, 2 through the middle, and 1 in the high treble. You can override it per note.
- A three-row strobe. Flat scrolls one way, sharp the other, and the fine row moves 25 times faster so a tenth of a cent is visible. The numeric readout is in tenths of a cent, with the beat rate against the target.
- All 88 notes, A0 through C8, plus optional auto-note and auto-advance.
- A measure step. Hold a note, the app fits partial frequencies to the stiff-string model, and stores the inharmonicity coefficient B. A few notes across the compass replace the generic curve. Tunings are saved per piano as JSON on the device, and you can share or import the file.
- Reference pitch (A4, default 440 Hz), equal temperament, and Vallotti, Werckmeister III, Kirnberger III, Young 1799, and quarter-comma meantone. Every temperament is shifted so A stays on the reference pitch.
- Octave types 2:1, 4:2, 6:3, a fixed blend, a register-weighted blend (the default), or custom weights.
- Pitch-raise mode. You record how flat the piano is; the strobe then zeros sharp of the final curve by a capped overpull, and that target does not chase you as the note comes up.
- A curve view of cents from equal temperament across the keyboard.

## Get the app onto an iPhone from Windows

There is no Mac in this setup, and this project’s git host (Cursor Origin) does not run macOS builds. The iPhone also will not install an IPA that nobody has signed. The practical route is a free Mac runner in the cloud, then [Sideloadly](https://sideloadly.io) on Windows, which re-signs the IPA with a free Apple ID.

Two runners are wired up. They run the same script, `scripts/build-unsigned-ipa.sh`: unit tests, then an unsigned/ad-hoc Release archive, then a `.ipa`.

| Route | When to use it |
| --- | --- |
| **GitHub Actions** (recommended) | You can push this project to GitHub. A public repo gets free macOS minutes. Download the IPA from the Actions page in a browser. |
| **Codemagic** | You would rather not use GitHub, or you want a service aimed at iOS artifacts. Codemagic can clone a git URL that is not GitHub, including Origin, if you can give it a username and a read token. If Origin will not issue a token a third party can use, point Codemagic at the GitHub mirror instead. Codemagic’s free personal plan includes a monthly pool of Mac minutes; check their current pricing before you rely on it. |

This environment could not start either build: there is no GitHub or Codemagic credential here, and Origin has no macOS fleet. The first green log has to be yours. If that log fails, the error is an Xcode diagnostic the Linux tests could not see. Fix it in the file the log names and push again.

### A. GitHub Actions

1. Create a GitHub account and a new repository. Public is the one that does not spend Actions minutes on a Mac. Private works too, but GitHub bills Mac minutes at 10×, so the free quota does not last long.
2. On Windows, install [Git](https://git-scm.com/download/win).
3. Get a copy of this project onto the PC (clone it from Cursor Origin, or download the archive from the Cursor project) and push it to GitHub:

   ```bat
   git remote add github https://github.com/YOUR_USER/pinblock.git
   git push -u github main
   ```

4. Open the repository on GitHub, then **Actions**. The workflow **iOS unsigned IPA** starts on the push to `main`. You can also run it by hand with **Run workflow**.
5. When the job is green, open it and download the artifact **Pinblock-unsigned-ipa**. Unzip it. Inside is `Pinblock-unsigned.ipa`.
6. If the job is red, open the log. The unit-test section and the `xcodebuild` section name the file and the line. The runner label is `macos-latest` in `.github/workflows/ios.yml`. Change that label only if GitHub has retired it.

### B. Codemagic, if you are not using GitHub

1. Create a [Codemagic](https://codemagic.io) account. The personal plan is enough to try a build.
2. **Add application → HTTPS/SSH** (this is the path for a git host that is not GitHub, GitLab, or Bitbucket).
3. Paste the clone URL of this project. For a private repo, supply a username and a personal access token or an SSH key that can read it. If you cannot create that credential on Origin, push to GitHub first and add the GitHub repo with Codemagic’s GitHub integration instead. `codemagic.yaml` is already in the repository root.
4. Start the **Pinblock unsigned IPA** workflow. The Mac is `mac_mini_m2` with the latest Xcode image. If Codemagic rejects the machine type, pick any current Mac M-series instance in the workflow settings; the script does not care which Mac it is.
5. Download `Pinblock-unsigned.ipa` from the build’s artifacts.

### Install with Sideloadly

Do this once, then again every 7 days for as long as you use a free Apple ID. A paid Apple Developer account ($99/year) is the thing that makes the signature last a year. It is optional.

1. On the PC, install [Sideloadly](https://sideloadly.io).
2. Install the Apple USB driver Sideloadly asks for. On Windows 10/11 the usual working set is the **Apple Devices** app from the Microsoft Store. If Sideloadly still cannot see the phone, also install the classic iTunes from [apple.com/itunes](https://www.apple.com/itunes/download/win64) (the Apple web installer, not the Microsoft Store version of iTunes).
3. Plug the iPhone 15 into the PC with a data-capable USB-C cable. Unlock the phone and tap **Trust**.
4. Open Sideloadly. Sign in with your Apple ID when it asks. A normal free Apple ID is enough. Approve the two-factor prompt if Apple sends one.
5. Drag `Pinblock-unsigned.ipa` into Sideloadly. Leave the defaults and click **Start**. Sideloadly re-signs the app and installs it.
6. On the iPhone, if iOS says developer mode is required: **Settings → Privacy & Security → Developer Mode**. Turn it on, restart, and confirm the prompt. The switch sometimes appears only after this first install attempt. Then run Sideloadly once more.
7. **Settings → General → VPN & Device Management**. Under Developer App, trust your Apple ID.
8. Open Pinblock and allow the microphone. Audio is analyzed on the phone and is not stored as a recording.

The bundle id baked into the build is `com.jordan.pinblock`. Change it in one place, `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, and let CI build again. Sideloadly can also override the id on the way in (the bundle-id field next to the Apple ID) if Apple says that id is already in use. Something like `com.jordan.pinblock.phone` is fine.

A free signature dies after **7 days**. The app icon stays, but iOS refuses to open it. Plug the phone back in, open Sideloadly, and click **Start** on the same IPA. You do not need a new CI build unless the code changed. Free Apple IDs can only hold a few sideloaded apps at a time; delete an old one if Apple complains.

If install fails and the log mentions a capability or a background mode, the only extra plist entry is audio background mode (so the screen can lock during a long measurement). Removing the `UIBackgroundModes` array from `Pinblock/Info.plist` and rebuilding is the fallback.

## Using it

Mute the choir to one string. Pick the note on the strip. Leave the suggested partial unless the tone is cleaner on another one. Tune until the strobe stops and the readout sits inside ±0.5¢. Then bring the other strings to that one by ear. The beat number is the difference between the string and the target, not a two-string unison beat.

**Measure** asks for A0, A1, A2, A3, A4, A5, A6, and A7. Hold the note until the card says Stable, then Keep. The curve updates immediately. One measurement scales the generic curve; two or more interpolate in log B and hold the end value outside the measured span, so a wild extrapolation cannot run off.

**Pitch raise** is on the settings tab. Set how flat the piano is, or play a note and use “Use the note I’m hearing.” The banner on the tuner tells you how sharp of the final curve to tune. When the piano is up, turn pitch raise off and do a normal pass. The overpull is a technician’s rule of thumb, not a measured model of that soundboard:

```
extra      = min(12, flatnessCents × 0.12)
effective  = min(45, overpullPercent + extra)
overshoot  = flatnessCents × effective / 100
```

With the default 25% and a piano 40¢ flat, that is 14.8¢ of overshoot. Notes that are already at pitch, or sharp, get no overpull.

## Tuning math

Equal temperament, A4 = R:

```
f(m) = R · 2^((m − 69) / 12)
cents(a → b) = 1200 · log2(b / a)
```

A0 is 27.5 Hz at R = 440. C8 is 4186.009 Hz. Middle C is 261.626 Hz.

Partials of a stiff string, with f1 the sounding fundamental (so partial 1 is exactly f1):

```
f_n = n · f1 · sqrt( (1 + B n²) / (1 + B) )
```

B and f1 come from least squares. Let y = (f_n / n)² and x = n². Then y = a + c x, with a = f0², c = f0² B, B = c / a, and f1 = sqrt(a + c). Buried partials and any partial more than about 0.35¢ off the series are dropped, because a high partial has a lot of leverage on B.

The stretch curve locks A4 at the reference pitch. Every other note is tempered equal temperament plus a cents offset s. For each octave, s(upper) − s(lower) is asked to equal the extra cents that make the chosen partials coincide (2 with 1, 4 with 2, 6 with 3, or a weighted average of those cents). A small second-difference term keeps neighboring semitones smooth, which is what ties the twelve pitch-class chains together. Octave equations are weighted about 70× harder than the smoothness terms, and on the generic curve the residual octave error stays under a few hundredths of a cent.

Temperaments are built from the circle of fifths and then shifted so pitch-class A is 0:

- **Vallotti** — F–C–G–D–A–E–B each narrowed by 1/6 of a Pythagorean comma; the rest pure.
- **Young 1799** — C–G–D–A–E–B–F♯ each narrowed by 1/6 of a Pythagorean comma.
- **Werckmeister III** — C–G, G–D, D–A, and B–F♯ each narrowed by 1/4 of a Pythagorean comma.
- **Kirnberger III** — C–G–D–A–E each narrowed by 1/4 of a syntonic comma, so C–E is a pure 5:4. The leftover schisma sits on F♯–C♯.
- **Quarter-comma meantone** — eleven fifths narrowed by 1/4 of a syntonic comma. The wolf is G♯–E♭. Major thirds are pure.

The default inharmonicity (until you measure) is a smooth guess for a medium grand: about 0.00035 at A0, 0.00070 at A4, 0.011 at C8. With the register-weighted octaves that produces a Railsback-shaped curve, on the order of −17¢ at A0 and +31¢ at C8, with A4 at 0. A real piano will not match those numbers. That is what Measure is for.

Pitch is tracked like this. A 16384-point Hann FFT finds the peak near the partial you asked for, and the search window is kept inside 40% of the gap to the next partial so a neighbor cannot steal the lock. A one-pole heterodyne at that coarse frequency rejects everything more than a few hertz away. After a 0.35 s settle, a straight-line fit to the unwrapped baseband phase is the frequency. On a clean synthetic tone that residual is well inside 0.1¢ from 55 Hz through C8.

## Project layout

```
PinblockCore/          Swift package: tuning math, FFT, heterodyne, tests
Pinblock/              SwiftUI app, microphone, saved pianos
project.yml            XcodeGen project. Bundle id lives here.
scripts/build-unsigned-ipa.sh
.github/workflows/ios.yml
codemagic.yaml
```

`PinblockCore` has no SwiftUI and no microphone code, so `swift test` runs on a Mac (and, for the math and the portable FFT, on Linux). On a Mac the same tests also exercise the Accelerate FFT and check that its peak bin matches the reference transform.

Saved pianos are JSON files in the app’s Documents directory, one file per piano.

## Build on a Mac

You do not need this for the Windows path above.

1. Install Xcode 16 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. `xcodegen generate`, then open `Pinblock.xcodeproj`.
3. Set your team if you want a normal developer signature. The checked-in settings leave signing manual and empty so CI can archive without an Apple team.
4. Run the **Pinblock** scheme on your iPhone. The simulator has no useful microphone.
5. Tests: `swift test --package-path PinblockCore`.

The microphone purpose string is `NSMicrophoneUsageDescription` in `Pinblock/Info.plist`.

## Tests

`PinblockCore/Tests` covers note frequencies, cents round-trips, every temperament’s defining fifths (and the pure thirds in Kirnberger III and meantone), inharmonicity recovery from exact partials, B interpolation, the stretch solver (a zero-B piano is pure temperament, and 4:2 / 2:1 / 6:3 partials line up), pitch-raise overshoot, auto-advance timing, JSON round-trip, the FFT against a direct DFT, heterodyne accuracy to 0.1¢ on sines and on an inharmonic partial, chunked streaming, silence, partial-series fitting when the note is 8¢ off, and auto-note on a full A4 and on an A1 with no fundamental.

## Limits

- The SwiftUI app and the Accelerate FFT were not compiled in the environment that wrote this code. There was no Mac. The core tests were run on Swift 6.0.3 for Linux and passed, including the 0.1¢ pitch checks. The first Mac CI log is the first real compile of the app and of the vDSP path.
- The generic B curve is a starting picture, not your piano.
- Pitch-raise overpull is an empirical suggestion.
- Auto-note can still jump octaves on a noisy or mixed tone. It is happiest within a few tens of cents of the curve.
- Very flat high partials can fall outside the search window. Use a lower partial, or get the note closer, then measure.
- One microphone, one string at a time. No reference-tone playback (that would feed back into the mic).
- The screen can lock without stopping the microphone because of the audio background mode. The app does not record.
- A free Apple ID signature lasts 7 days.

## What to do next

- Run the CI build once and keep the log if Xcode complains. That is the missing compile.
- Measure one real piano and see where the generic anchors should move.
- A headphone reference tone, and a page for editing the curve by hand, are the natural follow-ons.
- A paid developer account, or TestFlight, if re-signing every week gets old.
