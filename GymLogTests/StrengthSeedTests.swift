//
//  StrengthSeedTests.swift
//  GymLogTests
//
//  `StrengthSeed` decide **qué rutina le toca a cada día de fuerza**. Es una
//  función pura de (título, fecha) → lista de ejercicios, y de ella depende lo
//  que el usuario encuentra al abrir la sesión guiada.
//
//  Backlog: TESTING.md · U-18..U-21
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Rutinas de fuerza · selección")
struct StrengthSeedTests {

    /// Una fecha fuera de las semanas de pico y taper, para que el filtro de saltos no
    /// interfiera cuando lo que se está probando es la elección de rutina (ver U-20).
    private let fechaNormal = date(2026, 6, 10)

    /// Los nombres de la rutina que le toca a un día. Se compara por nombre porque
    /// `ExerciseTemplate` no es `Equatable` — y el nombre es lo que distingue una rutina de
    /// la otra, que es justo lo que estos tests miran.
    @MainActor
    private func nombres(_ day: WorkoutDay) -> [String] {
        StrengthSeed.templates(for: day).map(\.name)
    }

    // MARK: - U-18

    // ⚠️ **Bug 1.** La rutina se elige mirando el título:
    //
    //     if title.contains("liviana") { … } else if title.contains("b") { dayB } else { dayA }
    //
    // Ese `contains("b")` no busca "el día B": busca **la letra b, en cualquier lugar del
    // título**. Con los títulos que siembra el plan funciona de casualidad — ninguno de los
    // de Día A tiene una "b". Pero el título **lo edita el usuario** (`WorkoutEditView` lo
    // expone en un `TextField`), y ahí se cae.

    @Test("U-18 · Con los títulos del plan, la elección es la correcta")
    func thePlanTitlesPickTheRightRoutine() {
        let db = TestDB()

        let diaA = makeDay(fechaNormal, type: .fuerza, title: "Fuerza A", in: db.context)
        let diaB = makeDay(fechaNormal, type: .fuerza, title: "Fuerza B", in: db.context)

        // Esta es la razón por la que el bug no explotó nunca: "fuerza a" no tiene ninguna
        // "b" suelta. Es una coincidencia afortunada, no una garantía.
        #expect(nombres(diaA) == StrengthSeed.dayA.map(\.name))
        #expect(nombres(diaB) == StrengthSeed.dayB.map(\.name))
    }

