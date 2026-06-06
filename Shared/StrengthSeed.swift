//
//  StrengthSeed.swift
//  Maraton
//
//  Carga la rutina de fuerza (DÍA A / DÍA B) en los días de fuerza del plan.
//  Tomada del plan "Fuerza · Media Maratón". Los rangos de repeticiones van en
//  las notas; el peso lo registra el usuario en cada sesión.
//

import Foundation
import SwiftData

enum StrengthSeed {

    /// Plantilla de un ejercicio: nombre, cantidad de series, rango de reps
    /// objetivo, una nota/etiqueta opcional y el descanso recomendado entre
    /// series (segundos). `sets == 0` indica un ejercicio sin carga (core),
    /// cuyo detalle vive en `note`.
    struct ExerciseTemplate {
        let name: String
        let sets: Int
        let reps: String
        let note: String?
        let rest: Int
    }

    // MARK: - DÍA A · Empuje + pierna + core (martes)

    static let dayA: [ExerciseTemplate] = [
        ExerciseTemplate(name: "Empuje de pecho con barra en banco plano", sets: 3, reps: "6-8",
                         note: "El fuerte del día · carga exigente", rest: 120),
        ExerciseTemplate(name: "Empuje de hombros en Hammer", sets: 3, reps: "8-10", note: nil, rest: 90),
        ExerciseTemplate(name: "Apertura de pecho con mancuernas en banco inclinado", sets: 2, reps: "12-15",
                         note: "Accesorio · moderado", rest: 60),
        ExerciseTemplate(name: "Vuelos laterales con mancuernas", sets: 3, reps: "12-15", note: nil, rest: 45),
        ExerciseTemplate(name: "Tríceps en polea (agarre prono) o press francés", sets: 3, reps: "10-12", note: nil, rest: 60),
        ExerciseTemplate(name: "Sentadilla copa", sets: 3, reps: "8-10",
                         note: "Mantenimiento · sin fallo · cuidá las piernas", rest: 90),
        ExerciseTemplate(name: "Hip thrust con barra", sets: 3, reps: "10-12",
                         note: "Glúteo · te protege como corredor", rest: 90),
        ExerciseTemplate(name: "Core", sets: 0, reps: "",
                         note: "Bicho muerto 3×10 por lado · Plancha prona alta 3×30 s", rest: 45),
    ]

    // MARK: - DÍA B · Espalda + tríceps + core

    /// Primero el bloque de Zona media (en circuito: 3 vueltas seguidas, sin
    /// pausa entre ejercicios, ~30-45 s al terminar cada vuelta) y después el
    /// bloque Principal. El orden de la lista define el orden en la sesión.
    static let dayB: [ExerciseTemplate] = [
        // Zona media · circuito (3 vueltas)
        ExerciseTemplate(name: "Abdominales inferiores + vela en banco", sets: 3, reps: "10",
                         note: "Zona media · circuito (3 vueltas), sin pausa entre ejercicios; ~30-45 s al terminar la vuelta", rest: 30),
        ExerciseTemplate(name: "Cobras sobre fitball", sets: 3, reps: "10",
                         note: "Zona media · circuito · con mancuernas", rest: 30),
        ExerciseTemplate(name: "Puente prono dinámico", sets: 3, reps: "10",
                         note: "Zona media · circuito · subir-bajar manos a step o rueda abdominal", rest: 30),
        // Principal
        ExerciseTemplate(name: "Remo colgado en barra agarre prono", sets: 4, reps: "12-12-12-12",
                         note: "Aumentar reps cada semana", rest: 75),
        ExerciseTemplate(name: "Tirón dorsal en polea con agarre supino", sets: 4, reps: "12-10-8-8", note: nil, rest: 90),
        ExerciseTemplate(name: "Remo con barra en landmine", sets: 4, reps: "15-12-10-10", note: nil, rest: 90),
        ExerciseTemplate(name: "Pull over con mancuerna", sets: 3, reps: "10-10-10",
                         note: "Combinar con remo con banda", rest: 60),
        ExerciseTemplate(name: "Remo con banda", sets: 3, reps: "20-20-20", note: nil, rest: 45),
        ExerciseTemplate(name: "Tríceps copa", sets: 4, reps: "12-12-10-10", note: nil, rest: 75),
        ExerciseTemplate(name: "Empuje de pecho con barra en banco plano (toma cerrada)", sets: 3, reps: "10-10-10", note: nil, rest: 90),
        ExerciseTemplate(name: "Fondos de tríceps en banco", sets: 3, reps: "al fallo", note: nil, rest: 60),
    ]

