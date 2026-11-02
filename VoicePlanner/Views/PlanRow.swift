//
//  PlanRow.swift
//  VoicePlanner
//

import SwiftUI

struct PlanRow: View {
    let plan: Plan

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation(.snappy) { plan.isCompleted.toggle() }
                PlanReminders.sync(plan)
            } label: {
                Image(systemName: plan.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(plan.isCompleted ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plan.isCompleted ? "إلغاء الإنجاز" : "تحديد كمنجزة")

            VStack(alignment: .leading, spacing: 6) {
                Text(plan.text)
                    .font(.body)
                    .strikethrough(plan.isCompleted, color: .secondary)
                    .foregroundStyle(plan.isCompleted ? .secondary : .primary)

                metadata
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var metadata: some View {
        if let date = plan.scheduledFor {
            Label {
                // Text(_:format:) follows the environment locale set in VoicePlannerApp.
                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            } icon: {
                Image(systemName: isOverdue ? "exclamationmark.circle" : "calendar")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isOverdue ? Color.red : Color.accentColor)
        } else {
            Text(plan.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isOverdue: Bool {
        guard !plan.isCompleted, let date = plan.scheduledFor else { return false }
        return date < .now
    }
}
