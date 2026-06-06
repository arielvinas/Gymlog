# Maratón — Handoff

App iOS nativa (SwiftUI + SwiftData) para seguir un plan de media maratón
(21,1 km, **5 de julio de 2026**, Córdoba). 100% offline, español (es-AR),
light/dark. Target del proyecto: `Maraton` (bundle `ariel.Maraton`).

## Estado general
- Plan de entrenamiento con seed + reconciliación versionada.
- Seguimiento de corridas con importación desde Apple Health (HealthKit).
- Rutina de gimnasio (ejercicios/series/peso) + importación de métricas de
  sesiones de fuerza desde Health. Plantillas Fuerza A y Fuerza B = los dos días
  del **plan de Megatlón** (entrenador Francisco Ambrosio): cada uno arranca con
  circuito de acondicionamiento + específico (3 vueltas) y sigue con el bloque
  principal de fuerza. Cada ejercicio lleva su **foto** (assets `r1_NN`/`r2_NN`
  en `Maraton/Assets.xcassets`, importadas del PDF/web del plan) vía el campo
  `Exercise.imageName`. Están en `StrengthSeed`; `populateIfNeeded` (**v7**)
  refresca por completo la rutina de un día de fuerza del nuevo plan que aún no
  tenga nada registrado (respeta lo que el usuario cargó), **sólo para días del
  9/6/2026 en adelante** (piso `newPlanCutoff`); los anteriores conservan lo que
  tenían. Las fotos se muestran en `GymSessionView` (miniatura, `ExerciseThumbnail`)
  y en `GuidedGymSessionView` (imagen grande). Cada `ExerciseTemplate` tiene flag
  `weighted`: los de peso corporal/banda/core/equilibrio/salto no llevan peso
  (`StrengthSeed.bodyweightExerciseNames` + `Exercise.tracksWeight`). En las
  semanas de **pico** (15-21/6) y **taper** (29/6-5/7), `templates(for:)` **omite
  los ejercicios de salto** (paracaidista / step a una pierna). Migraciones
  puntuales de `WorkoutSeed` (cada una corre 1 vez, con su clave en UserDefaults):
  `applyThursdayGymSwapIfNeeded` (semana del 4-5/6/2026: jueves a gimnasio Fuerza B,
  calidad al viernes) y **`applyNewStructureIfNeeded`** (pone los días del **8/6 en
  adelante** con la estructura/calidades nuevas, sin tocar nada ≤ 7/6; preserva
  progreso y no cambia tipos).
- **Carga de series por rueda (estilo alarma), sin teclado:** en `GymSessionView`
  (`SetRow`) y `GuidedGymSessionView` (`LoggingCard`) el peso/reps/segundos se
  eligen tocando un chip que abre una hoja con ruedas (`WeightWheelField` —kg +
  fracción— y `CountWheelField` —reps o segundos según `Exercise.isTimeBased`—,
  ambos en `GymSessionView.swift`). El campo de **peso se oculta** en ejercicios
  sin peso (`Exercise.tracksWeight`).
- Dashboard en 3 tabs: **Detalle** (vista de un día del plan, deslizable entre
  todos los días o saltando desde la tira de la semana; muestra qué toca, datos de
  la semana de ese día, última corrida y suplementos del día —permite marcar
  suplementos de días pasados—), **Plan** (editable: crear/editar/borrar días),
  **Progreso** (consistencia, proyección, evolución de fuerza, suplementos +
  **generar reporte PDF**).
- Suplementos (creatina, proteína): marcado diario, adherencia, rachas y
  recordatorios locales configurables.
- **Reporte de progreso (PDF) para el profe:** botón en Progreso que junta
  adherencia al plan, corridas (km, ritmo, proyección, últimas corridas), fuerza
  (sesiones + mejores series), suplementos, y métricas de **Apple Salud / Fitness**
  (FC en reposo, HRV, VO₂máx, peso, sueño y resumen de entrenamientos), y lo
  comparte como PDF. Render con `ReportView` + `ImageRenderer`→PDF; se comparte vía
  `ShareLink` con un `Transferable` de tipo `.pdf` (`ReportPDFFile`) y miniatura
  de la 1ª página (PDFKit). Los datos se arman en `ProgressReportBuilder`
  (`ProgressReport.swift`) y las métricas de Salud en `HealthManager.snapshot(from:to:)`.

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
  sesión de gimnasio guiada, **compartida iPhone ↔ reloj**; al terminar el descanso
  no avanza solo: cuenta *tiempo extra* en rojo y re-vibra cada 10 s hasta que el
  usuario confirma la próxima serie con `skipRest`) y `AppData` (schema,
  creación del `ModelContainer` y sembrado; dueño del flag `iCloudSyncEnabled`).
- `Maraton/` — app iOS/Catalyst (solo target Maraton). `Maraton/Views/` (`RootView`,
  `DayDetailView` —tab "Detalle": carrusel `TabView`(.page) de todos los días del plan—,
  `WeekStripView` —tira de la semana del día seleccionado, salta al tocar—, `PlanView`,
  `WorkoutDetailView`, `WorkoutEditView`, `GymSessionView`, `GuidedGymSessionView`,
  `SupplementsTodayCard` —acepta una fecha, no solo hoy—, `ReportView` —documento +
  generación de PDF + hoja de compartir—, etc.), `MaratonApp`, y helpers iOS
  (`HealthManager`, `NotificationManager`, `RaceProjection`, `StreakCalculator`,
  `StrengthProgress`, `SupplementTracker`, `ProgressReport` —modelo + constructor del
  reporte—, `WeekAssigner`, `PreviewData`).
