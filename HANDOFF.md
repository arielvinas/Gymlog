# GymLog — Handoff

App nativa (SwiftUI + SwiftData) para registrar entrenamiento continuo: gimnasio +
running. Corre en **iPhone, Apple Watch y Mac (Catalyst)**. Offline, español (es-AR),
light/dark. Sincroniza por iCloud entre los tres.

> **Pivot (julio 2026).** Nació como app para preparar la Media Maratón de Córdoba
> (21,1 km, 5/7/2026) y se reorientó a entrenamiento continuo. Se sacó todo lo que
> dependía de una fecha de carrera fija: proyección de tiempos, cuenta regresiva,
> encabezados de carrera en los PDFs. En su lugar el dashboard muestra **volumen
> semanal** (km + kilos). El nombre visible es **GymLog**, pero el proyecto, el target
> y el bundle id siguen siendo `Maraton` / `ariel.Maraton` a propósito: renombrarlos
> rompe el historial de la app instalada y su contenedor de CloudKit.

## Estado general

- **Plan de entrenamiento** con seed versionado + reconciliación. Ver "El plan sembrado"
  abajo: ⚠️ el plan canónico **se terminó el 5/7/2026** y no hay días nuevos.
- **Rutina de gimnasio** (ejercicios / series / peso). Las plantillas Fuerza A y Fuerza B
  son los dos días del **plan de Megatlón** (entrenador Francisco Ambrosio): cada uno
  arranca con circuito de acondicionamiento + específico (3 vueltas) y sigue con el
  bloque principal de fuerza. Están en `StrengthSeed`. Cada ejercicio lleva su **foto**
  (assets `r1_NN` / `r2_NN` en `Maraton/Assets.xcassets`, importadas del PDF del plan)
  vía `Exercise.imageName`; se ven como miniatura en `GymSessionView` y en grande en
  `GuidedGymSessionView`. Cada `ExerciseTemplate` tiene flag `weighted`: los de peso
  corporal / banda / core / equilibrio / salto no llevan peso
  (`StrengthSeed.bodyweightExerciseNames` + `Exercise.tracksWeight`).
- **Carga de series por rueda (estilo alarma), sin teclado:** en `GymSessionView`
  (`SetRow`) y `GuidedGymSessionView` (`LoggingCard`) el peso / reps / segundos se eligen
  tocando un chip que abre una hoja con ruedas (`WeightWheelField` —kg + fracción— y
  `CountWheelField` —reps o segundos según `Exercise.isTimeBased`—, ambos en
  `GymSessionView.swift`). El campo de peso se oculta en ejercicios sin peso.
- **Series pre-cargadas (sesión guiada):** al llegar a cada serie, el engine
  (`GuidedSessionEngine.prefillCurrentSet`) la pre-completa: **reps** = objetivo del plan
  (número más alto del rango, ej. "6-8" → 8) y **peso** = el de la serie previa de la
  sesión, o el último usado en el ejercicio (`ExerciseHistory.lastWeight`, el más pesado
  de la última sesión). Solo completa lo vacío (nunca pisa lo cargado). Vale para reloj +
  iPhone guiado + Live Activity.
- **Cambiar el próximo ejercicio (sesión guiada):** botón "Cambiar ejercicio" (en carga y
  descanso, reloj e iPhone) que abre la lista de pendientes; el elegido pasa a ser el
  próximo (`GuidedSessionEngine.bringExerciseNext` reordena los `Exercise.order` y
  preserva la posición y lo registrado). Para cuando la máquina del que seguía está
  ocupada y se intercala otro del plan.
- **Corridas desde Apple Salud** (HealthKit): km, ritmo, pulso, calorías, asociadas al día
  del plan. También importa métricas de sesiones de fuerza.
- Dashboard en 3 tabs: **Detalle** (un día del plan, deslizable entre todos los días o
  saltando desde la tira de la semana; muestra qué toca, datos de la semana de ese día,
  última corrida y suplementos del día —permite marcar suplementos de días pasados—),
  **Plan** (editable: crear / editar / borrar días), **Progreso** (volumen de la semana,
  tendencia de 6 semanas, consistencia, evolución de fuerza, suplementos + **generar
  reporte PDF**).
- **Volumen semanal** (`WeeklyVolume`, reemplazo de la vieja proyección de carrera):
  `actualKm` (km corridos) y `tonnage` (Σ peso × reps de cada serie; las series sin peso
  o sin reps no suman). `recentWeeks(6)` arma la tendencia que dibuja `VolumeTrendCard`.
  Las dos barras de cada semana se escalan a **su propio máximo**, porque km y kg no son
  comparables entre sí.
