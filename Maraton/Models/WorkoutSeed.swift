//
//  WorkoutSeed.swift
//  Maraton
//
//  Datos del plan de entrenamiento para pre-cargar en el primer arranque.
//

import Foundation
import SwiftData

enum WorkoutSeed {

    // MARK: - Descripciones largas reutilizables

    private static let descFondo = """
    Correr a ritmo conversacional (Zona 2, esfuerzo 4-5/10). Podés hablar en \
    frases completas. El objetivo es tiempo en pie, no velocidad.
    """

    private static let descCalidad = """
    Entrada en calor 10', luego los bloques a ritmo firme 7/10 (cómodamente \
    difícil, no podés mantener una charla), trote suave entre bloques, vuelta a \
    la calma 5'. Es el único día rápido de la semana.
    """

    private static let descRodaje = """
    Trote regenerativo en Zona 2, bien tranquilo.
    """

    private static let descFuerzaA = """
    Empuje (press banca, hombros, vuelos), pierna de mantenimiento (sentadilla y \
    hip thrust moderados, sin fallo), core. Dejá 1-2 reps en reserva.
    """

    private static let descFuerzaB = """
    Tirón (remo, dorsales, pull over), bíceps, core.
    """

    private static let descDescanso = """
    Opcional movilidad o trote muy suave. La recuperación es parte del plan.
    """

    private static let descCarrera = """
    ¡El gran día! Media Maratón de Córdoba, 21,1 km. Salí con ritmo controlado en \
    los primeros kilómetros, hidratá y usá los geles que practicaste en los fondos. \
    Disfrutá: todo el trabajo ya está hecho.
    """

    /// Devuelve la descripción larga según el tipo y el título del entrenamiento.
    private static func longDescription(for type: WorkoutType, title: String) -> String {
        switch type {
        case .fondo:    return descFondo
        case .calidad:  return descCalidad
        case .rodaje:   return descRodaje
        case .carrera:  return descCarrera
        case .descanso: return descDescanso
        case .fuerza:
            return title.localizedCaseInsensitiveContains("B") ? descFuerzaB : descFuerzaA
        }
    }

    // MARK: - Definición del plan

    /// Una entrada cruda del plan antes de convertirse en `WorkoutDay`.
    private struct Entry {
        let year: Int
        let month: Int
        let day: Int
        let title: String
        let detail: String
        let type: WorkoutType
    }

    /// Una semana del plan con su etiqueta opcional.
    private struct Week {
        let title: String
        let tag: String?
        let entries: [Entry]
    }

    private static let plan: [Week] = [
        Week(title: "Arranque", tag: nil, entries: [
            Entry(year: 2026, month: 5, day: 30, title: "Descanso + movilidad 10'", detail: "", type: .descanso),
            Entry(year: 2026, month: 5, day: 31, title: "Fondo largo 12 km", detail: "Z2 conversacional", type: .fondo),
        ]),
        Week(title: "Semana 1", tag: nil, entries: [
            Entry(year: 2026, month: 6, day: 1, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 2, title: "Fuerza A", detail: "Empuje + pierna + core", type: .fuerza),
            Entry(year: 2026, month: 6, day: 3, title: "Rodaje suave 5 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 4, title: "Calidad · 2×10' tempo", detail: "(7/10), 3' trote", type: .calidad),
            Entry(year: 2026, month: 6, day: 5, title: "Fuerza B", detail: "Tirón + core", type: .fuerza),
            Entry(year: 2026, month: 6, day: 6, title: "Descanso", detail: "(o trote 15')", type: .descanso),
            Entry(year: 2026, month: 6, day: 7, title: "Fondo largo 14 km", detail: "", type: .fondo),
        ]),
        Week(title: "Semana 2", tag: nil, entries: [
            Entry(year: 2026, month: 6, day: 8, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 9, title: "Fuerza A", detail: "", type: .fuerza),
            Entry(year: 2026, month: 6, day: 10, title: "Rodaje suave 6 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 11, title: "Calidad · 2×10' tempo", detail: "3' trote", type: .calidad),
            Entry(year: 2026, month: 6, day: 12, title: "Fuerza B", detail: "", type: .fuerza),
            Entry(year: 2026, month: 6, day: 13, title: "Descanso", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 14, title: "Fondo largo 16 km", detail: "Practicá geles", type: .fondo),
        ]),
        Week(title: "Semana 3", tag: "Pico de volumen", entries: [
            Entry(year: 2026, month: 6, day: 15, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 16, title: "Fuerza A", detail: "", type: .fuerza),
            Entry(year: 2026, month: 6, day: 17, title: "Rodaje suave 6 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 18, title: "Calidad · 25-30' continuos tempo", detail: "", type: .calidad),
            Entry(year: 2026, month: 6, day: 19, title: "Fuerza B", detail: "", type: .fuerza),
            Entry(year: 2026, month: 6, day: 20, title: "Descanso", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 21, title: "Fondo largo 18 km", detail: "Tope · geles", type: .fondo),
        ]),
        Week(title: "Semana 4", tag: nil, entries: [
            Entry(year: 2026, month: 6, day: 22, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 23, title: "Fuerza A", detail: "", type: .fuerza),
            Entry(year: 2026, month: 6, day: 24, title: "Rodaje suave 6 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 25, title: "Calidad · 25-30' continuos tempo", detail: "", type: .calidad),
            Entry(year: 2026, month: 6, day: 26, title: "Fuerza B", detail: "", type: .fuerza),
            Entry(year: 2026, month: 6, day: 27, title: "Descanso", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 28, title: "Fondo 13-14 km", detail: "Arranca el taper", type: .fondo),
        ]),
        Week(title: "Semana 5", tag: "Taper", entries: [
            Entry(year: 2026, month: 6, day: 29, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 30, title: "Fuerza liviana", detail: "Mitad de series, sin pierna pesada", type: .fuerza),
            Entry(year: 2026, month: 7, day: 1, title: "Rodaje suave 4-5 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 7, day: 2, title: "Tempo cortito 15'", detail: "", type: .calidad),
            Entry(year: 2026, month: 7, day: 3, title: "Descanso o trote muy corto 10'", detail: "", type: .descanso),
            Entry(year: 2026, month: 7, day: 4, title: "Descanso total", detail: "Hidratar + cargar hidratos", type: .descanso),
            Entry(year: 2026, month: 7, day: 5, title: "Media Maratón Córdoba", detail: "21,1 km", type: .carrera),
        ]),
    ]

    // MARK: - Construcción

    /// Crea todos los `WorkoutDay` del plan listos para insertar.
    static func allWorkoutDays() -> [WorkoutDay] {
        var result: [WorkoutDay] = []
        for (index, week) in plan.enumerated() {
            for entry in week.entries {
                let day = WorkoutDay(
                    date: DateComponents.makeDate(year: entry.year, month: entry.month, day: entry.day),
                    title: entry.title,
                    detail: entry.detail,
                    longDescription: longDescription(for: entry.type, title: entry.title),
                    type: entry.type,
                    weekTitle: week.title,
                    weekTag: week.tag,
                    weekOrder: index
                )
                result.append(day)
            }
        }
        return result
    }

    /// Inserta el plan en el contexto sólo si todavía no hay datos.
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutDay>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for day in allWorkoutDays() {
            context.insert(day)
        }
        try? context.save()
    }
}
