//
//  PlanReminders.swift
//  VoicePlanner
//
//  Local notifications at `Plan.scheduledFor`. These are scheduled on the device
//  itself and need no network. No Info.plist key or capability is required.
//
//  One pending notification per plan, identified by the plan's UUID. Call `sync`
//  after any change to a plan's text, date or completion. It removes the old
//  notification and schedules a new one only if the plan is still due in the future.
//

import Foundation
import UserNotifications

enum PlanReminders {

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func sync(_ plan: Plan) {
        let center = UNUserNotificationCenter.current()
        let id = plan.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard !plan.isCompleted, let date = plan.scheduledFor, date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "حان موعد خطتك"
        content.body = plan.text
        content.sound = .default

        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    static func cancel(_ plan: Plan) {
        let id = plan.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}

/// Without a delegate, iOS hides notifications that fire while the app is open.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
