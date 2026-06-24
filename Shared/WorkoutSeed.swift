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
        let local = UserDefaults.standard.integer(forKey: versionKey)
        guard AppData.iCloudSyncEnabled else { return local }
        let cloud = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: versionKey))
        return max(cloud, local)
    }

    private static func markSeeded(_ version: Int) {
        UserDefaults.standard.set(version, forKey: versionKey)
        if AppData.iCloudSyncEnabled {
            NSUbiquitousKeyValueStore.default.set(Int64(version), forKey: versionKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
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

    // MARK: - Ajuste puntual semana 1 (jueves gimnasio / viernes calidad)

    private static let thursdaySwapKey = "appliedThursdayGymSwapV1"

    private static var thursdaySwapApplied: Bool {
        let local = UserDefaults.standard.bool(forKey: thursdaySwapKey)
        guard AppData.iCloudSyncEnabled else { return local }
        return local || NSUbiquitousKeyValueStore.default.bool(forKey: thursdaySwapKey)
    }

    private static func markThursdaySwapApplied() {
        UserDefaults.standard.set(true, forKey: thursdaySwapKey)
        if AppData.iCloudSyncEnabled {
            NSUbiquitousKeyValueStore.default.set(true, forKey: thursdaySwapKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Intercambia el jueves 4/6 y el viernes 5/6 en instalaciones ya sembradas:
    /// el jueves pasa a ser el día de fuerza (gimnasio, nueva rutina de Fuerza B)
    /// y la corrida de calidad se mueve al viernes. Los ejercicios del jueves los
    /// siembra después `StrengthSeed.populateIfNeeded`. Corre una sola vez y sólo
    /// si los días siguen como los dejó el plan original (no pisa ediciones).
    static func applyThursdayGymSwapIfNeeded(context: ModelContext) {
        guard !thursdaySwapApplied else { return }

        let cal = PlanConstants.calendar
        let jueves = DateComponents.makeDate(year: 2026, month: 6, day: 4)
        let viernes = DateComponents.makeDate(year: 2026, month: 6, day: 5)

        guard let days = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }

        // Jueves: de corrida de calidad a día de fuerza (gimnasio).
        if let thu = days.first(where: { cal.isDate($0.date, inSameDayAs: jueves) }), thu.type == .calidad {
            thu.type = .fuerza
            thu.title = "Fuerza B"
            thu.detail = "Espalda + tríceps + core"
            thu.longDescription = longDescription(for: .fuerza, title: thu.title)
            thu.isCompleted = false
            // Limpia campos de corrida que ya no aplican.
            thu.actualKm = nil
            thu.durationMinutes = nil
            thu.perceivedEffort = nil
            thu.avgHeartRate = nil
            thu.activeCalories = nil
        }

        // Viernes: de día de fuerza a corrida de calidad. Si no hay nada
        // registrado en el gimnasio, se quitan los ejercicios sobrantes.
        if let fri = days.first(where: { cal.isDate($0.date, inSameDayAs: viernes) }), fri.type == .fuerza {
            if !fri.orderedExercises.contains(where: { $0.hasLoggedData }) {
                for exercise in fri.orderedExercises { context.delete(exercise) }
            }
            fri.type = .calidad
            fri.title = "Calidad · 2×10' tempo"
            fri.detail = "(7/10), 3' trote"
            fri.longDescription = longDescription(for: .calidad, title: fri.title)
            fri.isCompleted = false
        }

        try? context.save()
        markThursdaySwapApplied()
    }

    // MARK: - Estructura nueva del 8/6 en adelante

    private static let newStructureKey = "appliedNewStructureV1"

    /// Primer día que toca la actualización de estructura. Todo lo igual o
    /// anterior al 7/6 queda intacto.
    private static let newStructureCutoff = DateComponents.makeDate(year: 2026, month: 6, day: 8)

    private static var newStructureApplied: Bool {
        let local = UserDefaults.standard.bool(forKey: newStructureKey)
        guard AppData.iCloudSyncEnabled else { return local }
        return local || NSUbiquitousKeyValueStore.default.bool(forKey: newStructureKey)
    }

    private static func markNewStructureApplied() {
        UserDefaults.standard.set(true, forKey: newStructureKey)
        if AppData.iCloudSyncEnabled {
            NSUbiquitousKeyValueStore.default.set(true, forKey: newStructureKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Pone los días del 8/6 en adelante al día con la estructura canónica nueva
    /// (calidades con su prescripción, notas de fondo, semana de pico/taper). No
    /// toca ninguna fecha igual o anterior al 7/6. Corre una sola vez. Como esos
    /// días son futuros, reescribe los campos descriptivos; preserva el progreso
    /// (`isCompleted`, métricas y ejercicios) y no cambia el tipo de ningún día.
    static func applyNewStructureIfNeeded(context: ModelContext) {
        guard !newStructureApplied else { return }

        let cal = PlanConstants.calendar
        let cutoff = cal.startOfDay(for: newStructureCutoff)

        guard let existentes = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }
        let porFecha = Dictionary(existentes.map { (cal.startOfDay(for: $0.date), $0) },
                                  uniquingKeysWith: { a, _ in a })

        for canonical in allWorkoutDays() where cal.startOfDay(for: canonical.date) >= cutoff {
            let key = cal.startOfDay(for: canonical.date)
            if let dia = porFecha[key] {
                dia.title = canonical.title
                dia.detail = canonical.detail
                dia.longDescription = canonical.longDescription
                dia.type = canonical.type
                dia.weekTitle = canonical.weekTitle
                dia.weekTag = canonical.weekTag
                dia.weekOrder = canonical.weekOrder
            } else {
                context.insert(canonical)
            }
        }

        try? context.save()
        markNewStructureApplied()
    }

    // MARK: - Etapa de recuperación de rodilla (24/6 → 5/7/2026)

    private static let kneeRecoveryKey = "appliedKneeRecoveryV1"

    private static var kneeRecoveryApplied: Bool {
        let local = UserDefaults.standard.bool(forKey: kneeRecoveryKey)
        guard AppData.iCloudSyncEnabled else { return local }
        return local || NSUbiquitousKeyValueStore.default.bool(forKey: kneeRecoveryKey)
    }

    private static func markKneeRecoveryApplied() {
        UserDefaults.standard.set(true, forKey: kneeRecoveryKey)
        if AppData.iCloudSyncEnabled {
            NSUbiquitousKeyValueStore.default.set(true, forKey: kneeRecoveryKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Spec de un día de la etapa de recuperación de rodilla.
    private struct KneeDay {
        let month: Int
        let day: Int
        let type: WorkoutType
        let title: String
        let detail: String
    }

    /// Plan del 24/6 al 5/7/2026: prioriza descanso sin impacto y un trote de
    /// prueba antes de decidir la carrera. Sin fondos, sin pierna pesada ni saltos.
    private static let kneeRecoveryDays: [KneeDay] = [
        KneeDay(month: 6, day: 24, type: .descanso, title: "Descanso de rodilla + movilidad",
                detail: "Movilidad, elongación de gemelo/sóleo y protocolo de Alfredson. Caminar normal sí; no correr ni testear la rodilla a propósito."),
        KneeDay(month: 6, day: 25, type: .fuerza, title: "Fuerza · Día 2 (tren superior + core)",
                detail: "Sin pierna pesada ni saltos. Sumar Alfredson."),
        KneeDay(month: 6, day: 26, type: .descanso, title: "Descanso / movilidad",
                detail: "Movilidad y Alfredson."),
        KneeDay(month: 6, day: 27, type: .descanso, title: "Descanso",
                detail: "Que la rodilla llegue fresca al trote de prueba. Movilidad ligera opcional."),
        KneeDay(month: 6, day: 28, type: .calidad, title: "Trote de PRUEBA (decisión rodilla)",
                detail: "15-20 min muy suave (Zona 2), en llano. Llevar el donut en el dedo. Es el test que define si la rodilla está para la carrera: si no duele corriendo ni al día siguiente, buena señal; si duele, cambia la pisada o aparece al otro día, no correr."),
        KneeDay(month: 6, day: 29, type: .descanso, title: "Descanso (evaluar rodilla)",
                detail: "Clave: cómo respondió la rodilla al trote de ayer. Sin dolor = seguimos. Con dolor = replantear la carrera."),
        KneeDay(month: 6, day: 30, type: .fuerza, title: "Fuerza liviana (tren superior)",
                detail: "Mitad de series, sin pierna ni saltos. Solo si la rodilla viene bien."),
        KneeDay(month: 7, day: 1, type: .rodaje, title: "Trote suave 4-5 km (condicional)",
                detail: "Solo si el trote del domingo salió sin dolor. Muy suave, Zona 2. Si la rodilla protesta, descanso."),
        KneeDay(month: 7, day: 2, type: .calidad, title: "Trote suave 15 min + unos pocos cambios de ritmo (condicional)",
                detail: "Solo si todo viene sin dolor. Nada exigente. Última activación antes de la carrera."),
        KneeDay(month: 7, day: 3, type: .descanso, title: "Descanso",
                detail: "Movilidad ligera."),
        KneeDay(month: 7, day: 4, type: .descanso, title: "Descanso total (víspera)",
                detail: "Hidratar, cargar hidratos, preparar todo: donut, vendaje, ropa."),
        KneeDay(month: 7, day: 5, type: .carrera, title: "Media Maratón Córdoba 21,1 km",
                detail: "Correr SOLO si la rodilla respondió bien a las pruebas. Si hay dolor que cambia la pisada, parar. La salud vale más que terminar."),
    ]

    /// Reescribe los días del 24/6 al 5/7/2026 con el plan de recuperación de
    /// rodilla, **sin tocar fechas anteriores al 24/6**. Reemplaza tipo, título,
    /// detalle, descripción y ejercicios (fuerza → rutina sin pierna/salto; el
    /// resto sin gimnasio) y limpia el registro previo (son días futuros). Corre
    /// una sola vez y **solo en el iPhone** (las altas/bajas de ejercicios no son
    /// idempotentes entre dispositivos; las eliminaciones se propagan por CloudKit).
    static func applyKneeRecoveryIfNeeded(context: ModelContext) {
        guard !kneeRecoveryApplied else { return }
        guard let allDays = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }

        let cal = PlanConstants.calendar
        let byDate = Dictionary(grouping: allDays) { cal.startOfDay(for: $0.date) }

        for spec in kneeRecoveryDays {
            let date = cal.startOfDay(for: DateComponents.makeDate(year: 2026, month: spec.month, day: spec.day))
            guard let días = byDate[date] else { continue }
            for day in días {
                day.type = spec.type
                day.title = spec.title
                day.detail = spec.detail
                day.longDescription = spec.detail
                // Son días futuros y el contenido cambió: se limpia el registro.
                day.isCompleted = false
                day.actualKm = nil
                day.durationMinutes = nil
                day.perceivedEffort = nil
                day.notes = nil
                day.avgHeartRate = nil
                day.activeCalories = nil

                if spec.type == .fuerza {
                    let light = spec.title.localizedCaseInsensitiveContains("liviana")
                    StrengthSeed.applyKneeRecoveryRoutine(to: day, light: light, context: context)
                } else {
                    for exercise in day.orderedExercises { context.delete(exercise) }
                }
            }
        }

        try? context.save()
        markKneeRecoveryApplied()
    }
}
