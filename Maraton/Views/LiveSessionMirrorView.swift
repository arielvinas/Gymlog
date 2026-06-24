//
//  LiveSessionMirrorView.swift
//  Maraton
//
//  Espejo en vivo de la sesión de gimnasio que corre en el Apple Watch. Lee el
//  último `LiveSessionSnapshot` recibido por WatchConnectivity y permite avanzar
//  de serie / saltear descanso / corregir, mandando comandos al reloj (que es la
//  autoridad). No corre su propio engine: solo refleja y controla.
//

import SwiftUI
import Combine

struct LiveSessionMirrorView: View {
    @State private var link = LiveSessionConnectivity.shared
    @Environment(\.dismiss) private var dismiss

    /// Re-dibuja el cronómetro de tiempo extra (cuando el descanso ya pasó).
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    private var tint: Color { WorkoutType.fuerza.color }
    private var snapshot: LiveSessionSnapshot? { link.latestSnapshot }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot, snapshot.isActive {
                    content(snapshot)
                } else {
                    inactive
                }
            }
            .navigationTitle("En el reloj")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: snapshot?.isActive) { _, active in
            if active == false { dismiss() }
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private func content(_ s: LiveSessionSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                liveBadge
                progress(s)

                switch s.phase {
                case .logging: logging(s)
                case .resting: resting(s)
                case .done:    EmptyView()
                }
            }
            .padding()
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .foregroundStyle(tint)
            Text("Sesión en vivo desde el reloj")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let hr = snapshot?.heartRate, hr > 0 {
                Label("\(hr)", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    private func progress(_ s: LiveSessionSnapshot) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: s.progressFraction)
                .tint(tint)
            HStack {
                Text("Ejercicio \(s.exerciseIndex + 1) de \(s.exerciseCount)")
                Spacer()
                Text("\(s.loggedSetsCount) series")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Logging

    private func logging(_ s: LiveSessionSnapshot) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(s.exerciseName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if s.setCount > 0 {
                    Text("Serie \(s.setNumber) de \(s.setCount)")
                        .font(.subheadline)
                        .foregroundStyle(tint)
                }
                if let target = s.targetReps, !target.isEmpty {
                    Text("Objetivo \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if s.setCount > 0 {
                HStack(spacing: 12) {
                    if !s.isBodyweight {
                        valueTile(title: "Peso",
                                  value: s.weight.map { "\($0.formattedKg) kg" } ?? "—")
                    }
                    valueTile(title: s.isTimeBased ? "Segundos" : "Reps",
                              value: s.reps.map { "\($0)" } ?? "—")
                }
            }

            Button {
                send(.completeCurrent)
            } label: {
                Label("Hecho", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .controlSize(.large)

            if s.exerciseIndex > 0 || s.setNumber > 1 {
                Button {
                    send(.goBack)
                } label: {
                    Label("Anterior", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Resting

    private func resting(_ s: LiveSessionSnapshot) -> some View {
        let overtime = restIsOvertime(s)
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: restFraction(s))
                    .stroke(overtime ? Color.red : tint,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    restCountdown(s, overtime: overtime)
                    Text(overtime ? "tiempo extra" : "descanso")
                        .font(.caption)
                        .foregroundStyle(overtime ? Color.red : .secondary)
                }
            }
            .frame(width: 160, height: 160)

            HStack(spacing: 12) {
                Button { send(.adjustRest(-15)) } label: {
                    Label("15s", systemImage: "minus").frame(maxWidth: .infinity)
                }
                Button { send(.adjustRest(15)) } label: {
                    Label("15s", systemImage: "plus").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)

            Button {
                send(.skipRest)
            } label: {
                Label(overtime ? "Empezar serie" : "Saltear descanso",
                      systemImage: overtime ? "play.fill" : "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(overtime ? .red : tint)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func restCountdown(_ s: LiveSessionSnapshot, overtime: Bool) -> some View {
        if let end = s.restEndDate, end > now, !overtime {
            // Cuenta regresiva nativa (corre sola sin updates).
            Text(timerInterval: now...end, countsDown: true)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
        } else {
            Text(overtime ? "+\(overtimeSeconds(s).countdownLabel)" : "0:00")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(overtime ? .red : .primary)
        }
    }

    private var inactive: some View {
        ContentUnavailableView(
            "Sin sesión activa",
            systemImage: "applewatch.slash",
            description: Text("Empezá una sesión de gimnasio guiada en el Apple Watch para verla acá en vivo.")
        )
    }

    // MARK: - Helpers

    private func valueTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func send(_ action: LiveSessionAction) {
        guard let id = snapshot?.sessionID else { return }
        link.send(command: LiveSessionCommand(sessionID: id, action: action))
    }

    /// Segundos transcurridos desde que terminó el descanso (tiempo extra).
    private func overtimeSeconds(_ s: LiveSessionSnapshot) -> Int {
        guard let end = s.restEndDate else { return 0 }
        return max(0, Int(now.timeIntervalSince(end)))
    }

    private func restIsOvertime(_ s: LiveSessionSnapshot) -> Bool {
        if s.isOvertime { return true }
        guard let end = s.restEndDate else { return false }
        return now >= end
    }

    private func restFraction(_ s: LiveSessionSnapshot) -> Double {
        guard s.restTotal > 0, let end = s.restEndDate else { return restIsOvertime(s) ? 1 : 0 }
        let remaining = end.timeIntervalSince(now)
        if remaining <= 0 { return 1 }
        return min(1, remaining / Double(s.restTotal))
    }
}
