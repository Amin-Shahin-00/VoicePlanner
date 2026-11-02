//
//  AddPlanIntent.swift
//  VoicePlanner
//
//  "يا Siri، أضف فكرة في مخطط" → Siri asks "ما هي فكرتك؟" → the answer is
//  saved to SwiftData in the background. The app is never opened.
//
//  ── How the Arabic phrases reach Siri ──────────────────────────────────────
//  App Shortcut phrases are localized strings. The project's development language
//  is Arabic, so the phrases below are the source strings in AppShortcuts.xcstrings
//  (Xcode keeps that file in sync on every build). If you add or change a phrase,
//  build once and it's picked up. Siri's language on the device must be Arabic.
//  Every phrase must contain \(.applicationName), which Siri hears as the display
//  name "مخطط". No Siri capability or NSSiriUsageDescription is needed. Those
//  only apply to legacy SiriKit.
//  Once installed, the shortcut also shows up in the Shortcuts app and in Spotlight.
//

import AppIntents
import SwiftData

struct AddPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "إضافة فكرة"
    static let description = IntentDescription("يحفظ فكرة أو خطة جديدة مباشرةً دون فتح التطبيق.")

    /// Run in the background and never bring the app to the foreground.
    static let openAppWhenRun: Bool = false

    /// A non-optional String parameter makes Siri ask for it by voice.
    /// Siri dictates the reply in the user's Siri language (Arabic).
    @Parameter(
        title: "الفكرة",
        requestValueDialog: IntentDialog("ما هي فكرتك؟")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("أضف \(\.$text)")
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $text.needsValueError(IntentDialog("ما هي فكرتك؟"))
        }

        let scheduledFor = ArabicDateParser.parse(trimmed)
        let context = PlanStore.shared.mainContext
        let plan = Plan(text: trimmed, scheduledFor: scheduledFor)
        context.insert(plan)
        try context.save()
        PlanReminders.sync(plan)

        if let scheduledFor {
            let when = scheduledFor.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened)
                    .locale(Locale(identifier: "ar"))
            )
            return .result(dialog: "تم حفظ فكرتك، وموعدها \(when).")
        }
        return .result(dialog: "تم حفظ فكرتك.")
    }
}

struct VoicePlannerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddPlanIntent(),
            phrases: [
                "أضف فكرة في \(.applicationName)",
                "سجل فكرة في \(.applicationName)",
                "فكرة جديدة في \(.applicationName)",
                "أضف خطة في \(.applicationName)",
                "\(.applicationName) فكرة جديدة",
            ],
            shortTitle: "فكرة جديدة",
            systemImageName: "mic.badge.plus"
        )
    }
}
