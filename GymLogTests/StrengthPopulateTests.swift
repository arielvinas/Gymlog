//
//  StrengthPopulateTests.swift
//  GymLogTests
//
//  `StrengthSeed.populateIfNeeded`: el que carga la rutina de gimnasio en los días de fuerza.
//  Corre una vez por versión, sobre días que el usuario **ya puede haber tocado**. Tiene tres
//  caminos y hay que saber cuál toma, porque uno de ellos **borra los ejercicios y los rehace**.
//
//  Backlog: TESTING.md · I-29, I-30, I-31
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Sembrado de la rutina de fuerza", .serialized)
struct StrengthPopulateTests {

    @MainActor
    private func conFlags(_ store: InMemorySeedFlagStore, _ body: () throws -> Void) rethrows {
        let previo = AppData.seedFlags
        AppData.seedFlags = store
        defer { AppData.seedFlags = previo }
        try body()
    }

    /// Un store donde la rutina todavía no se sembró.
    private func sinSembrar() -> InMemorySeedFlagStore { InMemorySeedFlagStore() }

    // MARK: - I-29 · A quién llena y a quién no

    @Test("I-29 · Llena los días de fuerza vacíos del nuevo plan (9/6 en adelante)")
    func itFillsEmptyStrengthDaysOfTheNewPlan() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            try db.context.save()

            #expect(dia.orderedExercises.isEmpty)

            StrengthSeed.populateIfNeeded(context: db.context)