    @Test(
        "U-18 · ⚠️ Cualquier 'b' en el título trae la rutina del Día B",
        arguments: [
            // Lo que un usuario escribiría al renombrar un día de Día A.
            "Fuerza A · brazos",
            "Fuerza A (banco plano)",
            "Gimnasio básico",
            "Fuerza A · bloque principal",
            // Y el caso más incómodo: el título ni siquiera menciona la letra como tal.
            "Hombros y abdominales",
        ]
    )
    func anyBInTheTitleBringsDayB(title: String) {
        let db = TestDB()
        let day = makeDay(fechaNormal, type: .fuerza, title: title, in: db.context)

        // ⚠️ Todos estos son días de **Día A** para el usuario, y reciben la rutina del
        // **Día B**: otros ejercicios, otras series, otro trabajo.
        #expect(
            nombres(day) == StrengthSeed.dayB.map(\.name),
            "Comportamiento actual: la letra 'b' en \"\(title)\" gana"
        )
        #expect(nombres(day) != StrengthSeed.dayA.map(\.name))
    }

    @Test("U-18 · Es alcanzable: el título lo edita el usuario y el seed lo relee")
    func itIsReachableThroughTheTitleEditor() {
        let db = TestDB()

        // `WorkoutEditView` expone el título en un `TextField`. El usuario renombra su día A
        // para acordarse de qué hace.
        let day = makeDay(fechaNormal, type: .fuerza, title: "Fuerza A", in: db.context)
        #expect(nombres(day) == StrengthSeed.dayA.map(\.name))

        day.title = "Fuerza A · empuje y brazos"

        // Y `populateIfNeeded` llama a `templates(for:)` con el título **actual**, así que
        // un día vacío renombrado se llena con la rutina equivocada. No hace falta que el
        // usuario haga nada raro: alcanza con que le ponga nombre a su propio entrenamiento.
        #expect(nombres(day) == StrengthSeed.dayB.map(\.name), "⚠️ Cambió de rutina al renombrarlo")
    }

    @Test("U-18 · 'liviana' gana sobre la 'b', pero por orden, no por precisión")
    func livianaWinsByOrdering() {
        let db = TestDB()

        // Este título tiene las dos cosas: "liviana" **y** una "b" (en "banco"). Cae en el
        // taper y no en el Día B completo, pero solo porque el `if` de "liviana" va
        // **primero**. Si alguien reordenara los dos `if`, este día cambiaría de rutina.
        let taper = makeDay(fechaNormal, type: .fuerza,
                            title: "Fuerza liviana (banco)", in: db.context)

        let rutina = StrengthSeed.templates(for: taper).map(\.name)
        #expect(rutina != StrengthSeed.dayB.map(\.name), "No es el Día B completo: es su variante de taper")
        #expect(rutina.count < StrengthSeed.dayB.count, "El taper saca ejercicios")

        // O sea: el orden de los `if` es lo único que evita que "liviana" y "b" choquen. Un
        // `switch` sobre un campo explícito (un `enum` de rutina en el día) haría innecesaria
        // toda esta adivinanza sobre el texto.
    }

    // MARK: - U-19

    // El día "liviana" del taper: el Día B con la mitad de las series. Sirve para llegar
    // descansado a la carrera sin perder el estímulo.

    /// La rutina de taper, tal como sale hoy.
    @MainActor
    private func taper(in context: ModelContext) -> [StrengthSeed.ExerciseTemplate] {
        let day = makeDay(fechaNormal, type: .fuerza,
                          title: "Fuerza liviana (tren superior)", in: context)
        return StrengthSeed.templates(for: day)
    }

    @Test("U-19 · Las series se parten al medio, redondeando hacia arriba")
    func setsAreHalvedRoundingUp() throws {
        let db = TestDB()
        let rutina = taper(in: db.context)

        // Redondear **hacia arriba** importa: con 3 series, la mitad exacta sería 1,5. Hacia
        // abajo quedaría 1 sola serie, que ya no es un entrenamiento liviano — es casi nada.
        let porNombre = Dictionary(uniqueKeysWithValues: rutina.map { ($0.name, $0.sets) })
        let original = Dictionary(uniqueKeysWithValues: StrengthSeed.dayB.map { ($0.name, $0.sets) })

        #expect(original["Empuje de hombros con barra (parado)"] == 4)
        #expect(porNombre["Empuje de hombros con barra (parado)"] == 2)

        #expect(original["Abdominal cruzado"] == 3)
        #expect(porNombre["Abdominal cruzado"] == 2, "3 → 2, no 1")

        #expect(original["Salto sobre step a una pierna"] == 2)
        #expect(porNombre["Salto sobre step a una pierna"] == 1)

        // Ninguno queda en cero: el `max(1, …)` garantiza al menos una serie de cada
        // ejercicio que sobrevive al filtro.
        #expect(rutina.allSatisfy { $0.sets >= 1 })
    }

    @Test("U-19 · ⚠️ Dice 'sin el trabajo de pierna', pero solo saca uno")
    func theTaperDoesNotActuallyRemoveLegWork() {
        let db = TestDB()
        let nombres = taper(in: db.context).map(\.name)

        // El comentario de `templates(for:)` dice que el día liviano es "el DÍA B reducido a
        // la mitad **y sin pierna**". El filtro, en cambio, saca **un solo ejercicio**:
        // `Flexión de rodillas`.
        #expect(!nombres.contains { $0.contains("Flexión de rodillas") }, "Este sí lo saca")

        // ⚠️ Y estos, que son igual de pierna, se quedan:
        #expect(nombres.contains("Aductores en máquina"))
        #expect(nombres.contains("Extensión de rodillas en máquina"))
        #expect(nombres.contains("Peso muerto a una pierna con pesa rusa"))
        #expect(nombres.contains("Equilibrio a un pie sobre bosu"))

        // O sea: el código y su comentario dicen cosas distintas, y **no se puede saber cuál
        // tiene razón sin preguntar**. Si la intención era descargar las piernas antes de la
        // carrera, el taper no la cumple: deja cuádriceps (extensión), aductores y un peso
        // muerto unilateral. Si la intención era solo bajar el volumen, el comentario miente.
        //
        // El test documenta lo que **hace**, no lo que debería hacer. Queda para decidir.
    }

    @Test("U-19 · El salto sigue en la rutina: lo saca la semana, no el taper")
    func theJumpIsRemovedByTheWeekNotByTheTaper() {
        let db = TestDB()

        // En una fecha normal, el día liviano **conserva** el salto.
        #expect(taper(in: db.context).map(\.name).contains("Salto sobre step a una pierna"))

        // El salto lo saca `omitsJumps`, que mira la **fecha** (semanas de pico y taper), no
        // el título. Son dos filtros independientes que se suelen confundir porque los dos
        // aplican al mismo día de la semana del taper. Ver U-20.
        let enSemanaDeTaper = makeDay(date(2026, 7, 1), type: .fuerza,
                                      title: "Fuerza liviana (tren superior)", in: db.context)
        let nombres = StrengthSeed.templates(for: enSemanaDeTaper).map(\.name)
        #expect(!nombres.contains("Salto sobre step a una pierna"))
    }

    @Test("U-19 · ⚠️ La nota del taper pisa la del circuito")
    func theTaperNoteOverwritesTheOriginal() throws {
        let db = TestDB()
        let rutina = taper(in: db.context)

        let abdominal = try #require(rutina.first { $0.name == "Abdominal cruzado" })
        let originalAbdominal = try #require(
            StrengthSeed.dayB.first { $0.name == "Abdominal cruzado" }
        )

        // La nota original explicaba **cómo** se hace el ejercicio dentro de la sesión: que
        // va en circuito, cuántas vueltas, si hay pausa.
        #expect(originalAbdominal.note?.contains("circuito") == true)

        // ⚠️ El taper la reemplaza entera. La info del circuito se pierde: el usuario ve
        // "Taper · mitad de series, carga cómoda" y no sabe que esos primeros ejercicios van
        // seguidos, sin pausa.
        #expect(abdominal.note == "Taper · mitad de series, carga cómoda")
        #expect(abdominal.note?.contains("circuito") == false)

        // La rama que **sí** preserva la nota es la de `sets == 0`… y no hay ninguna
        // plantilla con 0 series en todo el archivo. O sea: es código muerto.
        #expect(StrengthSeed.dayB.allSatisfy { $0.sets > 0 })
        #expect(StrengthSeed.dayA.allSatisfy { $0.sets > 0 })
    }

    @Test("U-19 · La variante pierde el flag `weighted`, pero hoy no se nota")
    func theTaperDropsTheWeightedFlagHarmlessly() throws {
        let db = TestDB()
        let rutina = taper(in: db.context)

        // `taperVariant` reconstruye cada `ExerciseTemplate` **sin pasar `weighted`**, que en
        // el init tiene default `true`. Así que en la copia de taper, hasta el core y el
        // equilibrio figuran como "con peso".
        let puente = try #require(rutina.first { $0.name == "Puente lateral" })
        let puenteOriginal = try #require(StrengthSeed.dayB.first { $0.name == "Puente lateral" })
        #expect(puenteOriginal.weighted == false)
        #expect(puente.weighted == true, "⚠️ La copia perdió el flag")

        // Pero **hoy es inofensivo**, por dos razones que conviene tener escritas:
        //
        // 1. `insert()` nunca lee `template.weighted`: no lo copia al `Exercise`.
        // 2. `Exercise.tracksWeight` resuelve **por nombre**, contra la lista estática
        //    `bodyweightExerciseNames`, que sale de los `dayA`/`dayB` **originales** — no de
        //    la copia de taper.
        //
        // Así que el ejercicio sembrado sigue sabiendo que no lleva peso.
        #expect(StrengthSeed.tracksWeight(exerciseName: "Puente lateral") == false)

        // ⚠️ Es una mina: el día que alguien haga que `insert()` use `template.weighted`
        // —lo natural, si el flag existe—, el día de taper va a empezar a pedir kilos para
        // el puente lateral y el equilibrio en bosu.
    }

    // MARK: - U-20

    // El segundo filtro, independiente del título: en las semanas de **pico de volumen**
    // (15–21/6) y de **taper** (29/6–5/7) se sacan los ejercicios de salto, para no cargar
    // las articulaciones cuando la pierna ya está exigida por el running.

    @MainActor
    private func nombresEn(_ fecha: Date, title: String, in context: ModelContext) -> [String] {
        StrengthSeed.templates(for: makeDay(fecha, type: .fuerza, title: title, in: context))
            .map(\.name)
    }

    @Test(
        "U-20 · Dentro de las dos ventanas no hay saltos; fuera, sí",
        arguments: [
            // Semana de pico: 15 al 21 de junio, los dos bordes incluidos.
            (date(2026, 6, 14), false),  // víspera
            (date(2026, 6, 15), true),   // primer día
            (date(2026, 6, 18), true),
            (date(2026, 6, 21), true),   // último día
            (date(2026, 6, 22), false),  // día siguiente
            // Entre las dos ventanas hay una semana normal.
            (date(2026, 6, 25), false),
            // Semana de taper: 29 de junio al 5 de julio.
            (date(2026, 6, 28), false),  // víspera
            (date(2026, 6, 29), true),   // primer día
            (date(2026, 7, 5), true),    // último día
            (date(2026, 7, 6), false),   // día siguiente
        ]
    )
    func jumpsAreOmittedOnlyInsideTheTwoWindows(fecha: Date, sinSaltos: Bool) {
        let db = TestDB()

        // Los dos bordes de cada ventana son inclusivos (`>=` y `<=`), y la comparación es
        // por `startOfDay`, así que la hora del día no cambia el resultado.
        let diaA = nombresEn(fecha, title: "Fuerza A", in: db.context)
        #expect(diaA.contains("Salto de paracaidista") == !sinSaltos)

        let diaB = nombresEn(fecha, title: "Fuerza B", in: db.context)
        #expect(diaB.contains("Salto sobre step a una pierna") == !sinSaltos)
    }

    @Test("U-20 · El filtro saca los saltos y no toca nada más")
    func theFilterOnlyRemovesJumps() {
        let db = TestDB()

        let normal = nombresEn(date(2026, 6, 10), title: "Fuerza A", in: db.context)
        let enPico = nombresEn(date(2026, 6, 18), title: "Fuerza A", in: db.context)

        // Exactamente un ejercicio de diferencia, y es el salto.
        #expect(normal.count == enPico.count + 1)
        #expect(Set(normal).subtracting(enPico) == ["Salto de paracaidista"])
    }

    @Test("U-20 · ⚠️ Las ventanas están clavadas a 2026 y ya pasaron")
    func theWindowsAreHardcodedToAPastRace() {
        let db = TestDB()

        // `omitsJumps` compara contra fechas literales de 2026: 15–21/6 y 29/6–5/7. Eran las
        // semanas de pico y taper **de la carrera del 5/7/2026**, que ya se corrió.
        //
        // Consecuencia: para cualquier día de hoy en adelante, el filtro **nunca** se activa.
        // La app ya no es un plan de media maratón —es GymLog, entrenamiento continuo— así
        // que estas dos ventanas son código muerto que espera a un evento que no vuelve.
        let hoy = nombresEn(date(2026, 7, 11), title: "Fuerza A", in: db.context)
        #expect(hoy.contains("Salto de paracaidista"))

        // Y en 2027 tampoco: las mismas semanas del calendario no matchean, porque el año
        // está en la constante.
        let mismaSemanaEn2027 = nombresEn(date(2027, 6, 18), title: "Fuerza A", in: db.context)
        #expect(mismaSemanaEn2027.contains("Salto de paracaidista"))

        // No es un bug —hoy nadie espera que se saquen los saltos— pero es deuda con nombre:
        // si el taper vuelve a hacer falta (otra carrera), esto hay que rehacerlo relativo a
        // una fecha objetivo, no clavado. Va con la deuda de HANDOFF: "el plan se quedó sin
        // días" el 5/7/2026.
    }

    @Test("U-20 · El taper de julio combina los dos filtros")
    func theJulyTaperCombinesBothFilters() {
        let db = TestDB()

        // El único día donde los dos filtros se cruzan: título "liviana" (mitad de series) y
        // fecha dentro de la ventana de taper (sin saltos). Se aplican en orden —primero la
        // variante, después el filtro por fecha— y no se pisan.
        let dia = makeDay(date(2026, 7, 1), type: .fuerza,
                          title: "Fuerza liviana (tren superior)", in: db.context)
        let rutina = StrengthSeed.templates(for: dia)

        #expect(!rutina.contains { $0.name.contains("Salto") }, "El filtro de fecha sacó el salto")
        #expect(!rutina.contains { $0.name.contains("Flexión de rodillas") }, "El taper sacó la flexión")
        #expect(rutina.allSatisfy { $0.sets <= 2 }, "Y las series están partidas al medio")
    }
}
