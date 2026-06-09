//
//  RootView.swift
//  Maraton
//
//  Contenedor principal: barra lateral en Mac, pestañas en iPhone.
//

import SwiftUI
import SwiftData
import Observation

/// Secciones principales de la app.
enum AppSection: String, CaseIterable, Identifiable {
    case hoy, plan, progreso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoy:      return "Detalle"
        case .plan:     return "Plan"
        case .progreso: return "Progreso"
        }
    }

    var symbol: String {
        switch self {
        case .hoy:      return "sun.max.fill"
        case .plan:     return "calendar"
        case .progreso: return "chart.bar.fill"
        }
    }
}

/// Estado de navegación compartido (lo usan la UI y los atajos de teclado).
@Observable
final class Navigator {
    var section: AppSection = .hoy
}

struct RootView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            SidebarRootView()
            #else
            TabRootView()
            #endif
        }
        .task {
            // Reprograma los recordatorios activos (p. ej. tras reinstalar).
            if let reminders = try? context.fetch(FetchDescriptor<SupplementReminder>()) {
                NotificationManager.shared.rescheduleAll(reminders)
            }
        }
    }
}

// MARK: - iPhone / iPad: pestañas

private struct TabRootView: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.section) {
            DayDetailView()
                .tabItem { Label("Detalle", systemImage: "sun.max.fill") }
                .tag(AppSection.hoy)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppSection.plan)
            ProgressDashboardView()
                .tabItem { Label("Progreso", systemImage: "chart.bar.fill") }
                .tag(AppSection.progreso)
        }
    }
}

// MARK: - Mac: barra lateral

private struct SidebarRootView: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        NavigationSplitView {
            // En Mac Catalyst el `List(selection:)` con filas normales no cambia
            // la selección al tocar (heredado del comportamiento de iOS, que solo
            // selecciona en modo edición). Manejamos el tap con botones para que
            // el click funcione igual que los atajos ⌘1/⌘2/⌘3.
            List {
                ForEach(AppSection.allCases) { section in
                    Button {
                        navigator.section = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .foregroundStyle(navigator.section == section ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        navigator.section == section
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .navigationTitle("Maratón")
        } detail: {
            switch navigator.section {
            case .hoy:      DayDetailView()
            case .plan:     PlanView()
            case .progreso: ProgressDashboardView()
            }
        }
    }
}

// MARK: - Menús y atajos de teclado (Mac)

struct SectionCommands: Commands {
    var navigator: Navigator

    var body: some Commands {
        CommandMenu("Ir a") {
            Button("Detalle") { navigator.section = .hoy }
                .keyboardShortcut("1", modifiers: .command)
            Button("Plan") { navigator.section = .plan }
                .keyboardShortcut("2", modifiers: .command)
            Button("Progreso") { navigator.section = .progreso }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}

#Preview {
    RootView()
        .environment(Navigator())
        .modelContainer(PreviewData.container)
}
