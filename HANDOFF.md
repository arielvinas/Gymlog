# Maratón — Handoff

App iOS nativa (SwiftUI + SwiftData) para seguir un plan de media maratón
(21,1 km, **5 de julio de 2026**, Córdoba). 100% offline, español (es-AR),
light/dark. Target del proyecto: `Maraton` (bundle `ariel.Maraton`).

## Estado general
- Plan de entrenamiento con seed + reconciliación versionada.
- Seguimiento de corridas con importación desde Apple Health (HealthKit).
- Rutina de gimnasio (ejercicios/series/peso) + importación de métricas de
  sesiones de fuerza desde Health.
- Dashboard en 3 tabs: **Hoy** (qué hago hoy + check-in + suplementos),
  **Plan** (editable: crear/editar/borrar días), **Progreso** (preparación,
  consistencia, proyección, evolución de fuerza, suplementos).
- Check-in de recuperación diario (energía/dolor/motivación).
- Suplementos (creatina, proteína): marcado diario, adherencia, rachas y
  recordatorios locales configurables.

- **Versión Mac (Mac Catalyst):** mismo target. Barra lateral
  (`NavigationSplitView`), ventana redimensionable, menú "Ir a" con atajos
  ⌘1/⌘2/⌘3. Apple Salud se oculta en Mac (no existe). UI adaptable en
  `RootView.swift` (`#if targetEnvironment(macCatalyst)`).

## Estructura del código
- `Maraton/Models/` — modelos SwiftData (`WorkoutDay`, `Exercise`, `ExerciseSet`,
  `DailyCheckIn`, `SupplementLog`, `SupplementReminder`) + helpers de cálculo
  (`ReadinessCalculator`, `RaceProjection`, `StreakCalculator`, `StrengthProgress`,
  `SupplementTracker`, `ExerciseHistory`) + `HealthManager`, `NotificationManager`,
  `WorkoutSeed`, `WeekAssigner`, formateadores.
- `Maraton/Views/` — `RootView` (adaptable), `TodayView`, `PlanView`,
  `WorkoutDetailView`, `WorkoutEditView`, `GymSessionView`, `CompletionFormView`,
  `ProgressDashboardView`, tarjetas del dashboard, `SupplementSettingsView`.
- Proyecto usa **PBXFileSystemSynchronizedRootGroup**: los archivos nuevos en
  `Maraton/` se agregan solos al target (no hace falta editar el `.pbxproj`).

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
- `ModelContainer` detrás del flag `MaratonApp.iCloudSyncEnabled` (hoy `false`
  → almacenamiento local, offline-first; el código CloudKit con fallback ya está).
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
3. Quitar `@Attribute(.unique)` de `WorkoutDay.date` y `DailyCheckIn.date`
   (CloudKit no admite constraints únicos; la unicidad ya se valida por código).
4. `MaratonApp.iCloudSyncEnabled = true`.
5. Compilar para device con `-allowProvisioningUpdates` (la firma automática
   registra el contenedor `iCloud.ariel.Maraton` y la capability de Push).

Resolución de conflictos: comportamiento estándar de CloudKit (last-writer-wins).
Migración: lightweight de SwiftData; al quitar `.unique` la primera vez puede
haber un breve período de posibles duplicados entre dispositivos hasta sincronizar.
