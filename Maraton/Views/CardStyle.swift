//
//  CardStyle.swift
//  Maraton
//
//  Estilo de tarjeta reutilizable para el dashboard.
//

import SwiftUI

private struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

extension View {
    /// Aplica el contenedor estándar de tarjeta del dashboard.
    func dashboardCard() -> some View {
        modifier(DashboardCardModifier())
    }
}

/// Encabezado consistente para las tarjetas (ícono + título).
struct CardHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label {
            Text(title)
                .font(.headline)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}