            let esperados = StrengthSeed.templates(for: dia).map(\.name)
            #expect(dia.orderedExercises.map(\.name) == esperados)
            // Y cada ejercicio viene con sus series vacías, listas para cargar.
            #expect(dia.orderedExercises.allSatisfy { !$0.orderedSets.isEmpty })
            #expect(dia.orderedExercises.allSatisfy { $0.targetReps != nil })
        }
    }

    @Test("I-29 · Un día de fuerza vacío anterior al 9/6 se deja como está")
    func emptyStrengthDaysBeforeTheCutoffAreLeftAlone() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            // El 8/6 es el día anterior al corte: la rutina nueva no rige.
            let viejo = makeDay(date(2026, 6, 8), type: .fuerza, title: "Fuerza A", in: db.context)
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            #expect(viejo.orderedExercises.isEmpty, "El plan viejo no se rellena con la rutina nueva")
        }
    }

    @Test("I-29 · Los días que no son de fuerza no se tocan")
    func nonStrengthDaysAreIgnored() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let fondo = makeDay(date(2026, 6, 16), type: .fondo, title: "Fondo 12 km", in: db.context)
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            #expect(fondo.orderedExercises.isEmpty)
        }
    }

    @Test("I-29 · Marca la versión y no vuelve a correr")
    func itMarksTheVersionAndDoesNotRunAgain() throws {
        let db = TestDB()
        let flags = sinSembrar()

        try conFlags(flags) {
            makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            #expect(flags.integer(forKey: "seededStrengthVersion") == StrengthSeed.version)
        }

        // Con la versión ya sembrada, un día vacío nuevo **no** se llena.
        try conFlags(InMemorySeedFlagStore(["seededStrengthVersion": StrengthSeed.version])) {
            let nuevo = makeDay(date(2026, 6, 23), type: .fuerza, title: "Fuerza A", in: db.context)
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            #expect(nuevo.orderedExercises.isEmpty, "Corre una vez por versión, no en cada arranque")
        }
    }

    @Test("I-29 · Un día del nuevo plan sin datos se reemplaza por la rutina actual")
    func anUntouchedNewPlanDayIsReplacedWholesale() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            // Una rutina vieja, sembrada por una versión anterior, sin nada cargado.
            makeExercise("Ejercicio viejo", on: dia, order: 0, sets: [(nil, nil)], in: db.context)
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // Se borra entera y se rehace: así el día toma los ajustes de carga de la versión
            // nueva. Es correcto **mientras no haya nada del usuario adentro**.
            #expect(!dia.orderedExercises.contains { $0.name == "Ejercicio viejo" })
            #expect(dia.orderedExercises.map(\.name) == StrengthSeed.templates(for: dia).map(\.name))
        }
    }

    // MARK: - I-31 · Bug 9

    /// ⚠️ **Bug 9 CONFIRMADO y alcanzable.** El camino "reemplazar por completo" se elige con
    /// `hasLoggedData`, que mira `reps` y `weight` **pero no `isDone`**.
    ///
    /// Si hiciste la sesión **tildando las series sin anotar los kilos**, el día parece intacto.
    /// Al subir `StrengthSeed.version`, `populateIfNeeded` borra los ejercicios y los rehace: **las
    /// tildes se van con ellos.** No es que se elija mal entre dos copias, como en el bug 7: acá
    /// simplemente se borra lo que hiciste.
    @Test("I-31 · ⚠️ Una sesión hecha solo tildando series se borra al subir la versión")
    func aSessionOfTickedSetsIsWipedOnAVersionBump() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            let ejercicio = makeExercise(
                "Sentadilla", on: dia, order: 0,
                sets: [(nil, nil), (nil, nil), (nil, nil)], in: db.context
            )
            // Hiciste las tres series y las tildaste. No anotaste los kilos.
            for set in ejercicio.orderedSets { set.isDone = true }
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // `hasLoggedData` no mira `isDone`, así que el día se consideró "sin nada registrado"
            // y se reemplazó entero.
            #expect(!dia.orderedExercises.contains { $0.name == "Sentadilla" })
            #expect(
                dia.orderedExercises.allSatisfy { ejercicio in
                    ejercicio.orderedSets.allSatisfy { !$0.isDone }
                },
                "Las series quedaron todas sin tildar: la sesión desapareció"
            )
        }
    }

    @Test("I-31 · Con un solo peso anotado, el mismo día se salva")
    func oneLoggedWeightIsEnoughToProtectTheDay() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            // La única diferencia con el test anterior: un peso.
            makeExercise("Sentadilla", on: dia, order: 0, sets: [(80, 8)], in: db.context)
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // Ahora sí `hasLoggedData` es true: se toma el camino conservador y el ejercicio queda.
            #expect(dia.orderedExercises.contains { $0.name == "Sentadilla" })
        }
    }

    // MARK: - I-30 · Bug 8

    /// ⚠️ **Bug 8 CONFIRMADO.** En el camino conservador, la asignación de `notes` está **adentro**
    /// del `if exercise.targetReps == nil`:
    ///
    /// ```swift
    /// if exercise.targetReps == nil {
    ///     exercise.targetReps = target(for: template)
    ///     exercise.notes = template.note        // ← pisa la nota del usuario
    /// }
    /// ```
    ///
    /// La intención era "completar los campos que falten". Pero `notes` **no se chequea**: si el
    /// ejercicio no tenía `targetReps` (el caso de la rutina vieja) y vos le escribiste una nota,
    /// la nota **se pisa** con la del template. El propio comentario de la función promete
    /// "respetando lo que el usuario editó".
    ///
    /// **Fix:** mover la asignación a su propio `if exercise.notes == nil`, como ya hacen
    /// `restSeconds` e `imageName`.
    @Test("I-30 · ⚠️ La nota que escribiste se pisa con la del plan")
    func theUserNoteIsOverwritten() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)

            // Un ejercicio de la rutina, con datos cargados (para tomar el camino conservador) y
            // sin `targetReps` —como quedan los de la rutina vieja—.
            let nombre = try #require(StrengthSeed.templates(for: dia).first?.name)
            let mío = makeExercise(nombre, on: dia, order: 0, sets: [(20, 12)], in: db.context)
            mío.targetReps = nil
            mío.notes = "Ojo con la rodilla: bajar despacio"
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // Completó el `targetReps` que faltaba: eso está bien…
            #expect(mío.targetReps != nil)
            // …pero de paso se llevó puesta la nota, que nadie le pidió tocar.
            #expect(
                mío.notes != "Ojo con la rodilla: bajar despacio",
                "La nota del usuario se pisó con la del template"
            )
        }
    }

    @Test("I-30 · Si el ejercicio ya tenía targetReps, la nota sobrevive")
    func theNoteSurvivesWhenTargetRepsIsAlreadySet() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            let nombre = try #require(StrengthSeed.templates(for: dia).first?.name)
            let mío = makeExercise(nombre, on: dia, order: 0, sets: [(20, 12)], in: db.context)
            mío.targetReps = "10"                       // ya está: el `if` no entra
            mío.notes = "Ojo con la rodilla"
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // Acá la nota se salva, pero **por accidente**: no porque el código la proteja, sino
            // porque el `if` que la pisa no llegó a entrar. La protección es una casualidad.
            #expect(mío.notes == "Ojo con la rodilla")
        }
    }

    @Test("I-30 · Los campos que faltan sí se completan, y los que están no se tocan")
    func missingFieldsAreFilledAndExistingOnesAreKept() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            let nombre = try #require(StrengthSeed.templates(for: dia).first?.name)
            let mío = makeExercise(nombre, on: dia, order: 0, sets: [(20, 12)], in: db.context)
            mío.restSeconds = 999                       // un descanso que elegiste vos
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // `restSeconds` sí chequea antes de escribir: tu valor manda.
            #expect(mío.restSeconds == 999)
            // Y lo que faltaba se completó.
            #expect(mío.targetReps != nil)
        }
    }

    @Test("I-30 · Un ejercicio que agregaste a mano no se toca")
    func aHandAddedExerciseIsLeftAlone() throws {
        let db = TestDB()

        try conFlags(sinSembrar()) {
            let dia = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: db.context)
            let mío = makeExercise("Curl martillo", on: dia, order: 0, sets: [(12, 10)], in: db.context)
            mío.notes = "Mi agregado"
            try db.context.save()

            StrengthSeed.populateIfNeeded(context: db.context)

            // El `guard let template = byName[exercise.name] else { continue }` lo salva: un
            // ejercicio que no está en la rutina se saltea entero.
            #expect(mío.notes == "Mi agregado")
            #expect(dia.orderedExercises.contains { $0.name == "Curl martillo" })
        }
    }
}
