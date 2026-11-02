//
//  SpeechManager.swift
//  VoicePlanner
//
//  Real-time Arabic dictation with SFSpeechRecognizer + AVAudioEngine.
//
//  Requires two Info.plist keys (see VoicePlannerApp.swift):
//    • NSMicrophoneUsageDescription
//    • NSSpeechRecognitionUsageDescription
//  If either key is missing, iOS terminates the app the first time it asks for permission.
//
//  Concurrency note: Speech and AVFoundation call their completion handlers on
//  background threads. Every closure handed to those APIs is created inside a
//  `nonisolated` helper, so Swift 6 doesn't infer it as @MainActor and then
//  crash with a runtime isolation check when the framework calls it off-main.
//

import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechManager {

    enum State: Equatable {
        case idle
        case preparing   // Waiting for permissions / audio session.
        case recording
        case finishing   // The mic is off; waiting for the final transcription.
    }

    enum SpeechError: LocalizedError {
        case speechPermissionDenied
        case microphonePermissionDenied
        case recognizerUnavailable
        case onDeviceRecognitionUnavailable
        case noAudioInput
        case recognitionFailed

        var errorDescription: String? {
            switch self {
            case .speechPermissionDenied:
                "لم يُسمح بالتعرّف على الكلام. فعّله من الإعدادات ← الخصوصية والأمان ← التعرّف على الكلام."
            case .microphonePermissionDenied:
                "لم يُسمح باستخدام الميكروفون. فعّله من الإعدادات ← الخصوصية والأمان ← الميكروفون."
            case .recognizerUnavailable:
                "التعرّف على الكلام باللغة العربية غير متاح حالياً."
            case .onDeviceRecognitionUnavailable:
                "التعرّف على الكلام العربي دون إنترنت غير مدعوم على هذا الجهاز. أضف العربية إلى لغات الإملاء من الإعدادات ← عام ← لوحة المفاتيح ثم أعد المحاولة."
            case .noAudioInput:
                "لا يوجد ميكروفون متاح. شغّل التطبيق على جهاز iPhone حقيقي."
            case .recognitionFailed:
                "لم أتمكن من فهم الكلام. حاول مرة أخرى."
            }
        }
    }

    // MARK: Configuration

    /// Saudi Arabic. `init` falls back to generic Arabic if this variant isn't installed.
    static let preferredLocale = Locale(identifier: "ar-SA")

    /// `true` means audio is never sent to Apple's servers. If the device has no
    /// on-device Arabic model, recording fails with `.onDeviceRecognitionUnavailable`
    /// and nothing goes over the network.
    /// Set this to `false` only if you accept server-side recognition as a fallback.
    static let requiresOnDeviceRecognition = true

    // MARK: Observable state

    private(set) var state: State = .idle
    private(set) var transcript = ""
    var errorMessage: String?

    // MARK: Private

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var didReceiveFinalResult = false
    @ObservationIgnored private var finalResultWaiter: CheckedContinuation<Void, Never>?

    init() {
        recognizer = SFSpeechRecognizer(locale: Self.preferredLocale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "ar"))
    }

    // MARK: Public API

    /// Call this on launch so the first press on the mic button records right away
    /// instead of opening the permission alerts.
    func requestPermissionsIfNeeded() async {
        do {
            try await ensurePermissions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts streaming microphone audio into the recognizer. `transcript` updates live.
    func startRecording() async {
        guard state == .idle else { return }
        state = .preparing
        transcript = ""
        errorMessage = nil

        do {
            try await ensurePermissions()
            // The user may have released the button while a permission alert was up.
            guard state == .preparing else { return }
            try beginRecognition()
            state = .recording
        } catch {
            errorMessage = error.localizedDescription
            tearDown()
        }
    }

    /// Stops the mic, waits briefly for the recognizer's final result, and returns it.
    func finishRecording() async -> String {
        switch state {
        case .preparing:
            state = .idle   // Makes the pending `startRecording` bail out.
            return ""
        case .idle, .finishing:
            return ""
        case .recording:
            break
        }

        state = .finishing
        stopAudio()
        request?.endAudio()
        if !didReceiveFinalResult {
            await waitForFinalResult(timeout: .seconds(2))
        }

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        tearDown()
        return text
    }

    /// Discards the current recording.
    func cancelRecording() {
        guard state != .idle else { return }
        tearDown()
        transcript = ""
    }

    // MARK: Recognition

    private func beginRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        if Self.requiresOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
            throw SpeechError.onDeviceRecognitionUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = Self.requiresOnDeviceRecognition
        request.addsPunctuation = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // The Simulator (and devices with no mic route) report a 0 Hz format.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.noAudioInput
        }

        Self.installTap(on: inputNode, format: format, feeding: request)
        audioEngine.prepare()
        try audioEngine.start()

        let id = UUID()
        sessionID = id
        didReceiveFinalResult = false
        self.request = request
        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failed: failed, session: id)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, session: UUID) {
        // Ignore late callbacks from a previous or cancelled session.
        guard session == sessionID, state == .recording || state == .finishing else { return }

        if let text { transcript = text }
        guard isFinal || failed else { return }

        didReceiveFinalResult = true
        if state == .recording {
            // The recognizer stopped by itself (e.g. a long silence). Turn off the mic.
            // When the button is released, whatever was transcribed gets saved.
            stopAudio()
            if failed && transcript.isEmpty {
                errorMessage = SpeechError.recognitionFailed.localizedDescription
            }
        }
        resumeFinalWaiter()
    }

    private func waitForFinalResult(timeout: Duration) async {
        await withCheckedContinuation { continuation in
            finalResultWaiter = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resumeFinalWaiter()
            }
        }
    }

    private func resumeFinalWaiter() {
        finalResultWaiter?.resume()
        finalResultWaiter = nil
    }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tearDown() {
        task?.cancel()
        task = nil
        request = nil
        stopAudio()
        didReceiveFinalResult = false
        resumeFinalWaiter()
        state = .idle
    }

    // MARK: Permissions

    private func ensurePermissions() async throws {
        guard await Self.speechAuthorization() == .authorized else {
            throw SpeechError.speechPermissionDenied
        }
        guard await Self.microphonePermission() else {
            throw SpeechError.microphonePermissionDenied
        }
    }

    // MARK: Nonisolated bridges to callback-based APIs

    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private nonisolated static func microphonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// The tap block runs on a real-time audio thread.
    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (_ text: String?, _ isFinal: Bool, _ failed: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}
