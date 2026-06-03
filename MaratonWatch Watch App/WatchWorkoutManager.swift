//
//  WatchWorkoutManager.swift
//  MaratonWatch Watch App
//
//  Maneja la sesión de entrenamiento de HealthKit en el reloj: arranca un
//  HKWorkoutSession + HKLiveWorkoutBuilder para leer la frecuencia cardíaca en
//  vivo y las calorías, y al terminar devuelve las métricas para guardarlas en
//  el WorkoutDay (reutilizando los campos avgHeartRate / activeCalories /
//  durationMinutes que ya maneja la app).
//

import Foundation
import HealthKit

@Observable
@MainActor
final class WatchWorkoutManager: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Pulso actual (bpm) para mostrar en vivo. 0 = todavía sin lectura.
    var currentHeartRate: Int = 0
    /// Calorías activas acumuladas (kcal).
    var activeCalories: Double = 0
    /// Indica si hay una sesión de entrenamiento en curso.
    var isRunning = false

    private let heartRateType = HKQuantityType(.heartRate)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    /// Pide permiso a Apple Salud para leer y guardar el workout junto con sus
    /// muestras de pulso y energía (así el entrenamiento queda con FC y calorías,
    /// no solo la duración).
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKQuantityType.workoutType(), heartRateType, energyType]
        let read: Set<HKObjectType> = [heartRateType, energyType]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    /// Arranca la sesión de entrenamiento de fuerza en interior.
    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    /// Termina la sesión y devuelve las métricas para persistir en el WorkoutDay.
    @discardableResult
    func end() async -> (avgHeartRate: Double?, activeCalories: Double?, minutes: Int?) {
        guard let session, let builder else { return (nil, nil, nil) }

        let endDate = Date()
        let avgHR = builder.statistics(for: heartRateType)?.averageQuantity()?.doubleValue(for: bpmUnit)
        let kcal = builder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let elapsed = builder.elapsedTime

        session.end()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            builder.endCollection(withEnd: endDate) { _, _ in
                builder.finishWorkout { _, _ in cont.resume() }
            }
        }

        self.session = nil
        self.builder = nil
        isRunning = false

        let minutes = Int((elapsed / 60).rounded())
        return (avgHR, kcal, minutes > 0 ? minutes : nil)
    }
}

// MARK: - Delegados de HealthKit (nonisolated; saltan a MainActor con primitivos)

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let hrType = HKQuantityType(.heartRate)
        let calType = HKQuantityType(.activeEnergyBurned)
        let unit = HKUnit.count().unitDivided(by: .minute())

        var bpm: Double?
        var kcal: Double?
        if collectedTypes.contains(hrType) {
            bpm = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?.doubleValue(for: unit)
        }
        if collectedTypes.contains(calType) {
            kcal = workoutBuilder.statistics(for: calType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }

        Task { @MainActor in
            if let bpm { self.currentHeartRate = Int(bpm.rounded()) }
            if let kcal { self.activeCalories = kcal }
        }
    }
}
