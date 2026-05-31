//
//  RootView.swift
//  Maraton
//
//  Contenedor principal con las tres pestañas de la app.
//

import SwiftUI
import SwiftData

struct RootView: View {
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
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
