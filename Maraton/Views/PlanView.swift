//
//  PlanView.swift
//  Maraton
//
//  Pantalla principal: el plan completo agrupado por semana.
//

import SwiftUI
import SwiftData

struct PlanView: View {
    @Query(sort: \WorkoutDay.date) private var days: [WorkoutDay]
    @Environment(\.modelContext) private var context

    @State private var showingNew = false
    @State private var editingDay: WorkoutDay?
    @State private var showingExport = false

    /// Días agrupados por semana, ordenados por la fecha de su primer día.
    private var weeks: [(title: String, tag: String?, days: [WorkoutDay])] {
        // `days` ya viene ordenado por fecha, así que cada grupo queda ordenado.
        let grouped = Dictionary(grouping: days, by: { $0.weekTitle })
        return grouped.values
            .sorted { ($0.first?.date ?? .distantPast) < ($1.first?.date ?? .distantPast) }
            .compactMap { weekDays in
                guard let first = weekDays.first else { return nil }
                return (title: first.weekTitle, tag: first.weekTag, days: weekDays)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(weeks, id: \.title) { week in
                    Section {
                        ForEach(week.days) { day in
                            NavigationLink {
                                WorkoutDetailView(day: day)
                            } label: {
                                WorkoutRow(day: day)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    eliminar(day)
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                                Button {
                                    editingDay = day
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        WeekHeader(title: week.title, tag: week.tag)
                    }
                }
            }
            .navigationTitle("Mi plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Label("Agregar día", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingExport = true
                    } label: {
                        Label("Compartir plan", systemImage: "square.and.arrow.up")
                    }
                    .disabled(days.isEmpty)
                }
            }
            .sheet(isPresented: $showingNew) {
                WorkoutEditView(editing: nil)
            }
            .sheet(item: $editingDay) { day in
                WorkoutEditView(editing: day)
            }
            .sheet(isPresented: $showingExport) {
                PlanExportSheet(days: days)
            }
        }
    }

    private func eliminar(_ day: WorkoutDay) {
        context.delete(day)
        try? context.save()
    }
}

// MARK: - Fila de entrenamiento

private struct WorkoutRow: View {
    let day: WorkoutDay

    private var isToday: Bool {
        PlanConstants.calendar.isDateInToday(day.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Punto de color según el tipo.
            Circle()
                .fill(day.type.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.weekdayAndDay)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(day.title)
                    .font(.body)
                    .fontWeight(isToday ? .semibold : .regular)

                if !day.detail.isEmpty {
                    Text(day.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isToday {
                Text("HOY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
            }

            if day.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isToday ? Color.accentColor.opacity(0.12) : nil)
    }
}

// MARK: - Encabezado de semana

private struct WeekHeader: View {
    let title: String
    let tag: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let tag {
                Text(tag)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
        }
    }
}

#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
