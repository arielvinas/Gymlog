//
//  CheckInCard.swift
//  Maraton
//
//  Check-in diario de recuperación: completar en menos de 10 segundos.
//

import SwiftUI
import SwiftData

struct CheckInCard: View {
    @Environment(\.modelContext) private var context

    /// Check-in existente para hoy (si ya se cargó).
    let existing: DailyCheckIn?

    @State private var energy = 3
    @State private var soreness = 3
    @State private var motivation = 3
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "¿Cómo amaneciste?", systemImage: "heart.text.square.fill", tint: .pink)

            if let existing, !editing {
                summary(for: existing)
            } else {
                inputs
            }
        }
        .dashboardCard()
        .onAppear(perform: cargarExistente)
    }

    // MARK: - Resumen

    private func summary(for checkIn: DailyCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Energía", value: checkIn.energy, symbol: "bolt.fill", tint: .yellow)
            summaryRow("Dolor muscular", value: checkIn.soreness, symbol: "figure.strengthtraining.traditional", tint: .orange)
            summaryRow("Motivación", value: checkIn.motivation, symbol: "flame.fill", tint: .pink)

            Button {
                editing = true
            } label: {
                Label("Editar", systemImage: "pencil")
                    .font(.subheadline)
            }
            .padding(.top, 2)
        }
    }

    private func summaryRow(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint)
            Spacer()
            Text("\(value)/5")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    // MARK: - Inputs

    private var inputs: some View {
        VStack(spacing: 12) {
            RatingSelector(title: "Energía", systemImage: "bolt.fill", tint: .yellow, value: $energy)
            RatingSelector(title: "Dolor muscular", systemImage: "figure.strengthtraining.traditional", tint: .orange, value: $soreness)
            RatingSelector(title: "Motivación", systemImage: "flame.fill", tint: .pink, value: $motivation)

            Button(action: guardar) {
                Text("Guardar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    // MARK: - Acciones

    private func cargarExistente() {
        if let existing {
            energy = existing.energy
            soreness = existing.soreness
            motivation = existing.motivation
        }
    }

    private func guardar() {
        if let existing {
            existing.energy = energy
            existing.soreness = soreness
            existing.motivation = motivation
        } else {
            let nuevo = DailyCheckIn(
                date: PlanConstants.calendar.startOfDay(for: Date()),
                energy: energy,
                soreness: soreness,
                motivation: motivation
            )
            context.insert(nuevo)
        }
        try? context.save()
        editing = false
    }
}

// MARK: - Selector de 1 a 5

private struct RatingSelector: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        value = i
                    } label: {
                        ZStack {
                            Circle()
                                .fill(i <= value ? tint : Color(.tertiarySystemFill))
                            Text("\(i)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(i <= value ? .white : .secondary)
                        }
                        .frame(width: 44, height: 44)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        CheckInCard(existing: nil)
            .padding()
    }
    .modelContainer(PreviewData.container)
}
