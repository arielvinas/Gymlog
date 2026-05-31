//
//  SupplementSettingsView.swift
//  Maraton
//
//  Configuración de recordatorios locales por suplemento.
//

import SwiftUI
import SwiftData

struct SupplementSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var reminders: [SupplementReminder]

    @State private var showAuthDenied = false

    var body: some View {
        List {
            Section {
                ForEach(SupplementKind.allCases) { kind in
                    let reminder = SupplementTracker.reminder(for: kind, in: reminders, context: context)
                    ReminderRow(reminder: reminder) { showAuthDenied = true }
                }
            } footer: {
                Text("Te avisamos todos los días a la hora elegida. Mantener el hábito suma para tu preparación.")
            }
        }
        .navigationTitle("Recordatorios")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Notificaciones desactivadas", isPresented: $showAuthDenied) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Activá las notificaciones de Maratón desde Ajustes para recibir los recordatorios.")
        }
    }
}

// MARK: - Fila de recordatorio

private struct ReminderRow: View {
    @Bindable var reminder: SupplementReminder
    @Environment(\.modelContext) private var context
    var onAuthDenied: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $reminder.enabled) {
                Label(reminder.kind.displayName, systemImage: reminder.kind.symbolName)
                    .foregroundStyle(reminder.kind.color)
            }
            .onChange(of: reminder.enabled) { _, nuevo in
                if nuevo {
                    Task {
                        let ok = await NotificationManager.shared.requestAuthorization()
                        if ok {
                            aplicar()
                        } else {
                            reminder.enabled = false
                            try? context.save()
                            onAuthDenied()
                        }
                    }
                } else {
                    aplicar()
                }
            }

            if reminder.enabled {
                DatePicker("Hora", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "es_AR"))
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            PlanConstants.calendar.date(
                bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()
            ) ?? Date()
        } set: { nuevaFecha in
            let comps = PlanConstants.calendar.dateComponents([.hour, .minute], from: nuevaFecha)
            reminder.hour = comps.hour ?? reminder.hour
            reminder.minute = comps.minute ?? 0
            aplicar()
        }
    }

    private func aplicar() {
        try? context.save()
        NotificationManager.shared.reschedule(reminder)
    }
}

#Preview {
    NavigationStack {
        SupplementSettingsView()
    }
    .modelContainer(PreviewData.container)
}