- `MaratonWatch Watch App/` — app del reloj (solo target watchOS). `MaratonWatchApp`,
  `WatchTodayView` (carrusel deslizable de días del plan que arranca en hoy: qué toca
  + suplementos por día, reutiliza `DailyPlanInfo`/`SupplementTracker`), `WatchWorkoutView`
  (detalle del día + Empezar en días de fuerza), `WatchGuidedSessionView` (peso/reps se
  editan **tocando el valor** para "agarrarlo" con la corona digital —sin selección la
  corona hace scroll; el foco se arma en dos pasos `armed`→`focused` porque watchOS
  descarta el foco si la celda no era focusable en el render previo—; descanso con tiempo
  extra en rojo y vibración; pulso en vivo), `WatchWorkoutManager` (pulso/calorías en vivo
  vía `HKWorkoutSession` y, al terminar, guarda el `HKWorkout` de fuerza en Apple Salud),
  `Info.plist`, `MaratonWatch.entitlements`, `Assets` (incluye el `AppIcon`, el mismo PNG
  1024² del iPhone).
- Proyecto usa **PBXFileSystemSynchronizedRootGroup**: los archivos nuevos en una
  carpeta se agregan solos a los targets que la incluyen (no hace falta editar el
  `.pbxproj`). El `Info.plist` del reloj queda excluido de recursos vía
  `membershipExceptions` (si no, choca con `INFOPLIST_FILE`).

## Build / deploy (CLI)
- **iPhone físico:** "iPhone de Ariel", iPhone 15 Pro, UDID hardware
  `<UDID-IPHONE>` (id CoreDevice `<COREDEVICE-ID-IPHONE>`,
  el que toma `devicectl`/`-destination 'id=…'`).
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
      -destination 'platform=watchOS Simulator,name=Apple Watch Series 7 (45mm)' \
      -configuration Debug -derivedDataPath /tmp/maraton-watch build
    xcrun simctl boot "Apple Watch Series 7 (45mm)"
    xcrun simctl install booted \
      "/tmp/maraton-watch/Build/Products/Debug-watchsimulator/MaratonWatch Watch App.app"
    xcrun simctl launch booted ariel.Maraton.watchkitapp
    ```
  - El **pulso en vivo** real necesita un **Apple Watch físico emparejado** (el
    simulador no genera HR real). Las métricas (HR prom., calorías, duración) se
    guardan en el `WorkoutDay` del día (campos `avgHeartRate`/`activeCalories`/
    `durationMinutes`), igual que el import de Apple Salud del iPhone.
  - Al terminar la sesión se **guarda como entrenamiento** (`HKWorkout` de fuerza
    en interior) en Apple Salud, con pulso y calorías. El permiso de **escritura**
    incluye `workoutType` + `heartRate` + `activeEnergyBurned` (si solo se comparte
    `workoutType`, el workout se guarda pero sin FC ni calorías asociadas).
  - ⚠️ Al cambiar el **`AppIcon` del reloj** hay que recompilar **limpio**
    (`clean build`): el build incremental no reprocesa el icono y el `Info.plist`
    queda sin `CFBundleIconName` (la app aparece sin icono).
  - Catalyst no compila el reloj gracias a `platformFilter = ios` en la dependencia
    y en la fase "Embed Watch Content".
  - **Instalar en el Apple Watch físico** ("Apple Watch de Ariel", Series 7 45mm,
    UDID hardware `<UDID-RELOJ>`, id CoreDevice
    `<COREDEVICE-ID-RELOJ>`):
    - ⚠️ Primero la Mac tiene que **poder conectarse al reloj**: abrir Xcode →
      Window → Devices and Simulators → seleccionar el reloj → "Preparing for
      development" hasta que figure disponible (misma Wi-Fi, reloj desbloqueado y
      cerca del iPhone). Si la Mac no lo "ve", el reloj sale como destino *no
      elegible* con la versión de watchOS en blanco y la firma no lo registra.
    - Con el reloj ya disponible:
      ```sh
      xcodebuild -project Maraton.xcodeproj -scheme "MaratonWatch Watch App" \
        -destination 'id=<UDID-RELOJ>' -configuration Debug \
        -derivedDataPath /tmp/maraton-watch-dev -allowProvisioningUpdates build
      xcrun devicectl device install app --device <COREDEVICE-ID-RELOJ> \
        "/tmp/maraton-watch-dev/Build/Products/Debug-watchos/MaratonWatch Watch App.app"
      xcrun devicectl device process launch --device <COREDEVICE-ID-RELOJ> \
        ariel.Maraton.watchkitapp
      ```
    - Cuenta gratuita ⇒ la firma **vence a los 7 días**; se reinstala con los
      mismos comandos. La primera vez puede pedir confiar el perfil de desarrollo
      en el reloj (Ajustes → General → Gestión de dispositivos y VPN → Confiar).
    - El pulso en vivo **sí** funciona en el reloj físico (en el simulador no).

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
