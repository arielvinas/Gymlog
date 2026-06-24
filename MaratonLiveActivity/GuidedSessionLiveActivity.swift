//
//  GuidedSessionLiveActivity.swift
//  MaratonLiveActivity (Widget Extension)
//
//  UI de la Live Activity: pantalla bloqueada + Dynamic Island. Dibuja el
//  `LiveSessionSnapshot` que la app del iPhone empuja desde el reloj. Los botones
//  ejecutan `AdvanceSetIntent`/`SkipRestIntent`, que mandan el comando al reloj.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

private let sessionTint = WorkoutType.fuerza.color

struct GuidedSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidedSessionActivityAttributes.self) { context in
            LockScreenView(snapshot: context.state.snapshot)
                .activityBackgroundTint(Color.black.opacity(0.5))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state.snapshot
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Fuerza", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sessionTint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let hr = s.heartRate, hr > 0 {
                        Label("\(hr)", systemImage: "heart.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomContent(s)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(sessionTint)
            } compactTrailing: {
                compactTrailing(s)
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(sessionTint)
            }
            .keylineTint(sessionTint)
        }
    }

    // MARK: Dynamic Island helpers

    @ViewBuilder
    private func bottomContent(_ s: LiveSessionSnapshot) -> some View {
        switch s.phase {
        case .resting:
            HStack(spacing: 10) {
                restLabel(s, compact: false)
                Spacer()
                Button(intent: SkipRestIntent(sessionID: s.sessionID)) {
                    Label(s.isOvertime ? "Empezar" : "Saltear",
                          systemImage: s.isOvertime ? "play.fill" : "forward.fill")
                }
                .tint(s.isOvertime ? .red : sessionTint)
            }
        case .logging:
            HStack(spacing: 10) {
                if s.setCount > 0 {
                    Text("Serie \(s.setNumber)/\(s.setCount)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: AdvanceSetIntent(sessionID: s.sessionID)) {
                    Label("Hecho", systemImage: "checkmark")
                }
                .tint(sessionTint)
            }
        case .done:
            Label("Sesión terminada", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func compactTrailing(_ s: LiveSessionSnapshot) -> some View {
        switch s.phase {
        case .resting:
            restLabel(s, compact: true)
        case .logging:
            if s.setCount > 0 {
                Text("\(s.setNumber)/\(s.setCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(sessionTint)
            }
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func restLabel(_ s: LiveSessionSnapshot, compact: Bool) -> some View {
        if let end = s.restEndDate, end > .now, !s.isOvertime {
            Text(timerInterval: .now...end, countsDown: true)
                .font(compact ? .caption2.weight(.bold).monospacedDigit()
                              : .subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(sessionTint)
                .frame(maxWidth: compact ? 44 : nil)
        } else {
            Text(s.isOvertime ? "¡Dale!" : "0:00")
                .font(compact ? .caption2.weight(.bold) : .subheadline.weight(.bold))
                .foregroundStyle(s.isOvertime ? .red : .secondary)
        }
    }
}

// MARK: - Pantalla bloqueada

private struct LockScreenView: View {
    let snapshot: LiveSessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Fuerza · en el reloj", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sessionTint)
                Spacer()
                if let hr = snapshot.heartRate, hr > 0 {
                    Label("\(hr)", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            Text(snapshot.exerciseName)
                .font(.headline)
                .lineLimit(1)

            content
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.phase {
        case .logging:
            HStack {
                if snapshot.setCount > 0 {
                    Text("Serie \(snapshot.setNumber) de \(snapshot.setCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: AdvanceSetIntent(sessionID: snapshot.sessionID)) {
                    Label("Hecho", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(sessionTint)
            }
        case .resting:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.isOvertime ? "Tiempo extra" : "Descanso")
                        .font(.caption)
                        .foregroundStyle(snapshot.isOvertime ? .red : .secondary)
                    restCountdown
                }
                Spacer()
                Button(intent: SkipRestIntent(sessionID: snapshot.sessionID)) {
                    Label(snapshot.isOvertime ? "Empezar serie" : "Saltear",
                          systemImage: snapshot.isOvertime ? "play.fill" : "forward.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(snapshot.isOvertime ? .red : sessionTint)
            }
        case .done:
            Label("Sesión terminada", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var restCountdown: some View {
        if let end = snapshot.restEndDate, end > .now, !snapshot.isOvertime {
            Text(timerInterval: .now...end, countsDown: true)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(sessionTint)
        } else {
            Text(snapshot.isOvertime ? "¡Dale!" : "0:00")
                .font(.title2.weight(.bold))
                .foregroundStyle(snapshot.isOvertime ? .red : .primary)
        }
    }
}
