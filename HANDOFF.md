# Maratón — Handoff

App iOS nativa (SwiftUI + SwiftData) para seguir un plan de media maratón
(21,1 km, **5 de julio de 2026**, Córdoba). 100% offline, español (es-AR),
light/dark. Target del proyecto: `Maraton` (bundle `ariel.Maraton`).

## Estado general
- Plan de entrenamiento con seed + reconciliación versionada.
- Seguimiento de corridas con importación desde Apple Health (HealthKit).
- Rutina de gimnasio (ejercicios/series/peso) + importación de métricas de
  sesiones de fuerza desde Health.
- Dashboard en 3 tabs: **Hoy** (qué hago hoy + suplementos),
  **Plan** (editable: crear/editar/borrar días), **Progreso** (consistencia,
  proyección, evolución de fuerza, suplementos).
- Suplementos (creatina, proteína): marcado diario, adherencia, rachas y
  recordatorios locales configurables.

- **Versión Mac (Mac Catalyst):** mismo target. Barra lateral
  (`NavigationSplitView`), ventana redimensionable, menú "Ir a" con atajos
  ⌘1/⌘2/⌘3. Apple Salud se oculta en Mac (no existe). UI adaptable en
  `RootView.swift` (`#if targetEnvironment(macCatalyst)`).

## Estructura del código
Tres carpetas = tres grupos sincronizados:
- `Shared/` — **código agnóstico de plataforma, compilado por iOS Y watchOS.**
  Modelos SwiftData (`WorkoutDay`, `Exercise`, `ExerciseSet`, `SupplementLog`,
  `SupplementReminder`), helpers (`WorkoutSeed`, `StrengthSeed`, `ExerciseHistory`,
  `PlanConstants`, formateadores), `GuidedSessionEngine` (máquina de estados de la
  sesión de gimnasio guiada, **compartida iPhone ↔ reloj**) y `AppData` (schema,
  creación del `ModelContainer` y sembrado; dueño del flag `iCloudSyncEnabled`).
- `Maraton/` — app iOS/Catalyst (solo target Maraton). `Maraton/Views/` (`RootView`,
  `TodayView`, `PlanView`, `WorkoutDetailView`, `WorkoutEditView`, `GymSessionView`,
  `GuidedGymSessionView`, etc.), `MaratonApp`, y helpers iOS (`HealthManager`,
  `NotificationManager`, `RaceProjection`, `StreakCalculator`, `StrengthProgress`,
  `SupplementTracker`, `WeekAssigner`, `PreviewData`).
- `MaratonWatch Watch App/` — app del reloj (solo target watchOS). `MaratonWatchApp`,
  `WatchRootView` (día de gimnasio de hoy/próximo + Empezar), `WatchGuidedSessionView`
  (corona digital + botones, descanso con vibración, pulso en vivo), `WatchWorkoutManager`
  (HR/calorías vía `HKWorkoutSession`), `Info.plist`, `MaratonWatch.entitlements`, `Assets`.
- Proyecto usa **PBXFileSystemSynchronizedRootGroup**: los archivos nuevos en una
  carpeta se agregan solos a los targets que la incluyen (no hace falta editar el
  `.pbxproj`). El `Info.plist` del reloj queda excluido de recursos vía
  `membershipExceptions` (si no, choca con `INFOPLIST_FILE`).

## Build / deploy (CLI)
- **iPhone físico:** "iPhone de Ariel", iPhone 15 Pro, UDID
  `<UDID-IPHONE>`.
  ```sh
  xcodebuild -project Maraton.xcodeproj -scheme Maraton \
    -destination 'platform=iOS,name=iPhone de Ariel' -configuration Debug \
    -derivedDataPath /tmp/maraton-device -allowProvisioningUpdates build
  xcrun devicectl device install app --device <UDID-IPHONE> \
    /tmp/maraton-device/Build/Products/Debug-iphoneos/Maraton.app
  xcrun devicectl device process launch --device <UDID-IPHONE> ariel.Maraton
  ```
  Requiere el teléfono **desbloqueado** y el perfil de desarrollador confiado
  (Ajustes → General → VPN y gestión de dispositivos).
- **Simulador:** iPhone 15 Pro (creado a mano; el Xcode trae sólo serie 17).
- **Mac (Catalyst), prueba local sin cuenta** (la sesión de Xcode estaba
  rechazando el login; por eso firma ad-hoc "Sign to Run Locally"):
  ```sh
  xcodebuild -project Maraton.xcodeproj -scheme Maraton \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug \
    -derivedDataPath /tmp/maraton-catalyst \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="" DEVELOPMENT_TEAM="" build
  open /tmp/maraton-catalyst/Build/Products/Debug-maccatalyst/Maraton.app
  ```
  Para correrla desde Xcode con la cuenta: re-loguear en Xcode
  (Settings → Accounts) y registrar la Mac.
