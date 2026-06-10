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
- **Exportar el plan a PDF (para compartir con amigos):** botón de compartir en
  la tab **Plan** (`PlanView`, arriba a la izquierda) que abre `PlanExportSheet`.
  Arma un PDF con el plan completo semana por semana (encabezado de la carrera +
  cada día con ícono/color por tipo, título y detalle). Misma maquinaria que el
  reporte: `PlanExportView` + `ImageRenderer`→PDF (`PlanPDF`, página continua) y
  `ShareLink` con un `Transferable` `.pdf` (`PlanPDFFile`) + miniatura PDFKit.
  Todo en `Maraton/Views/PlanExportView.swift`.
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
  - ✅ **Cuenta de pago (Apple Developer Program) ⇒ la firma dura 1 año**, ya no
    se vence a los 7 días (era así con la cuenta gratuita). Igual la primera vez
    tras instalar puede pedir **confiar el perfil** en el iPhone (Ajustes →
    General → VPN y gestión de dispositivos → App de desarrollador → Confiar); si
    no, al lanzar da `invalid code signature / profile has not been explicitly
    trusted`.
  - ⚠️ La firma automática (`-allowProvisioningUpdates`) **necesita la cuenta de
    Apple ID logueada en Xcode** (Settings → Accounts: `<TU-APPLE-ID>`,
    team `96B9D6W2NW`, ahora con membresía de pago). Sin cuenta, el build falla con `No Accounts` /
    `No profiles for 'ariel.Maraton' were found`. La identidad de firma vive en el
    llavero (`Apple Development: <TU-APPLE-ID>`).
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
    - Con la cuenta de pago la firma **dura 1 año** (antes, gratuita, vencía a los
      7 días). La primera vez puede pedir confiar el perfil de desarrollo en el
      reloj (Ajustes → General → Gestión de dispositivos y VPN → Confiar).
    - El pulso en vivo **sí** funciona en el reloj físico (en el simulador no).

## Pendientes / próximos pasos posibles
- ✅ iCloud **funcionando** iPhone ↔ Mac (9/6/2026, cuenta de pago) — ver sección abajo.
- ⌚ **Reloj con iCloud: pendiente de redesplegar.** El device estaba `unavailable`;
  comparte el mismo `AppData`/entitlements, así que sólo falta recompilar e instalar
  la build nueva cuando esté disponible (ver sección del reloj).
- La `.app` de Mac (dev) se dejó en **`/Applications/Maraton.app`** para abrirla desde
  Spotlight/Launchpad; al recompilar hay que volver a copiarla ahí (el build sale a `/tmp`).
- Posibles mejoras pedidas pero no hechas: ritmo objetivo en la tarjeta "Hoy",
  más suplementos, dosis/cantidad por suplemento.

## 🚀 Publicación en App Store (EN CURSO — arrancado 10/6/2026)
Decisiones tomadas: publicar **iPhone + Apple Watch** (el reloj viaja embebido, NO
se publica la versión Mac Catalyst) y subir **a TestFlight primero**, probar la sync
de CloudKit **Producción** instalada desde la nube y recién después enviar a revisión.

Estado: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` (sirve para el 1er
release). Bundle iOS `ariel.Maraton`, reloj `ariel.Maraton.watchkitapp`. Icono 1024²
y textos de uso de HealthKit (iOS + reloj) ya están.

### Ya hecho
- ✅ Declarada la **exención de criptografía**: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`
  en el target iOS (Debug y Release) en `project.pbxproj`. Evita la pregunta de
  export compliance en cada envío (la app solo usa HTTPS/cripto estándar exenta).

### Pendiente (próxima sesión) — manual salvo lo marcado
1. ⚠️ **CRÍTICO: promocionar el schema de CloudKit a Production.**
   icloud.developer.apple.com → contenedor `iCloud.ariel.Maraton` → Schema →
   **Deploy Schema to Production**. Las builds de distribución de iOS usan el
   contenedor de **Producción** (lo elige el perfil de distribución), que arranca
   **vacío**. Sin esto, la app de TestFlight/Store **no sincroniza**. Es el riesgo
   que queremos verificar en TestFlight antes de publicar.
2. ⚠️ **Política de privacidad (URL).** Apple la **exige** por usar HealthKit. Hay
   que hostearla (GitHub Pages / Notion público / etc.). *Claude puede redactarla*
   (es-AR; datos 100% locales + iCloud propio del usuario, sin servidores propios)
   — falta definir dónde se hospeda.
3. **Crear la ficha** en App Store Connect (Apps → + → iOS, bundle `ariel.Maraton`).
   ⚠️ El **nombre de la ficha debe ser único global**; "Maratón" casi seguro está
   tomado. El nombre en el ícono puede seguir siendo "Maratón", pero el de la Store
   quizá deba ser p.ej. "Maratón — Plan 21K". Definir 2-3 alternativas.
