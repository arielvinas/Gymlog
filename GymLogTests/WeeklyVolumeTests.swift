//
//  WeeklyVolumeTests.swift
//  GymLogTests
//
//  El volumen semanal: los kilómetros corridos y el **tonelaje** levantado. Son
//  los números de la tarjeta de tendencia — lo que el usuario mira para saber si
//  está progresando. Si suman mal, mienten en silencio: no hay forma de darse
//  cuenta desde la app.
//
//  Backlog: TESTING.md · U-22..U-29
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Volumen semanal")
struct WeeklyVolumeTests {

    /// Un miércoles cualquiera, lejos de los bordes de la semana.
    private let miercoles = date(2026, 6, 17)

    // MARK: - U-22

    @Test("U-22 · El tonelaje es la suma de peso × reps de cada serie")
    func tonnageIsTheSumOfWeightTimesReps() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // 3 series de press: 80×8, 80×8, 85×6 → 640 + 640 + 510 = 1790.
        let press = makeExercise("Press banca", on: day, order: 0,
                                 sets: [(80, 8), (80, 8), (85, 6)], in: db.context)

        let total = WeeklyVolume.tonnage(for: miercoles, among: [press])
        #expect(total == 1790)
    }

    @Test("U-22 · Las series sin peso o sin reps no suman")
    func setsWithoutWeightOrRepsDoNotCount() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // El core y la plancha no llevan peso (ver U-21), así que sus series tienen reps
        // pero no kilos. Si contaran como peso 0 el resultado sería el mismo, pero si
        // contaran como peso 1 —o si `weight` viniera con basura— inflarían el tonelaje.
        let plancha = makeExercise("Puente lateral", on: day, order: 0,
                                   sets: [(nil, 30), (nil, 30)], in: db.context)

        // Y una serie cargada a medias: el usuario puso el peso pero no las reps (se fue del
        // gimnasio antes de anotarlas). No hay forma de saber cuánto levantó.
        let press = makeExercise("Press banca", on: day, order: 1,
                                 sets: [(80, 8), (80, nil)], in: db.context)

        let total = WeeklyVolume.tonnage(for: miercoles, among: [plancha, press])

        // Solo la serie completa: 80 × 8. La plancha no aporta, y la serie a medias tampoco.
        #expect(total == 640)
    }

    @Test("U-22 · Solo cuentan los ejercicios de esa semana")
    func onlyThisWeeksExercisesCount() {
        let db = TestDB()

        let estaSemana = makeDay(miercoles, type: .fuerza, in: db.context)
        let deEstaSemana = makeExercise("Press banca", on: estaSemana, order: 0,
                                        sets: [(80, 10)], in: db.context)

        // El lunes de la semana siguiente. El filtro es por semana calendario
        // (`toGranularity: .weekOfYear`), no por "hace 7 días".
        let semanaQueViene = makeDay(date(2026, 6, 22), type: .fuerza, in: db.context)
        let deOtraSemana = makeExercise("Press banca", on: semanaQueViene, order: 0,
                                        sets: [(100, 10)], in: db.context)

        let total = WeeklyVolume.tonnage(for: miercoles, among: [deEstaSemana, deOtraSemana])
        #expect(total == 800, "Los 1000 kg de la semana que viene no entran")
    }

    @Test("U-22 · ⚠️ Cuenta las series que todavía no confirmaste")
    func tonnageCountsUnconfirmedSets() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // Dos series: una hecha, otra no. La segunda tiene datos porque el **prellenado** se
        // los puso (ver I-17: al llegar a la serie, las reps van al objetivo y el peso al
        // último usado).
        let press = makeExercise("Press banca", on: day, order: 0,
                                 sets: [(80, 8), (80, 8)], in: db.context)
        press.orderedSets[0].isDone = true
        press.orderedSets[1].isDone = false

        // ⚠️ `tonnage` no mira `isDone`: suma las dos. O sea que abrir la sesión guiada —sin
        // levantar nada— ya le agrega 640 kg a la semana.
        let total = WeeklyVolume.tonnage(for: miercoles, among: [press])
        #expect(total == 1280, "⚠️ Suma la serie sin confirmar")

        // Es el mismo defecto que el bug 14 (`loggedSetsCount` en el espejo), pero acá pega
        // en un número que **queda**: el tonelaje de la semana en la tarjeta de tendencia.
        // Si abrís la sesión y no entrenás, la semana igual muestra volumen.
        //
        // Y es asimétrico con los km, que **sí** filtran por `isCompleted` (ver U-24): un
        // rodaje no cuenta hasta que lo marcás como hecho, pero una serie cuenta apenas la
        // app le pone un número encima.
    }

    @Test("U-22 · Una serie con peso 0 suma 0, no rompe")
    func aZeroWeightSetAddsNothing() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // Peso 0 con reps es un dato válido (una barra vacía, una progresión desde cero).
        // Entra al cálculo —no lo descarta el `guard`, porque 0 no es `nil`— y aporta 0.
        let press = makeExercise("Press banca", on: day, order: 0,
                                 sets: [(0, 10), (80, 10)], in: db.context)

        #expect(WeeklyVolume.tonnage(for: miercoles, among: [press]) == 800)
    }

    // MARK: - U-23

    // El cero no es un caso de borde: es lo que ve **la mayoría de las semanas** de alguien
    // que corre y va al gimnasio dos veces. La tarjeta de tendencia tiene que poder dibujar
    // una barra en cero sin inventar nada ni romperse.

    @Test("U-23 · Sin ejercicios, el tonelaje es cero")
    func noExercisesMeansZeroTonnage() {
        // Una app recién instalada, o una semana de descanso. `reduce(0, +)` sobre una lista
        // vacía da 0, que es el valor correcto: no hay que distinguir "cero kilos" de "sin
        // datos" — para una barra de volumen son lo mismo.
        #expect(WeeklyVolume.tonnage(for: miercoles, among: []) == 0)
    }

    @Test("U-23 · Un ejercicio sin series suma cero")
    func anExerciseWithoutSetsAddsZero() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // Los ejercicios de core del plan no tienen series (ver I-01: ocupan un paso pero no
        // llevan `ExerciseSet`). El `flatMap(\.orderedSets)` los aplana a nada.
        let plancha = makeExercise("Plancha", on: day, order: 0, targetReps: "30 s", in: db.context)
        #expect(plancha.orderedSets.isEmpty)

        #expect(WeeklyVolume.tonnage(for: miercoles, among: [plancha]) == 0)
    }

    @Test("U-23 · Una semana sin gimnasio da cero aunque haya ejercicios en otras")
    func aWeekWithoutGymIsZero() {
        let db = TestDB()

        // Hay entrenamiento la semana anterior y la siguiente, pero no en esta. El filtro por
        // semana deja la lista vacía y el `reduce` devuelve 0 — sin `nil`, sin división por
        // cero, sin caso especial.
        let anterior = makeDay(date(2026, 6, 10), type: .fuerza, in: db.context)
        let siguiente = makeDay(date(2026, 6, 24), type: .fuerza, in: db.context)
        let a = makeExercise("Press banca", on: anterior, order: 0, sets: [(80, 10)], in: db.context)
        let b = makeExercise("Press banca", on: siguiente, order: 0, sets: [(90, 10)], in: db.context)

        #expect(WeeklyVolume.tonnage(for: miercoles, among: [a, b]) == 0)

        // Y las semanas de al lado sí suman: el cero de esta no se contagia.
        #expect(WeeklyVolume.tonnage(for: date(2026, 6, 10), among: [a, b]) == 800)
        #expect(WeeklyVolume.tonnage(for: date(2026, 6, 24), among: [a, b]) == 900)
    }

    // MARK: - U-24

    // Los tres números de la tarjeta de volumen usan **tres criterios distintos** para decidir
    // qué cuenta. No es evidente mirando la pantalla, y es lo que hace que "planificado" y
    // "real" no sean comparables de la forma que uno esperaría:
    //
    //   plannedKm  → todos los días de la semana, completados o no  (es un objetivo)
    //   actualKm   → solo los días **completados**                  (es un hecho)
    //   tonnage    → todas las series, confirmadas o no             (⚠️ bug 15)
    //
    // Los dos primeros están bien y la asimetría entre ellos es **deliberada**. El tercero es
    // el que se salió de la fila.

    @Test("U-24 · Los km reales solo cuentan los días completados")
    func actualKilometresOnlyCountCompletedDays() {
        let db = TestDB()

        // Un rodaje hecho: 8 km, marcado como completo.
        makeDay(miercoles, type: .rodaje, title: "Rodaje 8 km",
                isCompleted: true, actualKm: 8, in: db.context)

        // Y otro con km cargados pero **sin marcar como completo**. Pasa de verdad: el
        // usuario abre el formulario, escribe los kilómetros y se va sin confirmar. O la
        // importación de HealthKit deja el dato antes de que él lo revise.
        makeDay(date(2026, 6, 18), type: .rodaje, title: "Rodaje 10 km",
                isCompleted: false, actualKm: 10, in: db.context)

        let dias = try! db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Solo los 8. Es la decisión correcta: `actualKm` responde "cuánto corriste", y un
        // día sin confirmar todavía no es un hecho. El número no puede adelantarse al usuario.
        #expect(WeeklyVolume.actualKm(for: miercoles, among: dias) == 8)
    }

    @Test("U-24 · Los km planificados cuentan toda la semana, hecha o no")
    func plannedKilometresCountTheWholeWeek() {
        let db = TestDB()

        makeDay(miercoles, type: .rodaje, title: "Rodaje 8 km",
                isCompleted: true, actualKm: 8, in: db.context)
        makeDay(date(2026, 6, 18), type: .rodaje, title: "Fondo 12 km",
                isCompleted: false, in: db.context)

        let dias = try! db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Los 20 km, aunque el fondo todavía no se haya corrido. Y **acá está bien**: los km
        // planificados son el objetivo de la semana. Si el número bajara a medida que los
        // días quedan sin hacer, dejaría de ser un objetivo y no habría contra qué comparar.
        #expect(WeeklyVolume.plannedKm(for: miercoles, among: dias) == 20)
        #expect(WeeklyVolume.actualKm(for: miercoles, among: dias) == 8)

        // O sea: 8 de 20. Ese contraste —lo que hiciste contra lo que te tocaba— es
        // exactamente lo que la tarjeta quiere mostrar, y depende de que los dos números
        // usen criterios **distintos**. La asimetría es la función, no un descuido.
    }

    @Test("U-24 · Un día completado sin km no aporta nada")
    func aCompletedDayWithoutKilometresAddsNothing() {
        let db = TestDB()

        // Un día de fuerza completado: `actualKm` es `nil`. El `compactMap` lo saltea.
        makeDay(miercoles, type: .fuerza, title: "Fuerza A", isCompleted: true, in: db.context)
        // Y un rodaje completado al que el usuario nunca le cargó los km.
        makeDay(date(2026, 6, 18), type: .rodaje, title: "Rodaje 8 km",
                isCompleted: true, in: db.context)

        let dias = try! db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Cero km reales, pero **8 planificados**: el plan sabe lo que había que correr, el
        // registro no sabe lo que se corrió. Es la diferencia entre las dos fuentes — una lee
        // el texto del plan, la otra lee lo que el usuario cargó.
        #expect(WeeklyVolume.actualKm(for: miercoles, among: dias) == 0)
        #expect(WeeklyVolume.plannedKm(for: miercoles, among: dias) == 8)
    }

    @Test("U-24 · ⚠️ El tonelaje es el que rompe la simetría")
    func tonnageIsTheOddOneOut() {
        let db = TestDB()

        // El mismo escenario, en las dos mitades de la tarjeta: algo hecho y algo no.
        //
        // Corriendo: un rodaje sin confirmar **no cuenta**.
        makeDay(miercoles, type: .rodaje, title: "Rodaje 10 km",
                isCompleted: false, actualKm: 10, in: db.context)

        // En el gimnasio: una serie sin confirmar **sí cuenta** (bug 15, ver U-22).
        let gimnasio = makeDay(miercoles, type: .fuerza, in: db.context)
        let press = makeExercise("Press banca", on: gimnasio, order: 0,
                                 sets: [(80, 10)], in: db.context)
        press.orderedSets[0].isDone = false

        let dias = try! db.context.fetch(FetchDescriptor<WorkoutDay>())

        #expect(WeeklyVolume.actualKm(for: miercoles, among: dias) == 0, "El rodaje espera")
        #expect(WeeklyVolume.tonnage(for: miercoles, among: [press]) == 800, "⚠️ La serie no")

        // Dos datos igual de "sin confirmar", dos respuestas opuestas, en la misma tarjeta.
        // Si el tonelaje filtrara por `isDone` —como los km filtran por `isCompleted`— las
        // dos mitades contarían lo mismo y el bug 15 desaparecería.
    }

    // MARK: - U-25

    // `recentWeeks` arma la serie de la tendencia: una barra por semana, de izquierda a
    // derecha. El orden **no es un detalle de presentación** — la vista dibuja el arreglo tal
    // como viene, así que si estuviera al revés la tendencia se leería invertida (parecería
    // que bajás cuando subís).

    @Test("U-25 · Devuelve la cantidad pedida, de la más vieja a la más nueva")
    func recentWeeksAreOrderedOldestFirst() throws {
        let db = TestDB()
        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        let semanas = WeeklyVolume.recentWeeks(6, days: dias, exercises: [], today: miercoles)

        #expect(semanas.count == 6)

        // Cada `weekStart` es anterior al siguiente: la última es la de hoy.
        let inicios = semanas.map(\.weekStart)
        #expect(inicios == inicios.sorted(), "De la más vieja a la más nueva")

        // Y las seis son semanas distintas, consecutivas: exactamente 7 días entre una y la
        // siguiente. Sin huecos ni repetidas.
        for (anterior, siguiente) in zip(inicios, inicios.dropFirst()) {
            #expect(siguiente.timeIntervalSince(anterior) == 7 * 24 * 60 * 60)
        }
    }

    @Test("U-25 · La última semana es la que contiene hoy")
    func theLastWeekContainsToday() throws {
        let db = TestDB()

        // Entrenamiento de esta semana: 8 km corridos y 800 kg levantados.
        makeDay(miercoles, type: .rodaje, title: "Rodaje 8 km",
                isCompleted: true, actualKm: 8, in: db.context)
        let gimnasio = makeDay(miercoles, type: .fuerza, in: db.context)
        makeExercise("Press banca", on: gimnasio, order: 0, sets: [(80, 10)], in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())

        let semanas = WeeklyVolume.recentWeeks(6, days: dias, exercises: ejercicios, today: miercoles)
        let ultima = try #require(semanas.last)

        // Los datos de hoy caen en la **última** barra, que es la del extremo derecho de la
        // tarjeta. Si cayeran en la primera, la tendencia mostraría el presente como pasado.
        #expect(ultima.runKm == 8)
        #expect(ultima.tonnage == 800)

        // Y la semana empieza el **lunes** (ver U-28): el 17/6/2026 es miércoles, así que su
        // semana arranca el 15.
        let cal = PlanConstants.calendar
        #expect(cal.component(.day, from: ultima.weekStart) == 15)
    }

    @Test("U-25 · Cada semana recibe solo sus propios datos")
    func eachWeekGetsItsOwnData() throws {
        let db = TestDB()

        // Tres semanas seguidas, con volúmenes distintos, para poder distinguirlas.
        makeDay(date(2026, 6, 3), type: .rodaje, title: "Rodaje 5 km",
                isCompleted: true, actualKm: 5, in: db.context)
        makeDay(date(2026, 6, 10), type: .rodaje, title: "Rodaje 10 km",
                isCompleted: true, actualKm: 10, in: db.context)
        makeDay(miercoles, type: .rodaje, title: "Rodaje 15 km",
                isCompleted: true, actualKm: 15, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        let semanas = WeeklyVolume.recentWeeks(6, days: dias, exercises: [], today: miercoles)

        // Las tres últimas barras: 5, 10, 15. Creciente, como se cargó. Las tres primeras
        // están vacías (no hay datos tan atrás) y valen 0.
        #expect(semanas.map(\.runKm) == [0, 0, 0, 5, 10, 15])
    }

    @Test("U-25 · Pedir una sola semana devuelve la de hoy")
    func askingForOneWeekReturnsThisWeek() throws {
        let db = TestDB()
        makeDay(miercoles, type: .rodaje, title: "Rodaje 8 km",
                isCompleted: true, actualKm: 8, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        let semanas = WeeklyVolume.recentWeeks(1, days: dias, exercises: [], today: miercoles)

        // El `(0..<count).reversed()` con count = 1 da `[0]`: un solo offset, el de hoy. Es
        // el borde inferior del rango útil — el de arriba (0 y negativos) es U-26 y U-27.
        #expect(semanas.count == 1)
        #expect(semanas[0].runKm == 8)
    }
}