- **Suplementos** (creatina, proteína): marcado diario, adherencia, rachas y recordatorios
  locales configurables.
- **Exportar el plan a PDF:** botón de compartir en la tab **Plan** (`PlanView`, arriba a
  la izquierda) que abre `PlanExportSheet`. Arma el plan completo semana por semana (cada
  día con ícono / color por tipo, título y detalle). `PlanExportView` +
  `ImageRenderer`→PDF (`PlanPDF`, página continua) y `ShareLink` con un `Transferable`
  `.pdf` (`PlanPDFFile`) + miniatura PDFKit.
- **Reporte de progreso (PDF) para el profe:** botón en Progreso que junta adherencia al
  plan, corridas (km, ritmo, últimas corridas), fuerza (sesiones + mejores series),
  suplementos, y métricas de **Apple Salud** (FC en reposo, HRV, VO₂máx, peso, sueño y
  resumen de entrenamientos). Datos en `ProgressReportBuilder` (`ProgressReport.swift`) y
  métricas de Salud en `HealthManager.snapshot(from:to:)`.
- **Exportar un día (PDF):** desde el menú ⋯ de `WorkoutDetailView` → "Compartir día". En
  días de fuerza arma una tabla de **peso × reps por serie** de cada ejercicio + volumen
  por ejercicio y total; en corridas, km / ritmo / FC / calorías / esfuerzo
  (`DayExportView.swift`).
- **Sesión guiada en vivo reloj→iPhone + Live Activity (lock screen / Dynamic Island):**
  al empezar la sesión guiada en el **Apple Watch**, se ve y controla en vivo desde el
  iPhone. El **reloj es la autoridad** (corre el engine, muta SwiftData); el iPhone es
  **espejo + control remoto**. Transporte = **WatchConnectivity**
  (`Shared/LiveSession/LiveSessionConnectivity.swift`): `sendMessage` en vivo +
  `transferUserInfo` durable (despierta la app iOS en background) +
  `updateApplicationContext`. El reloj difunde `LiveSessionSnapshot` en cada
  `onStateChanged`; el iPhone manda `LiveSessionCommand`. En la app: banner +
  `LiveSessionMirrorView` (Hecho / Saltear / ±15 / Anterior). En pantalla bloqueada:
  **Live Activity** (target `MaratonLiveActivity`) con cronómetro nativo
  `Text(timerInterval:)` y botones interactivos (`AdvanceSetIntent` / `SkipRestIntent`; su
  `perform()` corre en el proceso de la app y rutea el comando al reloj). Sin servidor ⇒
  los avances con el teléfono bloqueado llegan por wake de WC (≈1-2 s), el cronómetro
  corre solo. Ver memoria [[live-activity-sync]].
- **Versión Mac (Mac Catalyst):** mismo target. Barra lateral (`NavigationSplitView`),
  ventana redimensionable, menú "Ir a" con atajos ⌘1/⌘2/⌘3. Apple Salud se oculta en Mac
  (no existe). UI adaptable en `RootView.swift` (`#if targetEnvironment(macCatalyst)`).

## Estructura del código

Cuatro targets / carpetas (grupos sincronizados):

- `Shared/` — **código agnóstico de plataforma, compilado por iOS Y watchOS** (y el
  subgrupo `Shared/LiveSession/` también por la extensión). Modelos SwiftData
  (`WorkoutDay`, `Exercise`, `ExerciseSet`, `SupplementLog`, `SupplementReminder`),
  helpers (`WorkoutSeed`, `StrengthSeed`, `ExerciseHistory`, `PlanConstants`,
  formateadores), `GuidedSessionEngine` (máquina de estados de la sesión de gimnasio
  guiada, **compartida iPhone ↔ reloj**; al terminar el descanso no avanza solo: cuenta
  *tiempo extra* en rojo y re-vibra cada 10 s hasta que el usuario confirma la próxima
  serie con `skipRest`) y `AppData` (schema, creación del `ModelContainer` y sembrado;
  dueño del flag `iCloudSyncEnabled`).