4. **Metadata** (subtítulo, descripción, keywords, categoría) — *Claude puede
   redactarla*. **Screenshots** los captura Ariel (iPhone 6.9"/6.5"; reloj opcional).
5. **Archive + subida** (Xcode, firma de distribución): scheme `Maraton`, destino
   *Any iOS Device* → Product → Archive → Organizer → Distribute App → App Store
   Connect → Upload (que regenere el perfil de distribución).
6. **Probar en TestFlight** (verificar CloudKit Producción end-to-end) → completar
   ficha → **Submit for Review**.

Notas/riesgos: el entitlement `aps-environment = development` NO es bloqueante
(Xcode lo reescribe a `production` al firmar con perfil de distribución). El
entitlement de Catalyst sigue en `icloud-container-environment = Development`, pero
como NO se publica Mac, no se toca.

## ✅ Sincronización iCloud (FUNCIONANDO — 9/6/2026, cuenta de pago, team 96B9D6W2NW)
iPhone y Mac sincronizan vía el contenedor CloudKit compartido
`iCloud.ariel.Maraton` (mismo container en los tres targets). Verificado end-to-end:
la data del iPhone (40 días / 133 ejercicios / 405 series / 12 suplementos) bajó
completa a la Mac. Se activó al pasar la cuenta `<TU-APPLE-ID>` al
**Apple Developer Program de pago**. El **reloj** comparte el mismo `AppData` y
entitlements; queda **pendiente** sólo redesplegar la build nueva cuando el device
esté disponible. Para revertir: `AppData.iCloudSyncEnabled = false` (vuelve a store
local en todos los dispositivos).

### Qué se tocó para activarlo (todo ya aplicado)
1. **Entitlements** iOS (`Maraton.entitlements`), Mac Catalyst (`Maraton-Catalyst.entitlements`)
   y reloj (`MaratonWatch.entitlements`): `aps-environment` (`development`),
   `com.apple.developer.icloud-container-identifiers` (`iCloud.ariel.Maraton`),
   `com.apple.developer.icloud-services` (`CloudKit`),
   `com.apple.developer.ubiquity-kvstore-identifier`. En **Catalyst** además
   `com.apple.developer.icloud-container-environment = Development` y
   `com.apple.security.network.client` (app sandbox; sin el `network.client`
   CloudKit no llega al server).
2. `project.pbxproj` (Debug y Release del target iOS):
   `INFOPLIST_KEY_UIBackgroundModes = "remote-notification";`.
3. **Modelo apto para CloudKit** (`WorkoutDay`, `Exercise`, `ExerciseSet`, …):
   - sin `@Attribute(.unique)` (se quitó de `WorkoutDay.date`; la unicidad por
     fecha la valida el código en `WorkoutSeed`).
   - **TODAS las relaciones opcionales, incluidas las to-many.** Esto fue el bug
     central: `WorkoutDay.exercises` y `Exercise.sets` eran `[T] = []` (no
     opcionales) y CloudKit las rechazaba con *"CloudKit integration requires that
     all relationships be optional"* → `SwiftDataError.loadIssueModelContainer`, y
     `AppData.makeContainer()` caía a store **local** en silencio. Se pasaron a
     `[T]?` y se lee siempre por `orderedExercises` / `orderedSets`.
4. `AppData.iCloudSyncEnabled = true`. `makeContainer()` loguea el error real si
   CloudKit falla (subsistema `ariel.Maraton`) en vez de tragárselo.
5. Compilar para device con `-allowProvisioningUpdates` (registra el contenedor y
   Push). La Mac además hay que **registrarla** una vez desde Xcode (Run → "Register
   this Mac…"); por CLI no se puede.

### ⚠️ Gotchas aprendidos (para no repetir el día del reloj o de otra capability)
- **Contenedor recién creado = propagación lenta.** Con la cuenta de pago activada
  *ese mismo día*, el server de CloudKit rechazaba crear la zona
  (`CKError 15 "Server Rejected Request"`) aunque la cuenta autenticaba bien. Se
  destrabó al **abrir el contenedor en la consola** (icloud.developer.apple.com →
  `iCloud.ariel.Maraton` → Development) y esperar un rato. No es un bug del código.
- **El sembrado usa iCloud KVS como flag de "ya sembrado".** Con sync activa, sólo
  un dispositivo siembra; los demás reciben la data por CloudKit. Si se borra el
  store local pero queda el flag KVS, ese dispositivo arranca **vacío** hasta que
  importe de CloudKit (es lo esperado, no un error).
- **El log de la Mac de esta sesión venía vacío** porque el shell tiene una función
  `log`; usar **`/usr/bin/log show ... --predicate 'process == "Maraton"'`**.
- Resolución de conflictos: estándar de CloudKit (last-writer-wins). Migración:
  lightweight de SwiftData (cambiar to-many a opcional es compatible).
