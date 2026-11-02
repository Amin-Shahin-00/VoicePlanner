//
//  ContentView.swift
//  VoicePlanner
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var plans: [Plan]

    @State private var speech = SpeechManager()
    @State private var editingPlan: Plan?
    @State private var savedCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    ContentUnavailableView(
                        "لا توجد أفكار بعد",
                        systemImage: "mic.badge.plus",
                        description: Text("اضغط مطولاً على الميكروفون وتحدّث، أو قل لـ Siri: «أضف فكرة في مخطط».")
                    )
                } else {
                    planList
                }
            }
            .navigationTitle("خططي")
            .safeAreaInset(edge: .bottom, spacing: 0) { captureBar }
            .sheet(item: $editingPlan) { plan in
                EditPlanView(plan: plan)
            }
            .alert("تعذّر التسجيل", isPresented: isShowingError) {
                Button("حسناً", role: .cancel) {}
            } message: {
                Text(speech.errorMessage ?? "")
            }
        }
        .task {
            await speech.requestPermissionsIfNeeded()
            await PlanReminders.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { speech.cancelRecording() }
        }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    // MARK: List

    private var planList: some View {
        List {
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { row(for: $0) }
                } header: {
                    Label("القادمة (\(upcoming.count))", systemImage: "clock")
                }
            }
            if !completed.isEmpty {
                Section {
                    ForEach(completed) { row(for: $0) }
                } header: {
                    Label("المكتملة (\(completed.count))", systemImage: "checkmark.seal")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for plan: Plan) -> some View {
        PlanRow(plan: plan)
            .contentShape(Rectangle())
            .onTapGesture { editingPlan = plan }
            .swipeActions(edge: .trailing) {
                Button("حذف", systemImage: "trash", role: .destructive) {
                    PlanReminders.cancel(plan)
                    withAnimation { context.delete(plan) }
                }
            }
            .swipeActions(edge: .leading) {
                Button(
                    plan.isCompleted ? "إعادة" : "إنجاز",
                    systemImage: plan.isCompleted ? "arrow.uturn.backward" : "checkmark"
                ) {
                    withAnimation { plan.isCompleted.toggle() }
                    PlanReminders.sync(plan)
                }
                .tint(plan.isCompleted ? .orange : .green)
            }
    }

    /// Plans with a date come first (soonest first), then undated ones (newest first).
    private var upcoming: [Plan] {
        plans.filter { !$0.isCompleted }.sorted { a, b in
            switch (a.scheduledFor, b.scheduledFor) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.createdAt > b.createdAt
            }
        }
    }

    private var completed: [Plan] {
        plans.filter(\.isCompleted).sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Capture

    private var captureBar: some View {
        VStack(spacing: 12) {
            if speech.state == .recording || speech.state == .finishing {
                LiveTranscriptBubble(text: speech.transcript, isFinishing: speech.state == .finishing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HoldToSpeakButton(
                isRecording: speech.state == .recording,
                onPress: startCapture,
                onRelease: endCapture
            )

            Text(speech.state == .recording ? "اسحب للأعلى للإلغاء" : "اضغط مطولاً وتحدّث")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .animation(.spring(duration: 0.3), value: speech.state)
    }

    private func startCapture() {
        Task { await speech.startRecording() }
    }

    private func endCapture(cancelled: Bool) {
        // Always go through a Task so this runs after `startCapture`'s Task.
        Task {
            if cancelled {
                speech.cancelRecording()
                return
            }
            let text = await speech.finishRecording()
            save(text)
        }
    }

    private func save(_ text: String) {
        guard !text.isEmpty else { return }
        let plan = Plan(text: text, scheduledFor: ArabicDateParser.parse(text))
        withAnimation { context.insert(plan) }
        try? context.save()
        PlanReminders.sync(plan)
        savedCount += 1
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { speech.errorMessage != nil },
            set: { if !$0 { speech.errorMessage = nil } }
        )
    }
}

// MARK: - Live transcript

private struct LiveTranscriptBubble: View {
    let text: String
    let isFinishing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.isEmpty ? "أستمع إليك…" : text)
                .font(.body)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.default, value: text)

            // Show the detected date while the user is speaking.
            if let date = ArabicDateParser.parse(text) {
                Label {
                    Text(date, format: .dateTime.weekday(.wide).day().month().hour().minute())
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }

            if isFinishing {
                ProgressView().controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Plan.self, inMemory: true)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
}
