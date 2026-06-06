//
//  HealthManager.swift
//  Maraton
//
//  Lectura de entrenamientos de Apple Salud (HealthKit) para los días de corrida.
//

import Foundation
#if !targetEnvironment(macCatalyst)
import HealthKit
#endif

/// Datos importados de un entrenamiento de Apple Salud.
struct ImportedWorkout {
    var km: Double?
    var minutes: Int?
    var avgHeartRate: Double?
    var activeCalories: Double?
}

/// Una métrica de salud a lo largo del período: último valor, promedio y el
/// primer valor del período (para ver tendencia).
struct HealthTrend {
    var latest: Double?
    var average: Double?
    var earliest: Double?

    /// Variación entre el primer y el último valor del período.
    var change: Double? {
        guard let latest, let earliest else { return nil }
        return latest - earliest
    }

    var hasData: Bool { latest != nil || average != nil }
}

/// Resumen de un entrenamiento leído de Apple Salud / Apple Fitness.
struct HealthWorkoutSummary: Identifiable {
    let id = UUID()
    let date: Date
    let activityName: String
    let durationMinutes: Int
    let distanceKm: Double?
    let activeCalories: Double?
    let avgHeartRate: Double?
}

/// Fotografía de los datos de Apple Salud para el período del reporte.
struct HealthSnapshot {
    var available = false
    var restingHeartRate: HealthTrend?
    var hrv: HealthTrend?
    var vo2Max: HealthTrend?
    var bodyMass: HealthTrend?
    var avgSleepHours: Double?
    var sleepNights = 0
    var workouts: [HealthWorkoutSummary] = []

    /// Calorías activas totales de los entrenamientos del período.
    var totalActiveCalories: Double {
        workouts.compactMap(\.activeCalories).reduce(0, +)
    }

    /// Minutos de entrenamiento totales del período.
    var totalWorkoutMinutes: Int {
        workouts.map(\.durationMinutes).reduce(0, +)
    }
}

enum HealthError: LocalizedError {
    case notAvailable
    case noWorkoutFound

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Salud no está disponible en este dispositivo."
        case .noWorkoutFound:
            return "No encontramos una corrida registrada para este día en Apple Salud."
        }
    }
}

#if targetEnvironment(macCatalyst)

// En Mac no existe Apple Salud: stub que mantiene la API sin romper nada.
@MainActor
final class HealthManager {
    static let shared = HealthManager()
    private init() {}

    /// Apple Salud no está disponible en Mac.
    static var isHealthAvailable: Bool { false }

    func importRun(for date: Date) async throws -> ImportedWorkout {
        throw HealthError.notAvailable
    }

    func importStrength(for date: Date) async throws -> ImportedWorkout {
        throw HealthError.notAvailable
    }

    /// Apple Salud no está disponible en Mac: snapshot vacío.
    func snapshot(from start: Date, to end: Date) async -> HealthSnapshot {
        HealthSnapshot(available: false)
    }
}

#else

@MainActor
final class HealthManager {
    static let shared = HealthManager()
    private let store = HKHealthStore()

    private init() {}