- `Maraton/` — app iOS/Catalyst. `Maraton/Views/` (`RootView`, `DayDetailView` —carrusel
  `TabView`(.page) de todos los días—, `WeekStripView`, `PlanView`, `WorkoutDetailView`,
  `WorkoutEditView`, `GymSessionView`, `GuidedGymSessionView`, `SupplementsTodayCard`,
  `ReportView`, `PlanExportView`, `DayExportView`, `DashboardCards`, etc.), `MaratonApp`,
  y helpers iOS (`HealthManager`, `NotificationManager`, `LiveActivityController`,
  `StreakCalculator`, `StrengthProgress`, `SupplementTracker`, `ProgressReport`,
  `WeeklyVolume`, `WeekAssigner`, `PreviewData`).
- `MaratonWatch Watch App/` — app del reloj (solo watchOS). `WatchTodayView` (carrusel de
  días que arranca en hoy), `WatchWorkoutView` (detalle + Empezar en días de fuerza),
  `WatchGuidedSessionView` (peso / reps se editan **tocando el valor** para "agarrarlo"
  con la corona digital —sin selección la corona hace scroll; el foco se arma en dos pasos
  `armed`→`focused` porque watchOS descarta el foco si la celda no era focusable en el
  render previo—; descanso con tiempo extra en rojo y vibración; pulso en vivo),
  `WatchWorkoutManager` (pulso / calorías vía `HKWorkoutSession` y, al terminar, guarda el
  `HKWorkout` de fuerza en Apple Salud).
- `MaratonLiveActivity/` — **Widget Extension** (bundle `ariel.Maraton.LiveActivity`),
  embebida en la app iOS. Solo dibuja la Live Activity y declara los `LiveActivityIntent`.
  Su target incluye el grupo `Shared`. Se agregó **editando `project.pbxproj` a mano**
  (UUIDs `DA7A0002…`).
- Proyecto usa **PBXFileSystemSynchronizedRootGroup**: los archivos nuevos en una carpeta
  se agregan solos a los targets que la incluyen (no hace falta editar el `.pbxproj`). Los
  `Info.plist` del reloj y de la extensión quedan excluidos de recursos vía
  `membershipExceptions` (si no, chocan con `INFOPLIST_FILE`). Para un **target nuevo** sí
  hay que tocar el `.pbxproj`.

## El plan sembrado

Todo el sembrado corre desde `AppData.seed(context:)`:

| Función | Qué hace |
|---|---|
| `WorkoutSeed.seedIfNeeded` | Inserta el plan canónico en el primer arranque (solo si `storedVersion == 0` y no hay días) |
| `WorkoutSeed.applyPlanUpdates` | Inserta los días del plan canónico que falten **por fecha**, una vez por versión (`planVersion = 2`). No toca ni resucita lo que el usuario editó o borró |
| `StrengthSeed.populateIfNeeded` | Carga la rutina (Día A / Día B) en los días de fuerza **sin nada registrado**, de **9/6/2026 en adelante** (`newPlanCutoff`). Versión `7` |
| `WorkoutSeed.deduplicateDays` | Agrupa por fecha y conserva el día más "rico" (con datos), borra los vacíos. Determinístico e idempotente |
| `WorkoutSeed.cleanupKneeRecoveryIfNeeded` | Borra los días **vacíos** de la etapa de rodilla (24/6→5/7/2026). Los días con entrenamiento real, incluida la carrera del 5/7, se conservan como historial |

**El flag de "ya sembré" vive en iCloud KVS** (`NSUbiquitousKeyValueStore`) además de
`UserDefaults`, para no re-sembrar al reinstalar o estrenar un dispositivo.

⚠️ **Regla general:** todo lo que **cree o borre registros** como parte de una migración
debe correr en **un solo dispositivo** (guardado con
`#if os(iOS) && !targetEnvironment(macCatalyst)`) — un único ejecutor evita carreras, y las
bajas se propagan por CloudKit. Modificar campos escalares sí es seguro en todos
(last-writer-wins). Por eso `deduplicateDays` y `cleanupKneeRecoveryIfNeeded` corren solo
en el iPhone.

### ⚠️ Deuda: el plan se quedó sin días

El plan canónico de `WorkoutSeed.plan` **termina el 5/7/2026** (el día de la carrera). No
hay días sembrados después de esa fecha, así que la app —que ahora es de entrenamiento
continuo— se quedó sin plan. Es lo próximo a resolver. Opciones:

- sembrar un plan recurrente (una semana tipo que se repite), en vez de una lista fija de
  fechas; o
- que el usuario arme su semana desde la tab Plan (ya es editable) y el seed solo aporte
  plantillas.

