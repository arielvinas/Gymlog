//
//  LiveSessionBanner.swift
//  Maraton
//
//  Banner compacto que aparece arriba de la app cuando hay una sesión de
//  gimnasio guiada corriendo en el Apple Watch. Al tocarlo abre el espejo en
//  vivo (`LiveSessionMirrorView`).
//

import SwiftUI

struct LiveSessionBanner: View {
    let snapshot: LiveSessionSnapshot
    let onTap: () -> Void

    private var tint: Color { WorkoutType.fuerza.color }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let hr = snapshot.heartRate, hr > 0 {
                    Label("\(hr)", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var headline: String {
        switch snapshot.phase {
        case .resting: return "Descanso en el reloj"
        case .done:    return "Sesión terminada"
        case .logging: return "Sesión en el reloj"
        }
    }

    private var subtitle: String {
        if snapshot.phase == .resting { return "Tocá para controlar el descanso" }
        let serie = snapshot.setCount > 0 ? " · serie \(snapshot.setNumber)/\(snapshot.setCount)" : ""
        return snapshot.exerciseName + serie
    }
}
