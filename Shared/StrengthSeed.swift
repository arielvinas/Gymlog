//
//  StrengthSeed.swift
//  Maraton
//
//  Carga la rutina de fuerza (DÍA A / DÍA B) en los días de fuerza del plan.
//  Tomada del plan de Megatlón (entrenador Francisco Ambrosio). Cada ejercicio
//  lleva su foto (asset `r1_NN` / `r2_NN`); el peso lo registra el usuario.
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
        /// Asset con la foto del ejercicio (ej. "r1_07"), o nil si no tiene.
        let imageName: String?
        /// Si el ejercicio se carga con peso. Los de peso corporal, banda, core,
        /// equilibrio o salto no llevan peso (no se muestra el campo).
        let weighted: Bool

        init(name: String, sets: Int, reps: String, note: String?, rest: Int, imageName: String? = nil, weighted: Bool = true) {
            self.name = name
            self.sets = sets
            self.reps = reps
            self.note = note
            self.rest = rest
            self.imageName = imageName
            self.weighted = weighted
        }
    }

    /// Nombres de los ejercicios de la rutina que NO llevan peso.
    static let bodyweightExerciseNames: Set<String> =
        Set((dayA + dayB).filter { !$0.weighted }.map(\.name))

    /// Indica si un ejercicio lleva peso. Los nombres desconocidos (ejercicios
    /// cargados a mano por el usuario) se asumen con peso.
    static func tracksWeight(exerciseName: String) -> Bool {
        !bodyweightExerciseNames.contains(exerciseName)
    }

    // MARK: - DÍA A · Acondicionamiento + específico + fuerza (día 1 del PDF)

    /// Arranca con dos circuitos de 3 vueltas (acondicionamiento y específico,
    /// sin pausa entre ejercicios) y sigue con el bloque principal de fuerza.
    /// El orden de la lista define el orden en la sesión.
    static let dayA: [ExerciseTemplate] = [
        // Acondicionamiento · circuito (3 vueltas)
        ExerciseTemplate(name: "Abdominales bisagra a dos piernas", sets: 3, reps: "12",
                         note: "Acondicionamiento · circuito (3 vueltas), sin pausa entre ejercicios", rest: 30, imageName: "r1_01", weighted: false),
        ExerciseTemplate(name: "Bicho muerto (dead bug)", sets: 3, reps: "10",
                         note: "Acondicionamiento · circuito (3 vueltas)", rest: 30, imageName: "r1_02", weighted: false),
        ExerciseTemplate(name: "Nados", sets: 3, reps: "12",
                         note: "Acondicionamiento · circuito · agarrando disco o banda", rest: 30, imageName: "r1_03", weighted: false),
        // Específico · circuito (3 vueltas)
        ExerciseTemplate(name: "Desplazamiento lateral con banda", sets: 3, reps: "16",
                         note: "Específico · circuito (3 vueltas)", rest: 30, imageName: "r1_04", weighted: false),
        ExerciseTemplate(name: "Estocada + flexión de cadera", sets: 3, reps: "16",
                         note: "Específico · circuito (3 vueltas)", rest: 30, imageName: "r1_05", weighted: false),
        ExerciseTemplate(name: "Salto de paracaidista", sets: 2, reps: "10",
                         note: "Específico · circuito · apoyar la punta del pie al caer", rest: 30, imageName: "r1_06", weighted: false),
        // Bloque principal de fuerza
        ExerciseTemplate(name: "Tirón dorsal en polea con agarre neutro", sets: 4, reps: "8",
                         note: "Pesado", rest: 90, imageName: "r1_07"),
        ExerciseTemplate(name: "Buenos días con barra", sets: 4, reps: "12", note: nil, rest: 75, imageName: "r1_08"),
        ExerciseTemplate(name: "Empuje de piernas (prensa)", sets: 3, reps: "10",
                         note: "A 1 pierna", rest: 90, imageName: "r1_09"),
        ExerciseTemplate(name: "Bíceps + press Arnold", sets: 4, reps: "12",
                         note: "Desde posición de rodillas", rest: 60, imageName: "r1_10"),
        ExerciseTemplate(name: "Sentadilla con mancuernas", sets: 3, reps: "6-8",
                         note: "Moderado, sin fallo", rest: 120, imageName: "r1_11"),
        ExerciseTemplate(name: "Bíceps con polea", sets: 3, reps: "10",
                         note: "10+10 en drop set", rest: 45, imageName: "r1_12"),
        ExerciseTemplate(name: "Fondos de tríceps en banco", sets: 3, reps: "12", note: nil, rest: 60, imageName: "r1_13", weighted: false),
    ]

    // MARK: - DÍA B · Acondicionamiento + específico + fuerza (día 2 del PDF)

    /// Mismo esquema que el día A: dos circuitos de 3 vueltas y después el bloque
    /// principal. El orden de la lista define el orden en la sesión.
    static let dayB: [ExerciseTemplate] = [
        // Acondicionamiento · circuito (3 vueltas)
        ExerciseTemplate(name: "Abdominal cruzado", sets: 3, reps: "10",
                         note: "Acondicionamiento · circuito (3 vueltas), sin pausa entre ejercicios", rest: 30, imageName: "r2_01", weighted: false),
        ExerciseTemplate(name: "Abdominales bicicleta", sets: 3, reps: "20",
                         note: "Acondicionamiento · circuito (3 vueltas)", rest: 30, imageName: "r2_02", weighted: false),
        ExerciseTemplate(name: "Puente lateral", sets: 3, reps: "30 s",
                         note: "Acondicionamiento · circuito · mantener la posición", rest: 30, imageName: "r2_03", weighted: false),
        // Específico · circuito (3 vueltas)
        ExerciseTemplate(name: "Equilibrio a un pie sobre bosu", sets: 3, reps: "20 s",
                         note: "Específico · circuito (3 vueltas)", rest: 30, imageName: "r2_04", weighted: false),
        ExerciseTemplate(name: "Salto sobre step a una pierna", sets: 2, reps: "6",
                         note: "Específico · circuito (3 vueltas)", rest: 30, imageName: "r2_05", weighted: false),
        ExerciseTemplate(name: "Peso muerto a una pierna con pesa rusa", sets: 3, reps: "10",
                         note: "Específico · circuito (3 vueltas)", rest: 30, imageName: "r2_06"),
        // Bloque principal de fuerza
        ExerciseTemplate(name: "Empuje de hombros con barra (parado)", sets: 4, reps: "6", note: nil, rest: 90, imageName: "r2_07"),
        ExerciseTemplate(name: "Apertura de pecho con mancuernas en banco inclinado", sets: 4, reps: "12", note: nil, rest: 60, imageName: "r2_08"),
        ExerciseTemplate(name: "Aductores en máquina", sets: 4, reps: "12", note: nil, rest: 60, imageName: "r2_09"),
        ExerciseTemplate(name: "Apertura de pecho en máquina", sets: 3, reps: "15", note: nil, rest: 45, imageName: "r2_10"),
        ExerciseTemplate(name: "Extensión de rodillas en máquina", sets: 4, reps: "12",
                         note: "Unilateral · 2\" de pausa arriba", rest: 60, imageName: "r2_11"),
        ExerciseTemplate(name: "Remo con mancuerna a un brazo", sets: 3, reps: "12", note: nil, rest: 60, imageName: "r2_12"),
        ExerciseTemplate(name: "Flexión de rodillas acostado", sets: 3, reps: "5",
                         note: "Unilateral", rest: 60, imageName: "r2_13"),
        ExerciseTemplate(name: "Bíceps con barra toma supina", sets: 3, reps: "10",
                         note: "Micro pausa entre series", rest: 30, imageName: "r2_14"),
        ExerciseTemplate(name: "Tríceps con polea 2", sets: 3, reps: "12", note: nil, rest: 45, imageName: "r2_15"),
    ]

    /// Devuelve la rutina que corresponde a un día de fuerza según su título.
    /// "Fuerza liviana" (taper) usa el DÍA B reducido a la mitad y sin pierna.
    /// En las semanas de pico (15-21/6) y taper (29/6-5/7) se omiten los
    /// ejercicios de salto (paracaidista / step a una pierna).
    static func templates(for day: WorkoutDay) -> [ExerciseTemplate] {
        let title = day.title.lowercased()
        let base: [ExerciseTemplate]
        if title.contains("liviana") { base = taperVariant(of: dayB) }
        else if title.contains("b") { base = dayB }
        else { base = dayA }

        guard omitsJumps(on: day.date) else { return base }
        return base.filter { !$0.name.localizedCaseInsensitiveContains("salto") }
    }

    /// Indica si un día cae en una semana sin saltos (pico de volumen o taper).
    private static func omitsJumps(on date: Date) -> Bool {
        let cal = PlanConstants.calendar
        let d = cal.startOfDay(for: date)
        let picoIni  = cal.startOfDay(for: DateComponents.makeDate(year: 2026, month: 6, day: 15))
        let picoFin  = cal.startOfDay(for: DateComponents.makeDate(year: 2026, month: 6, day: 21))
        let taperIni = cal.startOfDay(for: DateComponents.makeDate(year: 2026, month: 6, day: 29))
        let taperFin = cal.startOfDay(for: DateComponents.makeDate(year: 2026, month: 7, day: 5))
        return (d >= picoIni && d <= picoFin) || (d >= taperIni && d <= taperFin)
    }

    /// Versión de taper: 1-2 series por ejercicio, sin el trabajo de pierna.
    private static func taperVariant(of templates: [ExerciseTemplate]) -> [ExerciseTemplate] {
        templates
            .filter { !$0.name.localizedCaseInsensitiveContains("Flexión de rodillas") }
            .map { t in
                let reducedSets = t.sets == 0 ? 0 : max(1, (t.sets + 1) / 2)
                let note = t.sets == 0 ? t.note : "Taper · mitad de series, carga cómoda"
                return ExerciseTemplate(name: t.name, sets: reducedSets, reps: t.reps, note: note, rest: t.rest, imageName: t.imageName)
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
    /// v5: rutinas nuevas del plan de Megatlón (con fotos por ejercicio). Sólo
    /// se aplican a los días de fuerza del 9/6/2026 en adelante; los anteriores
    /// conservan lo que ya tenían.
    /// v6: corrige los días ≥ 9/6 que en v5 quedaron sin actualizar por tener
    /// datos sueltos cargados (de la rutina vieja). Ahora esos días también se
    /// reemplazan por la rutina nueva, sean cuales sean sus datos previos.
    /// v7: ajustes de carga (saltos reducidos, sentadilla moderada sin fallo) y
    /// regla de saltos en pico/taper. Refresca por completo los días de fuerza
    /// del nuevo plan que aún no tengan nada registrado.
    static let version = 7
    private static let versionKey = "seededStrengthVersion"

    /// Fecha desde la cual rige la rutina nueva del PDF. Los días de fuerza
    /// anteriores no se tocan.
    private static let newPlanCutoff = DateComponents.makeDate(year: 2026, month: 6, day: 9)

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

        let cal = PlanConstants.calendar
        let cutoff = cal.startOfDay(for: newPlanCutoff)

        for day in days where day.type == .fuerza {
            let routine = templates(for: day)
            // La rutina nueva (con fotos) sólo rige del 9/6 en adelante.
            let isNewPlanDay = cal.startOfDay(for: day.date) >= cutoff

            if day.exercises.isEmpty {
                // Sólo sembramos la rutina nueva en los días del nuevo plan; los
                // días vacíos anteriores se dejan como están.
                if isNewPlanDay { insert(routine, into: day, context: context) }
                continue
            }

            let hasLogged = day.exercises.contains { $0.hasLoggedData }

            if isNewPlanDay && !hasLogged {
                // Día del nuevo plan todavía sin nada registrado: se reemplaza por
                // completo (la eliminación arrastra sus series) y se refresca la
                // descripción. Así toman los ajustes de carga (saltos reducidos,
                // sentadilla moderada) y la regla de saltos de pico/taper.
                for exercise in day.exercises { context.delete(exercise) }
                insert(routine, into: day, context: context)
                day.longDescription = WorkoutSeed.longDescription(for: .fuerza, title: day.title)
            } else {
                // Resto (días con datos cargados o anteriores al 9/6): completa
                // sólo los campos faltantes sin pisar lo que el usuario editó ni
                // la rutina vieja.
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
                    if exercise.imageName == nil {
                        exercise.imageName = template.imageName
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
                imageName: template.imageName,
                day: day
            )
            context.insert(exercise)
            for s in 0..<template.sets {
                context.insert(ExerciseSet(order: s + 1, exercise: exercise))
            }
        }
    }
}
