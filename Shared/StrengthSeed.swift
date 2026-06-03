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

    // MARK: - DÍA B · Tirón + core (viernes)

    static let dayB: [ExerciseTemplate] = [
        ExerciseTemplate(name: "Remo con barra en landmine (o remo colgado en barra)", sets: 3, reps: "8-10", note: nil, rest: 120),
        ExerciseTemplate(name: "Tirón dorsal en polea con agarre supino", sets: 3, reps: "8-10", note: nil, rest: 90),
        ExerciseTemplate(name: "Remo en polea baja con toma neutra abierta", sets: 2, reps: "12", note: nil, rest: 60),
        ExerciseTemplate(name: "Bíceps con barra toma supina", sets: 3, reps: "8-10", note: nil, rest: 75),
        ExerciseTemplate(name: "Bíceps martillo", sets: 2, reps: "10-12", note: nil, rest: 60),
        ExerciseTemplate(name: "Vuelos posteriores con mancuernas", sets: 2, reps: "12-15",
                         note: "Postura + hombro sano", rest: 45),
        ExerciseTemplate(name: "Flexión de rodillas acostado (camilla)", sets: 2, reps: "12-15",
                         note: "Isquios livianos · previene lesión al correr", rest: 60),
        ExerciseTemplate(name: "Core", sets: 0, reps: "",
                         note: "Twist ruso 3×20 · Puente lateral con rotación 3×10 por lado", rest: 45),
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
    static let version = 3
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
    /// completa; en los ya sembrados por una versión previa completa las reps
    /// objetivo. Respeta lo que el usuario editó (solo toca ejercicios cuyo
    /// nombre coincide con la plantilla y que aún no tienen reps objetivo) y
    /// corre una sola vez por versión.
    static func populateIfNeeded(context: ModelContext) {
        guard storedVersion < version else { return }
        guard let days = try? context.fetch(FetchDescriptor<WorkoutDay>()) else { return }

        for day in days where day.type == .fuerza {
            let routine = templates(for: day)

            if day.exercises.isEmpty {
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
}
