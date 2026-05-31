//
//  RootView.swift
//  Maraton
//
//  Contenedor principal con las tres pestañas de la app.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Hoy", systemImage: "sun.max.fill")
                }

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }

            ProgressDashboardView()
                .tabItem {
                    Label("Progreso", systemImage: "chart.bar.fill")
                }
        }
        .task {
            // Reprograma los recordatorios activos (p. ej. tras reinstalar).
            if let reminders = try? context.fetch(FetchDescriptor<SupplementReminder>()) {
                NotificationManager.shared.rescheduleAll(reminders)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