    /// Indica si Apple Salud está disponible en este dispositivo.
    static var isHealthAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Tipos que necesitamos leer. Incluye, además de lo de las corridas, las
    /// métricas de salud que enriquecen el reporte de progreso (reposo, HRV,
    /// VO2máx, peso y sueño).
    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.vo2Max),
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    /// Solicita permiso de lectura a Apple Salud.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Busca la corrida del día indicado y devuelve sus métricas.
    /// Si hay varias, toma la de mayor distancia.
    func importRun(for date: Date) async throws -> ImportedWorkout {
        try await requestAuthorization()
        let workouts = try await workouts(on: date, activityTypes: [.running])
        // La de mayor distancia recorrida.
        guard let workout = workouts.max(by: { (distanceKm(of: $0) ?? 0) < (distanceKm(of: $1) ?? 0) }) else {
            throw HealthError.noWorkoutFound
        }
        return ImportedWorkout(
            km: distanceKm(of: workout),
            minutes: Int((workout.duration / 60.0).rounded()),
            avgHeartRate: try await averageHeartRate(for: workout),
            activeCalories: activeCalories(of: workout)
        )
    }

    /// Busca la sesión de fuerza del día y devuelve sus métricas globales
    /// (duración, FC promedio, calorías). HealthKit no expone series ni peso.
    /// Si hay varias, toma la de mayor duración.
    func importStrength(for date: Date) async throws -> ImportedWorkout {
        try await requestAuthorization()
        let workouts = try await workouts(
            on: date,
            activityTypes: [.traditionalStrengthTraining, .functionalStrengthTraining]
        )
        // La de mayor duración.
        guard let workout = workouts.max(by: { $0.duration < $1.duration }) else {
            throw HealthError.noWorkoutFound
        }
        return ImportedWorkout(
            km: nil,
            minutes: Int((workout.duration / 60.0).rounded()),
            avgHeartRate: try await averageHeartRate(for: workout),
            activeCalories: activeCalories(of: workout)
        )
    }

    // MARK: - Consultas

    /// Devuelve los workouts del día que coincidan con alguno de los tipos dados.
    private func workouts(on date: Date, activityTypes: [HKWorkoutActivityType]) async throws -> [HKWorkout] {
        let cal = PlanConstants.calendar
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let typePredicates = activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Distancia del workout en kilómetros.
    private func distanceKm(of workout: HKWorkout) -> Double? {
        let type = HKQuantityType(.distanceWalkingRunning)
        guard let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return sum.doubleValue(for: .meterUnit(with: .kilo))
    }

    /// Calorías activas del workout en kcal.
    private func activeCalories(of workout: HKWorkout) -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        guard let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return sum.doubleValue(for: .kilocalorie())
    }

    /// Frecuencia cardíaca promedio durante el workout (bpm).
    private func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let bpm = statistics?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    // MARK: - Snapshot para el reporte

    /// Reúne las métricas de Apple Salud del período para el reporte de progreso.
    /// Devuelve un snapshot vacío si Salud no está disponible o se deniega el
    /// permiso; cada métrica faltante queda en `nil` (se muestra "Sin datos").
    func snapshot(from start: Date, to end: Date) async -> HealthSnapshot {
        guard Self.isHealthAvailable, (try? await requestAuthorization()) != nil else {
            return HealthSnapshot(available: false)
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let ms = HKUnit.secondUnit(with: .milli)
        let vo2Unit = HKUnit(from: "ml/kg*min")
        let kg = HKUnit.gramUnit(with: .kilo)

        var snap = HealthSnapshot(available: true)
        snap.restingHeartRate = await trend(.restingHeartRate, unit: bpm, from: start, to: end)
        snap.hrv = await trend(.heartRateVariabilitySDNN, unit: ms, from: start, to: end)
        snap.vo2Max = await trend(.vo2Max, unit: vo2Unit, from: start, to: end)
        snap.bodyMass = await trend(.bodyMass, unit: kg, from: start, to: end)
        let sleep = await sleepStats(from: start, to: end)
        snap.avgSleepHours = sleep.averageHours
        snap.sleepNights = sleep.nights
        snap.workouts = await allWorkouts(from: start, to: end)
        return snap
    }

    /// Último valor, promedio y primer valor de una métrica discreta en el rango.
    private func trend(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> HealthTrend? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let avg = average(type, predicate: predicate, unit: unit)
        async let latest = boundarySample(type, predicate: predicate, unit: unit, ascending: false)
        async let earliest = boundarySample(type, predicate: predicate, unit: unit, ascending: true)

        let trend = HealthTrend(latest: await latest, average: await avg, earliest: await earliest)
        return trend.hasData ? trend : nil
    }

    /// Promedio (discreto) de una métrica en el rango.
    private func average(_ type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Valor de la primera (o última) muestra de una métrica en el rango.
    private func boundarySample(_ type: HKQuantityType, predicate: NSPredicate, unit: HKUnit, ascending: Bool) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)]
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: sort) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Horas de sueño promedio por noche en el rango.
    private func sleepStats(from start: Date, to end: Date) async -> (averageHours: Double?, nights: Int) {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        // Suma de horas dormidas agrupadas por la noche (día de despertar).
        let cal = PlanConstants.calendar
        var perNight: [Date: TimeInterval] = [:]
        for sample in samples where asleep.contains(sample.value) {
            let night = cal.startOfDay(for: sample.endDate)
            perNight[night, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }
        guard !perNight.isEmpty else { return (nil, 0) }
        let totalHours = perNight.values.reduce(0, +) / 3600
        return (totalHours / Double(perNight.count), perNight.count)
    }

    /// Todos los entrenamientos del rango (Apple Fitness), del más reciente al más viejo.
    private func allWorkouts(from start: Date, to end: Date) async -> [HealthWorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var result: [HealthWorkoutSummary] = []
        for workout in workouts {
            let hr = try? await averageHeartRate(for: workout)
            result.append(HealthWorkoutSummary(
                date: workout.startDate,
                activityName: Self.name(for: workout.workoutActivityType),
                durationMinutes: Int((workout.duration / 60).rounded()),
                distanceKm: distanceKm(of: workout),
                activeCalories: activeCalories(of: workout),
                avgHeartRate: hr
            ))
        }
        return result
    }

    /// Nombre legible (es-AR) de un tipo de actividad de Apple Fitness.
    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                    return "Carrera"
        case .walking:                    return "Caminata"
        case .cycling:                    return "Ciclismo"
        case .traditionalStrengthTraining: return "Fuerza"
        case .functionalStrengthTraining: return "Fuerza funcional"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining:               return "Core"
        case .yoga:                       return "Yoga"
        case .hiking:                     return "Senderismo"
        case .swimming:                   return "Natación"
        case .elliptical:                 return "Elíptico"
        case .rowing:                     return "Remo"
        case .stairs, .stairClimbing:     return "Escaleras"
        case .flexibility:                return "Flexibilidad"
        case .cooldown:                   return "Vuelta a la calma"
        default:                          return "Otro"
        }
    }
}

#endif
