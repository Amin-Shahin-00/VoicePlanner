# مخطط (VoicePlanner)

An Arabic, voice-first planner for iOS 17+. It works 100% offline and uses only Apple frameworks:
SwiftUI, SwiftData, Speech, App Intents, NaturalLanguage and UserNotifications.

## Run it on your iPhone (needs a Mac with Xcode 16 or later)

1. Copy this whole `VoicePlanner` folder to the Mac and open `VoicePlanner.xcodeproj`.
2. Select the **VoicePlanner** target, then open **Signing & Capabilities**:
   - Pick your **Team**. A free Apple ID works.
   - Change the **Bundle Identifier** to something unique, e.g. `com.yourname.voiceplanner`.
3. Connect the iPhone and pick it as the run destination, then press **Run** (⌘R).
   - On a first install you may have to turn on **Developer Mode** (Settings ▸ Privacy & Security).
   - With a free Apple ID you also have to trust the developer (Settings ▸ General ▸ VPN & Device Management).

## Set up the iPhone

- **Offline Arabic dictation:** go to Settings ▸ General ▸ Keyboard, turn on Dictation and add an Arabic keyboard.
  iOS then downloads the on-device Arabic speech model.
- **Siri:** set Siri's language to Arabic, then say «يا Siri، أضف فكرة في مخطط».

## Already configured in the project

- Microphone and speech-recognition privacy strings, in the generated Info.plist.
- Arabic as the development language, which gives right-to-left layout and Arabic Siri phrases (`AppShortcuts.xcstrings`).
- Local-only SwiftData storage (`cloudKitDatabase: .none`).
- Local reminder notifications at each plan's scheduled time.
- App icon and accent color.
