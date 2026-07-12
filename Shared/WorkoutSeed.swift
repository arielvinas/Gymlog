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
    Arrancá con el circuito de acondicionamiento (3 vueltas, sin pausa entre \
    ejercicios) y seguí con el específico, también en circuito. Después, el \
    bloque principal de fuerza: tirón, pierna y brazos. Dejá 1-2 reps en reserva.
    """

    private static let descFuerzaB = """
    Acondicionamiento y específico en circuito (3 vueltas cada uno, sin pausa \
    entre ejercicios) y después el bloque principal: hombro, pecho, pierna y \
    brazos. Cuidá la técnica en los unilaterales. Dejá 1-2 reps en reserva.
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
    static func longDescription(for type: WorkoutType, title: String) -> String {
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
        Week(title: "Pre-arranque", tag: nil, entries: [
            Entry(year: 2026, month: 5, day: 26, title: "Fuerza A", detail: "Empuje + pierna + core", type: .fuerza),
            Entry(year: 2026, month: 5, day: 27, title: "Rodaje suave 5 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 5, day: 28, title: "Calidad · 2×10' tempo", detail: "(7/10), 3' trote", type: .calidad),
            Entry(year: 2026, month: 5, day: 29, title: "Fuerza B", detail: "Tirón + core", type: .fuerza),
        ]),
        Week(title: "Arranque", tag: nil, entries: [
            Entry(year: 2026, month: 5, day: 30, title: "Descanso + movilidad 10'", detail: "", type: .descanso),
            Entry(year: 2026, month: 5, day: 31, title: "Fondo largo 12 km", detail: "Z2 conversacional", type: .fondo),
        ]),
        Week(title: "Semana 1", tag: nil, entries: [
            Entry(year: 2026, month: 6, day: 1, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 2, title: "Fuerza A", detail: "Empuje + pierna + core", type: .fuerza),
            Entry(year: 2026, month: 6, day: 3, title: "Rodaje suave 5 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 4, title: "Fuerza B", detail: "Espalda + tríceps + core", type: .fuerza),
            Entry(year: 2026, month: 6, day: 5, title: "Calidad · 2×10' tempo", detail: "(7/10), 3' trote", type: .calidad),
            Entry(year: 2026, month: 6, day: 6, title: "Descanso", detail: "(o trote 15')", type: .descanso),
            Entry(year: 2026, month: 6, day: 7, title: "Fondo largo 14 km", detail: "", type: .fondo),
        ]),
        Week(title: "Semana 2", tag: nil, entries: [
            Entry(year: 2026, month: 6, day: 8, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 9, title: "Fuerza A", detail: "Día 1", type: .fuerza),
            Entry(year: 2026, month: 6, day: 10, title: "Rodaje suave 6 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 11, title: "Calidad · 5×3' a ritmo controlado", detail: "(5:30-5:45/km), 90\" trote", type: .calidad),
            Entry(year: 2026, month: 6, day: 12, title: "Fuerza B", detail: "Día 2", type: .fuerza),
            Entry(year: 2026, month: 6, day: 13, title: "Descanso", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 14, title: "Fondo largo 16 km", detail: "Practicá geles", type: .fondo),
        ]),
        Week(title: "Semana 3", tag: "Pico de volumen", entries: [
            Entry(year: 2026, month: 6, day: 15, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 16, title: "Fuerza A", detail: "Día 1 · sin saltos", type: .fuerza),
            Entry(year: 2026, month: 6, day: 17, title: "Rodaje suave 6 km", detail: "Z2", type: .rodaje),
            Entry(year: 2026, month: 6, day: 18, title: "Calidad · 4×4' a ritmo controlado", detail: "90\" trote", type: .calidad),
            Entry(year: 2026, month: 6, day: 19, title: "Fuerza B", detail: "Día 2 · sin saltos", type: .fuerza),
            Entry(year: 2026, month: 6, day: 20, title: "Descanso", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 21, title: "Fondo largo 18 km", detail: "Tope de volumen · geles", type: .fondo),
        ]),
        Week(title: "Semana 4", tag: nil, entries: [
            Entry(year: 2026, month: 6, day: 22, title: "Descanso / movilidad", detail: "", type: .descanso),
            Entry(year: 2026, month: 6, day: 23, title: "Fuerza A", detail: "Día 1", type: .fuerza),
            Entry(year: 2026, month: 6, day: 24, title: "Descanso de rodilla + movilidad", detail: "Movilidad, elongación de gemelo/sóleo y protocolo de Alfredson. Caminar normal sí; no correr ni testear la rodilla a propósito.", type: .descanso),
            Entry(year: 2026, month: 6, day: 25, title: "Fuerza · Día 2 (tren superior + core)", detail: "Sin pierna pesada ni saltos. Sumar Alfredson.", type: .fuerza),
            Entry(year: 2026, month: 6, day: 26, title: "Descanso / movilidad", detail: "Movilidad y Alfredson.", type: .descanso),
            Entry(year: 2026, month: 6, day: 27, title: "Descanso", detail: "Que la rodilla llegue fresca al trote de prueba. Movilidad ligera opcional.", type: .descanso),
            Entry(year: 2026, month: 6, day: 28, title: "Trote de PRUEBA (decisión rodilla)", detail: "15-20 min muy suave (Zona 2), en llano. Llevar el donut en el dedo. Es el test que define si la rodilla está para la carrera: si no duele corriendo ni al día siguiente, buena señal; si duele, cambia la pisada o aparece al otro día, no correr.", type: .calidad),
        ]),
        Week(title: "Semana 5", tag: "Taper", entries: [
            Entry(year: 2026, month: 6, day: 29, title: "Descanso (evaluar rodilla)", detail: "Clave: cómo respondió la rodilla al trote de ayer. Sin dolor = seguimos. Con dolor = replantear la carrera.", type: .descanso),
            Entry(year: 2026, month: 6, day: 30, title: "Fuerza liviana (tren superior)", detail: "Mitad de series, sin pierna ni saltos. Solo si la rodilla viene bien.", type: .fuerza),
            Entry(year: 2026, month: 7, day: 1, title: "Trote suave 4-5 km (condicional)", detail: "Solo si el trote del domingo salió sin dolor. Muy suave, Zona 2. Si la rodilla protesta, descanso.", type: .rodaje),
            Entry(year: 2026, month: 7, day: 2, title: "Trote suave 15 min + unos pocos cambios de ritmo (condicional)", detail: "Solo si todo viene sin dolor. Nada exigente. Última activación antes de la carrera.", type: .calidad),
            Entry(year: 2026, month: 7, day: 3, title: "Descanso", detail: "Movilidad ligera.", type: .descanso),
            Entry(year: 2026, month: 7, day: 4, title: "Descanso total (víspera)", detail: "Hidratar, cargar hidratos, preparar todo: donut, vendaje, ropa.", type: .descanso),
            Entry(year: 2026, month: 7, day: 5, title: "Media Maratón Córdoba 21,1 km", detail: "Correr SOLO si la rodilla respondió bien a las pruebas. Si hay dolor que cambia la pisada, parar. La salud vale más que terminar.", type: .carrera),
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

    /// Versión del plan canónico. Subir este número cuando se agreguen días
    /// nuevos al plan que deban sincronizarse en instalaciones existentes.
    static let planVersion = 2

    private static let versionKey = "seededPlanVersion"

    /// Versión de plan ya sembrada. Con iCloud activo se guarda también en el
    /// Key-Value Store (que sincroniza) para no re-sembrar ni duplicar al
    /// reinstalar o estrenar un dispositivo nuevo; si no, sólo local.
    private static var storedVersion: Int {
        AppData.seedFlags.integer(forKey: versionKey)
    }

    private static func markSeeded(_ version: Int) {
        AppData.seedFlags.setInteger(version, forKey: versionKey)
    }

    /// Inserta el plan en el primer arranque, sólo si no se sembró antes y no
    /// hay datos locales todavía.
    static func seedIfNeeded(context: ModelContext) {
        guard storedVersion == 0 else { return }

        let count = (try? context.fetchCount(FetchDescriptor<WorkoutDay>())) ?? 0
        guard count == 0 else { return }

        for day in allWorkoutDays() {
            context.insert(day)
        }
        try? context.save()
        markSeeded(planVersion)
    }

    /// Aplica las novedades del plan: inserta los días del plan canónico que
    /// falten (por fecha) sin tocar los existentes, una sola vez por versión.
    /// Los días que el usuario borre no se vuelven a insertar.
    static func applyPlanUpdates(context: ModelContext) {
        let stored = storedVersion
        guard stored < planVersion else { return }
        guard stored >= 1 else { return } // stored == 0 lo maneja seedIfNeeded

        if let existentes = try? context.fetch(FetchDescriptor<WorkoutDay>()) {
            let cal = PlanConstants.calendar
            let fechasExistentes = Set(existentes.map { cal.startOfDay(for: $0.date) })

            var inserto = false
            for day in allWorkoutDays() where !fechasExistentes.contains(cal.startOfDay(for: day.date)) {
                context.insert(day)
                inserto = true
            }
            if inserto { try? context.save() }
        }

        markSeeded(planVersion)
    }

    // MARK: - Deduplicación de días (limpieza de copias por doble sembrado)

    /// Elimina días **duplicados por fecha**. Aparecen cuando dos dispositivos
    /// (p. ej. iPhone y reloj) siembran el plan antes de que CloudKit sincronice
    /// el flag "ya sembrado", quedando dos registros por fecha. Conserva el más
    /// "rico" (completado / con datos cargados) y borra el resto. Idempotente: si
    /// no hay duplicados, no hace nada. **Pensado para correr en un solo
    /// dispositivo** (el iPhone); las eliminaciones se propagan por CloudKit.
    static func deduplicateDays(context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }
        let cal = PlanConstants.calendar
        let groups = Dictionary(grouping: all) { cal.startOfDay(for: $0.date) }

        var deleted = false
        for (_, días) in groups where días.count > 1 {
            // Gana el más rico; desempata por id estable (consistente en el device).
            let sorted = días.sorted { a, b in
                let ra = richness(a), rb = richness(b)
                if ra != rb { return ra > rb }
                return String(describing: a.persistentModelID) < String(describing: b.persistentModelID)
            }
            for loser in sorted.dropFirst() {
                context.delete(loser)
                deleted = true
            }
        }
        if deleted { try? context.save() }
    }

    /// Puntaje de "riqueza" de un día para elegir cuál conservar al deduplicar.
    private static func richness(_ day: WorkoutDay) -> Int {
        var score = 0
        if day.isCompleted { score += 1000 }
        if day.actualKm != nil { score += 200 }
        if day.durationMinutes != nil { score += 50 }
        if day.avgHeartRate != nil { score += 20 }
        if let notes = day.notes, !notes.isEmpty { score += 10 }
        score += day.orderedExercises.reduce(0) { acc, exercise in
            acc + exercise.orderedSets.filter { $0.reps != nil || $0.weight != nil }.count
        }
        return score
    }

    // MARK: - Limpieza de la etapa de recuperación de rodilla (24/6 → 5/7/2026)

    private static let kneeCleanupKey = "cleanedKneeRecoveryV1"

    private static var kneeCleanupApplied: Bool {
        AppData.seedFlags.bool(forKey: kneeCleanupKey)
    }

    private static func markKneeCleanupApplied() {
        AppData.seedFlags.setBool(true, forKey: kneeCleanupKey)
    }

    /// Fechas que ocupó la etapa de recuperación de rodilla.
    private static let kneeRecoveryDates: [(month: Int, day: Int)] = [
        (6, 24), (6, 25), (6, 26), (6, 27), (6, 28), (6, 29), (6, 30),
        (7, 1), (7, 2), (7, 3), (7, 4), (7, 5),
    ]

    /// Borra los días de la etapa de recuperación de rodilla que quedaron **vacíos**:
    /// sin completar, sin métricas de corrida y sin series cargadas. Los días donde
    /// sí hubo entrenamiento —incluida la carrera del 5/7— se conservan como
    /// historial. Reutiliza el puntaje `richness` de la deduplicación: 0 significa
    /// que no hay ningún dato del usuario en ese día.
    ///
    /// Corre una sola vez y **solo en el iPhone**: los borrados se propagan por
    /// CloudKit al reloj y a la Mac.
    static func cleanupKneeRecoveryIfNeeded(context: ModelContext) {
        guard !kneeCleanupApplied else { return }
        guard let all = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }

        let cal = PlanConstants.calendar
        let objetivo = Set(kneeRecoveryDates.map {
            cal.startOfDay(for: DateComponents.makeDate(year: 2026, month: $0.month, day: $0.day))
        })

        var borré = false
        for day in all where objetivo.contains(cal.startOfDay(for: day.date)) && richness(day) == 0 {
            context.delete(day)
            borré = true
        }
        if borré { try? context.save() }
        markKneeCleanupApplied()
    }
}
