//
//  Plan.swift
//  VoicePlanner
//
//  The single SwiftData entity: one captured idea / plan.
//

import Foundation
import SwiftData

@Model
final class Plan {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    /// Filled automatically by `ArabicDateParser` when the spoken text contains a time
    /// expression ("غداً الساعة 5 مساءً"), and editable afterwards.
    var scheduledFor: Date?
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        scheduledFor: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.isCompleted = isCompleted
    }
}
