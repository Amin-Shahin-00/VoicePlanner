//
//  VoicePlannerApp.swift
//  VoicePlanner
//
//  ════════════════════════════════════════════════════════════════════════════
//  PROJECT SETUP (Xcode 16+, iOS 17.0+, physical iPhone)
//  ════════════════════════════════════════════════════════════════════════════
//
//  Already configured in VoicePlanner.xcodeproj (Target ▸ Build Settings):
//   • Info.plist is generated (GENERATE_INFOPLIST_FILE) with the required privacy keys.
//     Without them, iOS kills the app when it asks for permission:
//       NSMicrophoneUsageDescription         → INFOPLIST_KEY_NSMicrophoneUsageDescription
//       NSSpeechRecognitionUsageDescription  → INFOPLIST_KEY_NSSpeechRecognitionUsageDescription
//     In Target ▸ Info they appear as "Privacy - Microphone Usage Description"
//     and "Privacy - Speech Recognition Usage Description".
//   • Development language = Arabic (CFBundleDevelopmentRegion = ar), so the UI is
//     right-to-left and the Siri phrases in AppShortcuts.xcstrings are Arabic source strings.
//   • Display name "مخطط" (CFBundleDisplayName). This is the name you say to Siri.
//   • Capabilities: none. No iCloud, no Siri entitlement, no background modes.
//     App Shortcuts and local notifications need none of them.
//
//  You still have to do this yourself:
//   • Target ▸ Signing & Capabilities: pick your Team and change the bundle ID
//     (com.example.voiceplanner) to something unique.
//
//  Device settings for fully offline Arabic dictation:
//     Settings ▸ General ▸ Keyboard: enable Dictation and add an Arabic keyboard,
//     so iOS downloads the on-device Arabic speech model. Set Siri's language to
//     Arabic to use the Siri phrases. The Simulator has no usable microphone
//     input, so test on a real iPhone.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct VoicePlannerApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = ForegroundNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // CFBundleDevelopmentRegion = ar already gives RTL. These lines make
                // the UI Arabic even on a device whose system language is English.
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
        // The same container that AddPlanIntent writes to, so plans saved through
        // Siri appear in the list right away.
        .modelContainer(PlanStore.shared)
    }
}