Quedan además dos restos del plan de carrera en `StrengthSeed`, hoy inertes porque sus
fechas ya pasaron: `omitsJumps(on:)` (saca los ejercicios de salto en las semanas de pico
15-21/6 y taper 29/6-5/7) y `taperVariant(of:)` (mitad de series, sin pierna, para los días
titulados "liviana"). Si el plan pasa a ser recurrente, hay que decidir si se borran o se
re-anclan a algo que no sea una fecha fija.

## Build / deploy (CLI)

Requiere el **platform de watchOS** instalado (`xcodebuild -downloadPlatform watchOS`).
Como el target iOS **embebe** el reloj, sin el platform **tampoco compila el iPhone**.

> **Los identificadores están como placeholders** (`<UDID-IPHONE>`, `<TU-APPLE-ID>`, …)
> porque el repo es público y son datos personales. Para conseguir los tuyos:
> `xcrun devicectl list devices` lista los dispositivos emparejados con su UDID de
> hardware y su id de CoreDevice (el que toma `devicectl` y `-destination 'id=…'`).

- **iPhone físico:** "iPhone de Ariel", iPhone 15 Pro, UDID hardware
  `<UDID-IPHONE>` (id CoreDevice `<COREDEVICE-ID-IPHONE>`, el
  que toma `devicectl` / `-destination 'id=…'`).
  ```sh
  xcodebuild -project Maraton.xcodeproj -scheme Maraton \
    -destination 'platform=iOS,name=iPhone de Ariel' -configuration Debug \
    -derivedDataPath /tmp/maraton-device -allowProvisioningUpdates build
  xcrun devicectl device install app --device <UDID-IPHONE> \
    /tmp/maraton-device/Build/Products/Debug-iphoneos/Maraton.app
  xcrun devicectl device process launch --device <UDID-IPHONE> ariel.Maraton
  ```
  Requiere el teléfono **desbloqueado** y el perfil de desarrollador confiado (Ajustes →
  General → VPN y gestión de dispositivos).
  - ✅ **Cuenta de pago (Apple Developer Program) ⇒ la firma dura 1 año**, ya no se vence a
    los 7 días. Igual la primera vez tras instalar puede pedir **confiar el perfil**; si
    no, al lanzar da `invalid code signature / profile has not been explicitly trusted`.
  - ⚠️ La firma automática (`-allowProvisioningUpdates`) **necesita la cuenta de Apple ID
    logueada en Xcode** (Settings → Accounts: `<TU-APPLE-ID>`, team
    `96B9D6W2NW`). Sin cuenta el build falla con `No Accounts` / `No profiles for
    'ariel.Maraton' were found`. La identidad de firma vive en el llavero.
- **Simulador:** iPhone 15 Pro (creado a mano; el Xcode trae sólo serie 17).
- **Mac (Catalyst), prueba local sin cuenta** (firma ad-hoc "Sign to Run Locally"):
  ```sh
  xcodebuild -project Maraton.xcodeproj -scheme Maraton \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug \
    -derivedDataPath /tmp/maraton-catalyst \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="" DEVELOPMENT_TEAM="" build
  open /tmp/maraton-catalyst/Build/Products/Debug-maccatalyst/Maraton.app
  ```