- **Apple Watch (companion):** target `MaratonWatch Watch App`, bundle
  `ariel.Maraton.watchkitapp`, embebido en la app iOS.
  - ⚠️ **Requiere el platform de watchOS instalado** (Xcode → Settings → Components
    o `xcodebuild -downloadPlatform watchOS`). Como el target iOS **embebe** el
    reloj, sin el platform **tampoco compila el iPhone**.
  - Compilar/correr en simulador:
    ```sh
    xcodebuild -project Maraton.xcodeproj -scheme "MaratonWatch Watch App" \
      -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
      -configuration Debug -derivedDataPath /tmp/maraton-watch build
    xcrun simctl boot "Apple Watch Series 11 (46mm)"
    xcrun simctl install booted \
      "/tmp/maraton-watch/Build/Products/Debug-watchsimulator/MaratonWatch Watch App.app"
    xcrun simctl launch booted ariel.Maraton.watchkitapp
    ```
  - El **pulso en vivo** real necesita un **Apple Watch físico emparejado** (el
    simulador no genera HR real). Las métricas (HR prom., calorías, duración) se
    guardan en el `WorkoutDay` del día (campos `avgHeartRate`/`activeCalories`/
    `durationMinutes`), igual que el import de Apple Salud del iPhone.
  - Catalyst no compila el reloj gracias a `platformFilter = ios` en la dependencia
    y en la fase "Embed Watch Content".

## Pendientes / próximos pasos posibles
- Activar iCloud (ver sección abajo) — requiere cuenta de pago.
- Dejar la `.app` de Mac en una ubicación fija (hoy queda en `/tmp`).
- Posibles mejoras pedidas pero no hechas: ritmo objetivo en la tarjeta "Hoy",
  más suplementos, dosis/cantidad por suplemento.

## ⚠️ Sincronización iCloud (PENDIENTE — requiere cuenta de pago)
CloudKit + Push **no están permitidos en cuentas de desarrollador gratuitas**
(equipos personales). Para activar la sync se necesita el **Apple Developer
Program de pago (US$99/año)**. Hasta entonces, iPhone y Mac funcionan cada uno
con su **base local** (no comparten datos todavía); al activar iCloud, ambos
sincronizan automáticamente sin más cambios.

La capa de datos ya quedó **preparada** (bajo riesgo, sin tocar datos actuales):
- Todos los `@Model` tienen valores por defecto (requisito de CloudKit).
- `ModelContainer` detrás del flag `AppData.iCloudSyncEnabled` (hoy `false`
  → almacenamiento local, offline-first; el código CloudKit con fallback ya está).
  El reloj usa el **mismo** `AppData` (schema/container/flag): hoy cada dispositivo
  tiene su store local sembrado con el mismo plan; al activar iCloud, iPhone, Mac y
  reloj sincronizan con el mismo interruptor.
- Flag de sembrado del plan listo para usar iCloud Key-Value Store cuando se active.

### Pasos para activar iCloud (cuando haya cuenta de pago)
1. `Maraton/Maraton.entitlements`: reagregar
   `com.apple.developer.icloud-container-identifiers` (`iCloud.ariel.Maraton`),
   `com.apple.developer.icloud-services` (`CloudKit`),
   `com.apple.developer.ubiquity-kvstore-identifier`
   (`$(TeamIdentifierPrefix)$(CFBundleIdentifier)`) y
   `aps-environment` (`development`).
2. `project.pbxproj` (Debug y Release): agregar
   `INFOPLIST_KEY_UIBackgroundModes = "remote-notification";`.
3. Quitar `@Attribute(.unique)` de `WorkoutDay.date`
   (CloudKit no admite constraints únicos; la unicidad ya se valida por código).
   Agregar el mismo entitlement de iCloud al reloj (`MaratonWatch.entitlements`),
   con el mismo contenedor CloudKit, para que comparta datos con el iPhone.
4. `AppData.iCloudSyncEnabled = true` (vale para iPhone, Mac y reloj).
5. Compilar para device con `-allowProvisioningUpdates` (la firma automática
   registra el contenedor `iCloud.ariel.Maraton` y la capability de Push).

Resolución de conflictos: comportamiento estándar de CloudKit (last-writer-wins).
Migración: lightweight de SwiftData; al quitar `.unique` la primera vez puede
haber un breve período de posibles duplicados entre dispositivos hasta sincronizar.