    /// Devuelve la rutina que corresponde a un día de fuerza según su título.
    /// "Fuerza liviana" (taper) usa el DÍA B reducido a la mitad y sin pierna.
    static func templates(for day: WorkoutDay) -> [ExerciseTemplate] {
        let title = day.title.lowercased()
        if title.contains("liviana") { return taperVariant(of: dayB) }
        if title.contains("b") { return dayB }
        return dayA
    }

    /// Versión de taper: 1-2 series por ejercicio, sin el trabajo de pierna.
    private static func taperVariant(of templates: [ExerciseTemplate]) -> [ExerciseTemplate] {
        templates
            .filter { !$0.name.localizedCaseInsensitiveContains("Flexión de rodillas") }
            .map { t in
                let reducedSets = t.sets == 0 ? 0 : max(1, (t.sets + 1) / 2)
                let note = t.sets == 0 ? t.note : "Taper · mitad de series, carga cómoda"
                return ExerciseTemplate(name: t.name, sets: reducedSets, reps: t.reps, note: note, rest: t.rest)
            }
    }

    /// Rango de reps objetivo del template (nil para core, que no lleva carga).
    private static func target(for t: ExerciseTemplate) -> String? {
        t.reps.isEmpty ? nil : t.reps
    }

    // MARK: - Sembrado

    /// v2: las reps objetivo pasan a su propio campo (`targetReps`).
    /// v3: se agrega el descanso recomendado por ejercicio (`restSeconds`),
    /// completándolo también en los ejercicios ya sembrados.
    /// v4: nueva rutina de Fuerza B (Espalda + tríceps + core). Se reemplaza la
    /// rutina de los días cuyo template cambió y que aún no tienen nada cargado.
    static let version = 4
    private static let versionKey = "seededStrengthVersion"

    private static var storedVersion: Int {
        let local = UserDefaults.standard.integer(forKey: versionKey)
        guard AppData.iCloudSyncEnabled else { return local }
        let cloud = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: versionKey))
        return max(cloud, local)
    }

    private static func markSeeded() {
        UserDefaults.standard.set(version, forKey: versionKey)
        if AppData.iCloudSyncEnabled {
            NSUbiquitousKeyValueStore.default.set(Int64(version), forKey: versionKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Carga la rutina en los días de fuerza. En los días vacíos crea la rutina
    /// completa; si el template del día cambió (p. ej. la nueva Fuerza B) y el
    /// día todavía no tiene nada registrado, reemplaza los ejercicios por la
    /// rutina actual; en el resto sólo completa los campos que falten (reps
    /// objetivo y descanso) respetando lo que el usuario editó o registró.
    /// Corre una sola vez por versión.
    static func populateIfNeeded(context: ModelContext) {
        guard storedVersion < version else { return }
        guard let days = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }

        for day in days where day.type == .fuerza {
            let routine = templates(for: day)

            if day.exercises.isEmpty {
                insert(routine, into: day, context: context)
                continue
            }

            let routineNames = routine.map(\.name)
            let currentNames = day.orderedExercises.map(\.name)
            let dayHasLoggedData = day.exercises.contains { $0.hasLoggedData }

            if currentNames != routineNames && !dayHasLoggedData {
                // El template del día cambió y no hay nada cargado: se reemplaza
                // por la rutina actual (la eliminación arrastra sus series).
                for exercise in day.exercises { context.delete(exercise) }
                insert(routine, into: day, context: context)
            } else {
                // Migración de ejercicios ya sembrados: completa reps objetivo
                // (v2) y descanso recomendado (v3) sin pisar lo que el usuario
                // haya editado (solo rellena los campos que falten).
                let byName = Dictionary(uniqueKeysWithValues: routine.map { ($0.name, $0) })
                for exercise in day.exercises {
                    guard let template = byName[exercise.name] else { continue }
                    if exercise.targetReps == nil {
                        exercise.targetReps = target(for: template)
                        exercise.notes = template.note
                    }
                    if exercise.restSeconds == nil {
                        exercise.restSeconds = template.rest
                    }
                }
            }
        }

        try? context.save()
        markSeeded()
    }

    /// Crea los ejercicios de una rutina (con sus series vacías) dentro de un día.
    private static func insert(_ routine: [ExerciseTemplate], into day: WorkoutDay, context: ModelContext) {
        for (index, template) in routine.enumerated() {
            let exercise = Exercise(
                name: template.name,
                order: index,
                dayDate: day.date,
                notes: template.note,
                targetReps: target(for: template),
                restSeconds: template.rest,
                day: day
            )
            context.insert(exercise)
            for s in 0..<template.sets {
                context.insert(ExerciseSet(order: s + 1, exercise: exercise))
            }
        }
    }
}