- **Apple Watch (companion):** bundle `ariel.Maraton.watchkitapp`, embebido en la app iOS.
  - Simulador:
    ```sh
    xcodebuild -project Maraton.xcodeproj -scheme "MaratonWatch Watch App" \
      -destination 'platform=watchOS Simulator,name=Apple Watch Series 7 (45mm)' \
      -configuration Debug -derivedDataPath /tmp/maraton-watch build
    xcrun simctl boot "Apple Watch Series 7 (45mm)"
    xcrun simctl install booted \
      "/tmp/maraton-watch/Build/Products/Debug-watchsimulator/MaratonWatch Watch App.app"
    xcrun simctl launch booted ariel.Maraton.watchkitapp
    ```
  - El **pulso en vivo** real necesita un **Apple Watch físico** (el simulador no genera HR
    real). Las métricas (HR prom., calorías, duración) se guardan en el `WorkoutDay` del
    día, igual que el import de Apple Salud del iPhone.
  - Al terminar la sesión se **guarda como entrenamiento** (`HKWorkout` de fuerza en
    interior) en Apple Salud, con pulso y calorías. El permiso de **escritura** incluye
    `workoutType` + `heartRate` + `activeEnergyBurned` (si solo se comparte `workoutType`,
    el workout se guarda pero sin FC ni calorías asociadas).
  - ⚠️ Al cambiar el **`AppIcon` del reloj** hay que recompilar **limpio** (`clean build`):
    el build incremental no reprocesa el icono y el `Info.plist` queda sin
    `CFBundleIconName` (la app aparece sin icono).
  - Catalyst no compila el reloj gracias a `platformFilter = ios` en la dependencia y en la
    fase "Embed Watch Content".
  - **Instalar en el reloj físico** ("Apple Watch de Ariel", Series 7 45mm, UDID hardware
    `<UDID-RELOJ>`, id CoreDevice `<COREDEVICE-ID-RELOJ>`):
    - ⚠️ Primero la Mac tiene que **poder conectarse al reloj**: Xcode → Window → Devices
      and Simulators → seleccionar el reloj → "Preparing for development" hasta que figure
      disponible (misma Wi-Fi, reloj desbloqueado y cerca del iPhone). Si la Mac no lo
      "ve", el reloj sale como destino *no elegible* con la versión de watchOS en blanco.
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
    - ⚠️ Para instalar por CLI el **reloj tiene que estar DESBLOQUEADO** (si no:
      `kAMDMobileImageMounterDeviceLocked`). Si `-destination 'id=…'` tira "developer disk
      image could not be mounted", compilar con `-destination 'generic/platform=watchOS'` y
      después `devicectl device install` (monta la DDI por su cuenta). Lanzar por CLI puede
      fallar si el reloj está en la esfera ("Navigation away from clock not allowed"):
      abrir la app a mano en el reloj.

## ✅ Sincronización iCloud (funcionando)

iPhone, Mac y reloj sincronizan vía el contenedor CloudKit `iCloud.ariel.Maraton` (mismo
container en los tres targets). Verificado end-to-end. Para revertir a store local:
`AppData.iCloudSyncEnabled = false`.

### Qué se tocó para activarlo (todo ya aplicado)

1. **Entitlements** iOS (`Maraton.entitlements`), Catalyst (`Maraton-Catalyst.entitlements`)
   y reloj (`MaratonWatch.entitlements`): `aps-environment` (`development`),
   `com.apple.developer.icloud-container-identifiers` (`iCloud.ariel.Maraton`),
   `com.apple.developer.icloud-services` (`CloudKit`),
   `com.apple.developer.ubiquity-kvstore-identifier`. En **Catalyst** además
   `com.apple.developer.icloud-container-environment = Development` y
   `com.apple.security.network.client` (sin el `network.client`, CloudKit no llega al
   server).
2. `project.pbxproj` (Debug y Release del target iOS):
   `INFOPLIST_KEY_UIBackgroundModes = "remote-notification";`.
3. **Modelo apto para CloudKit** (`WorkoutDay`, `Exercise`, `ExerciseSet`, …):
   - sin `@Attribute(.unique)` (se quitó de `WorkoutDay.date`; la unicidad por fecha la
     valida el código en `WorkoutSeed`).
   - **TODAS las relaciones opcionales, incluidas las to-many.** Este fue el bug central:
     `WorkoutDay.exercises` y `Exercise.sets` eran `[T] = []` (no opcionales) y CloudKit
     las rechazaba con *"CloudKit integration requires that all relationships be
     optional"* → `SwiftDataError.loadIssueModelContainer`, y `AppData.makeContainer()`
     caía a store **local** en silencio. Se pasaron a `[T]?` y se lee siempre por
     `orderedExercises` / `orderedSets`.
4. `AppData.iCloudSyncEnabled = true`. `makeContainer()` loguea el error real si CloudKit
   falla (subsistema `ariel.Maraton`) en vez de tragárselo.
5. Compilar para device con `-allowProvisioningUpdates` (registra el contenedor y Push). La
   Mac además hay que **registrarla** una vez desde Xcode (Run → "Register this Mac…"); por
   CLI no se puede.

### ⚠️ Gotchas aprendidos

- **Contenedor recién creado = propagación lenta.** Con la cuenta de pago activada *ese
  mismo día*, el server rechazaba crear la zona (`CKError 15 "Server Rejected Request"`)
  aunque la cuenta autenticaba bien. Se destrabó al **abrir el contenedor en la consola**
  (icloud.developer.apple.com → `iCloud.ariel.Maraton` → Development) y esperar un rato. No
  era un bug del código.
