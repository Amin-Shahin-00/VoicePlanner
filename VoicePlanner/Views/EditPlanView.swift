//
//  EditPlanView.swift
//  VoicePlanner
//
//  Fix a mis-transcribed word or adjust the detected date.
//

import SwiftUI
import SwiftData

struct EditPlanView: View {
    @Bindable var plan: Plan
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section("الفكرة") {
                    TextField("اكتب فكرتك", text: $plan.text, axis: .vertical)
                        .lineLimit(2...8)
                }

                Section("الموعد") {
                    Toggle("تحديد موعد", isOn: hasDate)

                    if let date = plan.scheduledFor {
                        DatePicker(
                            "الوقت",
                            selection: Binding(get: { date }, set: { plan.scheduledFor = $0 })
                        )
                    }

                    Button("استخراج الموعد من النص", systemImage: "wand.and.stars") {
                        withAnimation { plan.scheduledFor = ArabicDateParser.parse(plan.text) }
                    }
                }

                Section {
                    Toggle("مكتملة", isOn: $plan.isCompleted)
                }
            }
            // Runs for both "تم" and swipe-down dismissal.
            .onDisappear { PlanReminders.sync(plan) }
            .navigationTitle("تعديل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private var hasDate: Binding<Bool> {
        Binding(
            get: { plan.scheduledFor != nil },
            set: { isOn in
                withAnimation {
                    plan.scheduledFor = isOn
                        ? (ArabicDateParser.parse(plan.text) ?? Date.now.addingTimeInterval(3600))
                        : nil
                }
            }
        )
    }
}
