//
//  GuidedSessionActivityAttributes.swift
//  Maraton (compartido app iOS + Widget Extension)
//
//  Define la Live Activity de la sesión de gimnasio en vivo. El estado dinámico
//  es el `LiveSessionSnapshot` completo que llega del reloj; no hay atributos
//  estáticos. Solo se compila donde existe ActivityKit (iOS, no watchOS ni
//  Mac Catalyst).
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

struct GuidedSessionActivityAttributes: ActivityAttributes {
    /// El estado que cambia durante la sesión: la foto que difunde el reloj.
    struct ContentState: Codable, Hashable {
        var snapshot: LiveSessionSnapshot
    }
}
#endif