- **Días duplicados por el KVS identifier.** El `ubiquity-kvstore-identifier` usaba
  `$(CFBundleIdentifier)`, que expandía distinto por app (iPhone `…ariel.Maraton` vs reloj
  `…ariel.Maraton.watchkitapp`); como el flag "ya sembré" vive en ese KVS, el reloj no veía
  el del iPhone y **sembraba su propia copia** del plan → dos registros por fecha. **Fix de
  raíz:** el reloj usa el **mismo** KVS identifier que el iPhone
  (`$(TeamIdentifierPrefix)ariel.Maraton`, hardcodeado). Apps y extensiones que compartan
  KVS entre iPhone y reloj deben declarar el **mismo** identifier hardcodeado, nunca
  `$(CFBundleIdentifier)`.
- **El sembrado usa el KVS como flag de "ya sembrado".** Con sync activa, sólo un
  dispositivo siembra; los demás reciben la data por CloudKit. Si se borra el store local
  pero queda el flag KVS, ese dispositivo arranca **vacío** hasta que importe de CloudKit
  (es lo esperado, no un error).
- **El log de la Mac sale vacío** si el shell tiene una función `log`; usar
  `/usr/bin/log show ... --predicate 'process == "Maraton"'`.
- Resolución de conflictos: estándar de CloudKit (last-writer-wins). Migración: lightweight
  de SwiftData (cambiar to-many a opcional es compatible).

## 🚀 Publicación en App Store (en curso)

Decisiones tomadas: publicar **iPhone + Apple Watch** (el reloj viaja embebido; NO se
publica la versión Mac Catalyst) y subir **a TestFlight primero**, probar la sync de
CloudKit **Producción** instalada desde la nube, y recién después enviar a revisión.

Estado: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`. Bundle iOS
`ariel.Maraton`, reloj `ariel.Maraton.watchkitapp`. Icono 1024² y textos de uso de
HealthKit (iOS + reloj) ya están.

**Ya hecho:** declarada la **exención de criptografía**
(`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` en el target iOS, Debug y Release).
Evita la pregunta de export compliance en cada envío.

**Pendiente:**

1. ⚠️ **CRÍTICO: promocionar el schema de CloudKit a Production.**
   icloud.developer.apple.com → contenedor `iCloud.ariel.Maraton` → Schema → **Deploy
   Schema to Production**. Las builds de distribución usan el contenedor de **Producción**
   (lo elige el perfil de distribución), que arranca **vacío**. Sin esto, la app de
   TestFlight/Store **no sincroniza**. Es el riesgo que queremos verificar en TestFlight
   antes de publicar.
2. ⚠️ **Política de privacidad (URL).** Apple la **exige** por usar HealthKit. Hay que
   hostearla (GitHub Pages / Notion público / etc.). Falta definir dónde.
3. **Crear la ficha** en App Store Connect (bundle `ariel.Maraton`). El **nombre de la
   ficha debe ser único global** — con el pivot el candidato es **GymLog**; verificar que
   esté libre y tener 2-3 alternativas de backup.
4. **Metadata** (subtítulo, descripción, keywords, categoría). **Screenshots** los captura
   Ariel (iPhone 6.9"/6.5"; reloj opcional).
5. **Archive + subida** (Xcode, firma de distribución): scheme `Maraton`, destino *Any iOS
   Device* → Product → Archive → Organizer → Distribute App → App Store Connect → Upload.
6. **Probar en TestFlight** (verificar CloudKit Producción end-to-end) → completar ficha →
   **Submit for Review**.

Notas: el entitlement `aps-environment = development` NO es bloqueante (Xcode lo reescribe
a `production` al firmar con perfil de distribución). El entitlement de Catalyst sigue en
`icloud-container-environment = Development`, pero como NO se publica Mac, no se toca.

## Pendientes / próximos pasos

- ⚠️ **El plan sembrado se acabó el 5/7/2026** — ver "Deuda" arriba. Es lo más urgente:
  hoy la app no tiene días futuros que mostrar.
- Restos del plan de carrera en `StrengthSeed` (`omitsJumps`, `taperVariant`) anclados a
  fechas fijas de junio/julio 2026: decidir si se borran o se re-anclan.
- La `.app` de Mac (dev) se dejó en **`/Applications/Maraton.app`** para abrirla desde
  Spotlight; al recompilar hay que volver a copiarla ahí (el build sale a `/tmp`).
- Mejoras pedidas y no hechas: más suplementos, dosis / cantidad por suplemento.
