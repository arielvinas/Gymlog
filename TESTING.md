# GymLog — Plan de pruebas

Estado actual: **cero tests, cero CI, cero hooks**. Este documento define qué probar, en qué
orden, y cuándo corre cada cosa. Es también el backlog: cada ítem tiene un ID estable y un
checkbox, para ir tachándolos de a uno.

## Estrategia

Tres niveles, con una regla de oro: **un test por comportamiento, no por método**. No buscamos
cobertura de líneas — buscamos que los invariantes que hoy sostienen la app a mano queden
escritos.

| Nivel | Qué prueba | Presupuesto |
|---|---|---|
| **Unit** | Lógica pura: parseo, cálculo, formateo, serialización | < 5 s |
| **Integración** | SwiftData en memoria: máquina de estados, seeds, wire | < 30 s |
| **E2E** | Recorridos de usuario sobre la app (XCUITest) | minutos |

Framework: **Swift Testing** (`@Test` / `#expect`), el default de Xcode 26. Para E2E, XCUITest.

Un build en caliente tarda **~13 s**, así que correr los tests localmente es barato. Eso
condiciona las decisiones de más abajo.

## Los 11 bugs que ya salieron de leer el código

Leer el código para diseñar los tests encontró once defectos **sin ejecutar nada**. Cada uno
tiene su test asignado. La regla: el test se escribe **primero para documentar el comportamiento
actual**; si confirma el bug, se arregla en un commit separado del test.

| # | Bug | Test |
|---|---|---|
| 1 | **`StrengthSeed.templates(for:)` matchea `title.contains("b")` sobre el título en minúsculas** → cualquier día con una "b" en cualquier parte ("Gimnasio **b**ásico", "Fuerza A · **B**loque") recibe la rutina del **Día B**. | U-18 |
| 2 | **`StreakCalculator.currentWeekStreak` agrupa por `weekTitle` (String), no por semana calendario** → dos semanas con el mismo título se fusionan; una semana partida en dos títulos cuenta doble. | U-32 |
| 3 | ~~**`GuidedSessionEngine`: con `restSeconds == 0`, `onStateChanged` nunca se emite al entrar en tiempo extra**~~ → **confirmado pero NO alcanzable.** El 0 no se puede producir hoy por ninguna ruta. Agujero de la lógica, no bug visible. Ver I-06. | I-06 ✅ |
| 4 | **Ráfaga de alertas al volver de background.** ✅ **CONFIRMADO** en I-07: vuelve con 35 s de tiempo extra → **4 vibraciones en <1 s**. Alcanzable a diario (el reloj apaga la pantalla y deja de tickear). **Pendiente de arreglar.** | I-07 ✅ |
| 5 | **`skipRest()` no valida la fase** → llamado en `.logging` avanza igual, **salteándose una serie entera**. | I-11 |
| 6 | **`bringExerciseNext` no valida que el ejercicio pertenezca al día** → reordena los `order` de los demás para nada. | I-14 |
| 7 | **`richness()` no cuenta `perceivedEffort`, `activeCalories` ni `ExerciseSet.isDone`** → un día donde el usuario solo tildó las series puntúa **0** y `cleanupKneeRecovery` **lo borra**. | I-30 |
| 8 | **`StrengthSeed` pisa `exercise.notes` del usuario**: la asignación está dentro del `if exercise.targetReps == nil`. | I-34 |
| 9 | **`hasLoggedData` mira `reps`/`weight` pero no `isDone`** → a un día donde el usuario solo tildó series, `populateIfNeeded` **le borra los ejercicios**. | I-35 |
| 10 | **Estado absorbente en el sembrado:** flag en 0 + días ya existentes (CloudKit bajó los registros antes que el KVS) → `seedIfNeeded` sale sin marcar versión → `applyPlanUpdates` también sale → **el plan no se actualiza nunca más**. | I-21 |
| 11 | **Crashes por parámetro negativo:** `WeeklyVolume.recentWeeks(-1)` y `StrengthProgress.recentImprovements(limit: -1)` → `fatalError` / precondition failure. Sin guard. | U-27, U-35 |

Además, dos contradicciones entre el código y sus comentarios, que hay que resolver decidiendo
cuál gana: `applyPlanUpdates` dice "los días que el usuario borre no se vuelven a insertar" pero
compara por fecha (I-23), y `taperVariant` dice "sin el trabajo de pierna" pero solo saca
"Flexión de rodillas", dejando aductores y extensión de rodillas (U-19).

## Lo que NO se puede automatizar

Hay que decirlo de entrada para no fingir cobertura que no existe. Necesitan hardware real y
quedan como **checklist manual** antes de cada release:

- Sync por CloudKit entre iPhone ↔ reloj ↔ Mac.
- Live Activity en pantalla bloqueada y Dynamic Island, con sus botones.
- Pulso en vivo (el simulador de watchOS no genera frecuencia cardíaca).
- Import desde Apple Salud (HealthKit no tiene datos en el simulador).
- Notificaciones locales de suplementos.
- Que el PDF *se vea bien* (que se genere y se comparta sí lo cubre E2E-09).

---

## Fase 0 — Prerequisitos

- [x] **P0-1 · Target de tests.** ✅ Hecho. `GymLogTests` (unit + integración, Swift Testing,
      `TEST_HOST` = `Maraton.app`, `@testable import Maraton`) y `GymLogUITests` (XCUITest). Ambos
      son `PBXFileSystemSynchronizedRootGroup`: **agregar un archivo `.swift` a la carpeta lo suma
      solo al target**, sin tocar el `.pbxproj`. También se versionó el scheme compartido
      (`xcshareddata/xcschemes/Maraton.xcscheme`) con los dos targets en su Test action, para que
      `xcodebuild test` sea reproducible en el CI.
      Correr todo: `xcodebuild test -scheme Maraton -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
      (~17 s). Solo unitarios: agregar `-only-testing:GymLogTests` (~13 s).

- [x] **P0-2 · Fechas deterministas.** ✅ Hecho. `PlanConstants.calendar` y los `DateFormatter` de
      `DateFormatting` usan la **TZ del dispositivo**, así que una fecha a medianoche puede caer en
      otro día según dónde corra el test. `TestSupport.swift` expone `date(2026, 7, 1)`, que
      construye la fecha **a mediodía**. **Usarla siempre**; no construir fechas a mano.

- [x] **P0-3 · Container en memoria.** ✅ Hecho (parcial). `AppData.makeContainer(inMemory: Bool = false)`
      devuelve un contenedor efímero, sin disco y sin CloudKit. Ojo: `ModelConfiguration` trae
      `cloudKitDatabase: .automatic` por defecto — sin el `.none` explícito, SwiftData intenta
      montar CloudKit **hasta sobre un store en memoria**.
      También se aisló el host: `MaratonApp.init()` detecta que está hosteando los tests unitarios
      (`AppData.isHostingUnitTests`) y arranca inerte — contenedor en memoria, sin sembrar y sin
      abrir el canal con el reloj. **Sin esto, cada corrida de tests escribía los flags de sembrado
      que los tests de seed necesitan controlar.** Los tests de UI no pasan por ahí: la app corre
      como proceso aparte y arranca normal.
      *Falta:* el `fatalError` de la rama no-in-memory sigue ahí (mataría el runner si alguien
      llamara `makeContainer()` sin `inMemory` desde un test).

      > ⚠️ **Trampa que ya nos costó una hora.** El `ModelContext` **no mantiene vivo** a su
      > `ModelContainer`. Un helper que cree el contenedor y devuelva solo `container.mainContext`
      > deja el contexto colgado apenas retorna → el test **crashea con `SIGTRAP`**, no falla. Y
      > como Swift Testing corre en paralelo, el crash **se lleva puesto al resto de los tests del
      > proceso**, que aparecen como fallados sin mensaje. Por eso `TestSupport` expone `TestDB`,
      > que guarda contenedor y contexto juntos: **guardalo en una variable del test.**

- [ ] **P0-4 · Flags de sembrado inyectables.** Los seeds leen y escriben **6 claves globales**
      (`seededPlanVersion`, `seededStrengthVersion`, `cleanedKneeRecoveryV1`, cada una en
      `UserDefaults.standard` **y** en `NSUbiquitousKeyValueStore.default`). Un test tendría que
      resetear las 6, y aun así el resultado dependería de si el bundle de tests tiene entitlement
      de iCloud: el KVS sin entitlement devuelve 0/false y **descarta escrituras en silencio**. Es
      una fábrica de flakes. Extraer `protocol SeedFlagStore` + una implementación en memoria.
      **Bloquea I-19..I-36.**

- [ ] **P0-5 · `AppData.iCloudSyncEnabled` es `static let`** (`Shared/AppData.swift:20`) → la rama
      "sin iCloud" de los seeds es inalcanzable desde un test. Pasarlo a `static var` o derivarlo
      del store de P0-4.

- [ ] **P0-6 · Reloj inyectable en el engine** *(mejora, no bloqueante)*. `startRest`, `adjustRest`
      y `makeSnapshot` usan `Date()` interno; `tickRest(now:)` **ya** recibe la fecha. Los tests del
      engine **se pueden escribir hoy** calculando `now` relativo a `engine.restEndDate!` — feo pero
      determinista. Inyectar un `var clock: () -> Date = Date.init` los deja mucho más legibles.
      Hacerlo cuando los tests del engine ya estén verdes, no antes.

- [ ] **P0-7 · `LiveSessionConnectivity.handle(_:)` es `private`**
      (`Shared/LiveSession/LiveSessionConnectivity.swift:107`). Adentro vive la regla de descarte
      de snapshots viejos, que es lógica pura y crítica para la sync reloj↔iPhone. Extraerla a
      `static func shouldAccept(_ new: LiveSessionSnapshot, over current: LiveSessionSnapshot?) -> Bool`.
      Es el refactor más barato del repo. **Bloquea I-37..I-39.**

Los protocolos para HealthKit, UNUserNotificationCenter, WCSession y HKWorkoutSession
(`HealthManager`, `NotificationManager`, `LiveActivityController`, `WatchWorkoutManager` — todos
singletons sin costura) **quedan para después**: no bloquean nada de lo que sigue.

---

## Fase 1 — Unit

Todo esto se escribe **sin refactorizar nada** salvo P0-1 (el target).

### Parseo de distancia (`PlannedDistance.parse`) — empezar por acá

La función más pura del repo y la que más casos raros tiene.

- [x] **U-01** `"Fondo largo 12 km"` → `12`. `"12,5 km"` → `12.5`. `"12.5km"` sin espacio → `12.5`. ✅
      (También `"0 km"` → `0`, que es un valor válido y no un "sin dato".)
- [x] **U-02** Rango → **promedio**: `"Fondo 13-14 km"` → `13.5`. Con en-dash (`13–14`) también. ✅
      El en-dash importa: es el que mete la sustitución automática de iOS al tipear. También con
      espacios alrededor del guion, con decimales, y un rango invertido (`14-13`) que promedia igual.
- [x] **U-03** Sin km → `nil`: `"Series 8x400 m"`, `"Descanso"`, `"Fuerza A"`. ✅
      Incluye los números que **no** son distancia (series, minutos, metros) y la ruta real por
      `WorkoutDay.plannedKm`: un día de fuerza o descanso no aporta km fantasma al volumen semanal.
- [x] **U-04** Case-insensitive: `"FONDO 10 KM"` → `10`. ✅
- [x] **U-05** ⚠️ Toma el **primer** match de `title + " " + detail`: `"Rodaje"` + `"5 km/h de
      viento, 10 km totales"` → `5`. Y `"1.000 km"` → `1.0`. ✅ **Ambos confirmados.**
      Ninguno muerde hoy —el plan siempre pone la distancia en el título y el ritmo en el detalle,
      y nadie planifica 1000 km en un día—, pero quedan escritos. El del separador de miles es
      irreparable sin cambiar el contrato: el regex acepta punto **y** coma como decimal, así que
      no puede distinguir `1.000` (mil, es-AR) de `1.000` (uno coma cero). Si algún día se formatean
      los km con separador de miles, esto los rompe.

### Formateo (`NumberFormatting`, `TimeFormatting`, `DateFormatting`)

- [ ] **U-06** `Int.restLabel`: `45 → "45 s"`, `60 → "1 min"`, `90 → "1:30 min"`, `120 → "2 min"`.
- [ ] **U-07** `Int.countdownLabel`: `90 → "1:30"`, `5 → "0:05"`.
- [ ] **U-08** ⚠️ Negativos: `(-30).restLabel` → `"-30 s"`, `(-5).countdownLabel` → `"0:-5"`.
      `restRemaining` es `Int` — fijar qué se espera.
- [ ] **U-09** `Double.formattedKm` / `.formattedKg`: separador decimal coma (es-AR), cero,
      y `1000.0 → "1.000"` (separador de miles — relevante para el tonelaje).
- [ ] **U-10** `Double.formattedPace`: `330 → "5'30\"/km"`; redondeo; cero.
- [ ] **U-11** `Date.dayMonth` / `.weekdayAndDay` / `.longDate` en es-AR. Comparar contra un
      `DateFormatter` construido en el test, **no** contra strings literales: las abreviaturas de
      mes de es-AR cambian entre versiones de iCU (`"may"` vs `"may."`).

### Serialización de la sesión en vivo (`Shared/LiveSession/LiveSessionState.swift`)

La fruta madura: importa **solo Foundation**, todo es `Codable` + `Equatable`, y `LiveSessionWire`
ya encapsula el encode/decode. Cero refactor, y protege el contrato reloj↔iPhone, que hoy no tiene
ninguna red.

- [x] **U-12** Round-trip de un `LiveSessionSnapshot` completo. ✅
- [x] **U-13** Round-trip con todos los opcionales en `nil`. ✅
- [x] **U-14** Round-trip de `LiveSessionAction.adjustRest(±15)` — el caso con valor asociado, el
      más frágil ante un rename. Y cada `case` restante. ✅
- [x] **U-15** `LiveSessionWire.payload(for:)` → `snapshot(from:)` devuelve un snapshot igual. ✅
      (También el comando, y que cada decodificador solo entienda su propia clave.)
- [x] **U-16** `snapshot(from:)` con `Data` corrupta o sin la clave → `nil`. **Documenta un fallo
      silencioso**: hoy usa `try?`, así que un payload de otra versión del schema se descarta sin
      log. ✅ **Confirmado.** Un JSON válido al que le falte un campo requerido —exactamente lo que
      mandaría un reloj con una versión vieja de la app— hace que **se pierda el snapshot entero,
      sin ninguna pista**. La sesión en vivo simplemente no aparece. El comportamiento actual
      (devolver `nil` en vez de crashear) está bien; lo que falta es **logging** o una **versión en
      el payload**. Pendiente de decidir: no es un bug de corrección, es de diagnosticabilidad.
- [x] **U-17** Fidelidad de las `Date` en el round-trip. Blinda contra que alguien cambie la
      estrategia de encoding de un solo lado — el encoder y el decoder son dos instancias distintas. ✅
      Incluye precisión de subsegundo en `restEndDate` (de la que depende el cronómetro) y un canario
      que falla si el wire empezara a aceptar fechas ISO-8601.

### Plantillas de fuerza (`Shared/StrengthSeed.swift`)

- [ ] **U-18** ⚠️ **Bug 1.** `templates(for:)` elige Día A o Día B por título. **Hoy
      `title.contains("b")` matchea cualquier "b"** → `"Gimnasio básico"` cae en Día B. Test que lo
      expone.
- [ ] **U-19** ⚠️ Un día "liviana" → `taperVariant`: mitad de series redondeando hacia arriba
      (`2→1`, `3→2`, `4→2`, `0→0`). **El comentario dice "sin trabajo de pierna" pero solo saca
      "Flexión de rodillas"** — deja aductores y extensión de rodillas.
- [ ] **U-20** Semana de pico (15-21/6) y taper (29/6-5/7): se filtran los ejercicios de salto.
      Bordes exactos: 14/6 no, 15/6 sí, 21/6 sí, 22/6 no, 28/6 no, 29/6 sí, 5/7 sí, 6/7 no.
- [ ] **U-21** `tracksWeight`: los de peso corporal / banda / core / salto → `false`. Los
      desconocidos → `true`. Es **case-sensitive y exacto**.

### Volumen (`Maraton/Models/WeeklyVolume.swift`)

- [ ] **U-22** `tonnage` = Σ (peso × reps). Las series sin peso o sin reps **no suman**.
- [ ] **U-23** `tonnage` con lista vacía → 0.
- [ ] **U-24** `actualKm` suma solo días completados. ⚠️ Asimétrico con `plannedKm`, que no filtra.
- [ ] **U-25** `recentWeeks(6)`: devuelve 6, de la más vieja a la más nueva, la última contiene
      `today`.
- [ ] **U-26** `recentWeeks` sin datos → 6 semanas en cero (es el caso que dibuja la tarjeta vacía).
- [ ] **U-27** ⚠️ **Bug 11.** `recentWeeks(0)` → `[]`, pero `recentWeeks(-1)` → **crash**.
- [ ] **U-28** La semana arranca el **lunes**. Test con un domingo y el lunes siguiente.
- [ ] **U-29** Cruce de año (semana del 29/12 al 4/1).

### Racha (`StreakCalculator`)

- [ ] **U-30** `currentWeekStreak` cuenta semanas consecutivas con al menos un día completado.
- [ ] **U-31** Una semana en curso sin completar **no corta** la racha (se cuenta desde la última
      semana activa hacia atrás).
- [ ] **U-32** ⚠️ **Bug 2.** Agrupa por `weekTitle` (String), no por semana calendario. Test con
      dos semanas del mismo título.
- [ ] **U-33** `currentDayStreak`: los días de descanso intercalados no cortan ni suman; hoy
      pendiente no corta; ayer pendiente sí.

### Fuerza e historial

- [ ] **U-34** `StrengthProgress.recentImprovements` detecta una subida de peso; ignora ejercicios
      con menos de 2 sesiones con datos.
- [ ] **U-35** ⚠️ **Bug 11.** `limit: 0` → `[]`, pero `limit: -1` → **crash**. Y ⚠️ `percentChange`
      **puede ser negativo** — el tipo se llama "improvement" pero incluye retrocesos: fijar el
      contrato.
- [ ] **U-36** `ExerciseHistory.lastWeight` = el **mayor** peso de la última sesión anterior con
      datos. Ignora el día actual (comparación con `<` estricto).
- [ ] **U-37** ⚠️ **Asimetría:** `lastWeight` sigue buscando hacia atrás si la última sesión no
      tiene ningún peso, pero `lastSession` solo mira la primera con datos. Y ambas tienen
      `fetchLimit = 10`: con más de 10 registros previos sin datos, se pierde el histórico.

### Suplementos, tipos y reporte

- [ ] **U-38** `SupplementTracker.adherence`: fracción en la ventana; `days <= 0` → 0 (protegido);
      logs duplicados el mismo día cuentan una vez; logs futuros no cuentan.
- [ ] **U-39** `SupplementTracker.currentStreak`: solo hoy → 1; solo ayer (hoy no) → 1 (**el día en
      curso no corta la racha**); un hueco corta.
- [ ] **U-40** `WorkoutDay.dailyStatus`: un día de descanso marcado como completado igual devuelve
      `.rest`. Y `objective` con `detail` vacío.
- [ ] **U-41** `WeekAssigner.weekInfo`: hereda el título si hay un día de esa semana; si no, crea
      `"Semana del …"` con `order = max + 1`. Con `days` vacío → `order = 1`.
- [ ] **U-42** `ProgressReportBuilder.build` con `days` vacío → `periodStart = today`,
      `completionRate = 0`, `avgPace = nil`, sin crash. (Es `static`, puro, con `today` inyectable
      y `HealthSnapshot()` sirve de stub — el mejor test de integración de lógica pura del repo.)
- [ ] **U-43** `ProgressReportBuilder`: una corrida con km pero **sin duración** cuenta en el total
      de km pero **no** en el ritmo promedio. Y `avgPace` es ponderado por distancia.
- [ ] **U-44** `ProgressReportBuilder`: `completionRate` con 0 días de entrenamiento → 0 (división
      protegida).

---

## Fase 2 — Integración

Container SwiftData en memoria.

### La máquina de estados de la sesión guiada

El corazón de la app, hoy sin una sola prueba. Y la buena noticia: **es testeable tal como está,
sin refactor**. Importa solo Foundation + SwiftData; el `ModelContext` es **opcional** (sin él el
engine funciona entero en memoria, solo no persiste ni consulta historial); y sus cuatro efectos
externos ya están inyectados como closures (`onRestAlert`, `onStateChanged`, `onRestStarted`,
`onRestEnded`) → **se espían con contadores, sin mocks**. `tickRest(now:)` recibe la fecha, así que
el cronómetro se simula sin esperar tiempo real. Es el mayor retorno del repo.

- [x] **I-01** `start(day:)` arma los pasos (ejercicios × series) y arranca en `.logging` sobre la
      primera serie incompleta. ✅ También: el core (sin series) ocupa un paso, y `start` es
      idempotente — la vista llama `prepare` en el init y `start` en el `onAppear`, así que rearmar
      los pasos perdería el progreso de la sesión en curso.
- [x] **I-02** `completeCurrent` → `.resting` con el descanso del ejercicio. En la última serie →
      `.done`. ✅ El descanso sale de **cada ejercicio** (press 90 s, remo 60 s), terminar marca el
      día como completado, y la última serie no abre un descanso que nadie va a consumir.
- [x] **I-03** Un paso **sin series** (core) → `completeCurrent` **saltea el descanso** y avanza
      directo. ✅ **Falsa alarma aclarada:** el paso de core nunca queda marcado como hecho
      (`step.set?.isDone` es un no-op sin serie). Parece un bug, pero no lo es: `firstIncompleteIndex`
      solo mira pasos **con** serie, así que al retomar la sesión el core se saltea igual y no
      bloquea nada. Queda escrito para que nadie lo "arregle" de más.
- [x] **I-04** `skipRest` → `.logging` de la serie siguiente. ✅ Avanzar limpia el `restEndDate` (si
      sobreviviera, el iPhone seguiría dibujando una cuenta regresiva sobre una serie que ya no
      descansa), y `skipRest` es también la salida del tiempo extra ("Empezar serie").
- [x] **I-05** **Regla clave:** cuando el descanso llega a cero, el engine **no avanza solo** —
      entra en tiempo extra y espera confirmación. Es la decisión de diseño más importante del
      engine y hoy solo la sostiene un comentario. ✅ **Ya no.** 120 ticks seguidos pasado el
      vencimiento no mueven la sesión ni un paso; solo `skipRest` avanza. Si avanzara solo, el reloj
      daría por empezada una serie que el usuario todavía no arrancó, y las reps y el peso quedarían
      asignados al momento equivocado.
- [x] **I-06** ⚠️ **Bug 3 — confirmado, pero NO alcanzable.** ✅ Con `restSeconds == 0`,
      `onStateChanged` nunca se emite al entrar en tiempo extra (`enteringOvertime = restRemaining > 0`
      no se cumple si ya arrancó en 0), así que el iPhone y la Live Activity no pintan el rojo.
      **Corrección de severidad:** el 0 **no es alcanzable hoy** — las plantillas usan 30-120 s,
      `adjustRest` clampea el total a un mínimo de 15, y ninguna vista escribe `restSeconds = 0`. Es
      un agujero de la lógica del engine, no un bug que el usuario pueda ver. El test queda como
      guardia: el día que se agregue una plantilla sin descanso (una superserie), se vuelve real.
      También queda fijado el caso normal: el cruce a tiempo extra avisa **exactamente una vez**, y
      los ticks con descanso restante **no** avisan (inundar WatchConnectivity con un snapshot por
      tick sería carísimo; la cuenta regresiva la dibuja cada cliente desde `restEndDate`).
- [x] **I-07** ⚠️ **Bug 4 — CONFIRMADO y alcanzable.** ✅ Volver de background con 35 s de tiempo
      extra encima dispara **4 vibraciones en menos de un segundo**, en vez de una.
      **Causa:** `tickRest` avisa si `restOvertime >= nextOvertimeAlert` y después hace
      `nextOvertimeAlert += 10`. El `+=` asume ticks seguidos: sube de a 10 por vez. Si la app
      estuvo suspendida, el contador arranca en 0 y tiene que **remontar** — y cada tick del remonte
      dispara su propia vibración.
      **Alcanzable todos los días:** bajás la muñeca, el reloj apaga la pantalla y deja de tickear.
      **Fix propuesto:** saltar `nextOvertimeAlert` al próximo múltiplo de 10 por encima del
      `restOvertime` actual, en vez de incrementarlo de a 10. **Pendiente de aplicar** (commit aparte).
- [x] **I-08** `adjustRest(±15)` mueve `restEndDate`, no lo deja en negativo, y **persiste
      `exercise.restSeconds`** (ojo: cambia la preferencia del ejercicio, no solo este descanso). ✅
      Confirmado que el ajuste **queda recordado**: la serie siguiente del mismo ejercicio ya arranca
      con el descanso nuevo. Es deliberado ("lo aprende"), pero implica que **no hay forma de alargar
      un descanso solo por esta vez**. Decisión de producto, no bug.
      Los dos clamps son distintos a propósito: el remanente baja a **1 s** (el descanso se corta ya)
      pero el total recordado no baja de **15 s** (para no dejar al ejercicio con un descanso
      inservible). Efecto colateral: el anillo de la UI queda casi vacío (`restFraction` = 1/15).
- [x] **I-09** `goBackFromLogging` vuelve atrás y **des-marca** la serie. En `index == 0` es no-op
      **y no emite `onStateChanged`** (el iPhone no recibe eco). ✅
      Des-marcar es lo que importa: si la serie siguiera marcada, al retomar la sesión el engine la
      saltearía y perderías la corrección. El no-op silencioso en el índice 0 **no es un bug** (el
      estado no cambió, no hay nada que difundir), pero implica que la Live Activity no puede
      distinguir "no llegó el comando" de "llegó y era no-op".
- [ ] **I-10** `goBackFromResting` **no avanza el índice** y deja `restTotal`/`restRemaining`/
      `restOvertime` con basura del descanso anterior. Fijar el contrato.
- [ ] **I-11** ⚠️ **Bug 5.** `skipRest()` en `.logging` **avanza igual**, salteándose una serie.
- [ ] **I-12** `bringExerciseNext` reordena los `Exercise.order` y **preserva lo ya registrado**.
- [ ] **I-13** `bringExerciseNext` sobre el ejercicio actual → no-op. Durante `.resting` → reubica
      el índice pero **no cambia la fase**.
- [ ] **I-14** ⚠️ **Bug 6.** `bringExerciseNext` con un ejercicio que **no pertenece al día** →
      reordena a los demás para nada, sin guard.
- [ ] **I-15** Retomar una sesión a medias arranca en la primera serie incompleta. ⚠️ **Si están
      todas hechas devuelve 0** → reinicia desde el principio en vez de ir a `.done`.
- [ ] **I-16** **Día sin ejercicios:** `steps == []`, `isLastStep == true` (!), `completeCurrent` es
      no-op → **la sesión nunca llega a `.done`**.
- [ ] **I-17** `prefillCurrentSet` aplica reps objetivo (`"6-8"` → **8**, el máximo) + peso
      sugerido, y **nunca pisa** lo que el usuario ya cargó.
- [ ] **I-18** `suggestedWeight` prefiere el peso de la serie previa **de esta sesión** por sobre el
      histórico, y salta series intermedias sin peso.
- [ ] **I-19** `apply(_ command:)` produce **la misma transición** que el método directo, para cada
      `LiveSessionCommand`. Ignora comandos con otro `sessionID`. ⚠️ `apply(.goBack)` desde `.done`
      **resucita** la sesión a `.logging`.
- [ ] **I-20** `makeSnapshot` refleja fase, índice, progreso y pulso; `restEndDate` solo en
      `.resting`. Round-trip por `LiveSessionWire` → snapshot equivalente. Cierra el lazo engine ↔
      serialización.

### Seeds y migraciones *(requieren P0-3, P0-4, P0-5)*

- [ ] **I-21** ⚠️ **Bug 10.** Estado absorbente: flag en 0 + días existentes → `seedIfNeeded` sale
      sin marcar versión → el plan no se actualiza nunca más.
- [ ] **I-22** `seedIfNeeded` siembra en DB vacía, marca la versión, y es idempotente.
- [ ] **I-23** ⚠️ **Contradicción.** `applyPlanUpdates` inserta solo fechas faltantes y no toca los
      existentes — pero el comentario dice "los días que el usuario borre no se vuelven a insertar"
      y **compara por fecha**: si sube `planVersion`, el día borrado **reaparece**.
- [ ] **I-24** `deduplicateDays` conserva el día con más datos del usuario, y es idempotente.
- [ ] **I-25** ⚠️ Con dos días de igual "riqueza", el ganador debe ser estable. Hoy desempata por
      `String(describing: persistentModelID)`, que en un container en memoria **no tiene orden
      garantizado** — si el test sale flaky, ese **es** el hallazgo.
- [ ] **I-26** El borrado arrastra en cascada `Exercise` y `ExerciseSet`: no quedan huérfanos.
- [ ] **I-27** `cleanupKneeRecoveryIfNeeded` borra los días vacíos del rango 24/6→5/7 y **preserva**
      los que tienen datos, incluida la carrera del 5/7.
- [ ] **I-28** ⚠️ **Bug 7.** `richness()` no cuenta `perceivedEffort`, `activeCalories` ni
      `isDone` → un día donde el usuario solo tildó las series **se borra**.
- [ ] **I-29** `populateIfNeeded` llena los días de fuerza vacíos del 9/6 en adelante y **no toca**
      los anteriores.
- [ ] **I-30** ⚠️ **Bug 8.** No debe pisar `exercise.notes` del usuario.
- [ ] **I-31** ⚠️ **Bug 9.** No debe borrar los ejercicios de un día donde el usuario solo tildó
      series (`isDone` sin reps/peso).
- [ ] **I-32** **Invariante global:** después de `AppData.seed` completo (seed → updates → strength
      → dedup → cleanup), **no hay ninguna fecha duplicada**. Es la unicidad que CloudKit no puede
      garantizar y que hoy sostiene el código a mano.

### Conectividad *(requiere P0-7)*

- [ ] **I-33** `shouldAccept` descarta un snapshot con `updatedAt` menor o igual al actual del mismo
      `sessionID`, y acepta uno de otro `sessionID`.
- [ ] **I-34** `handle(_:)` dispara `onSnapshot` / `onCommand` según el payload.
- [ ] **I-35** Política de entrega: reachable → `sendMessage`; no reachable → `transferUserInfo`;
      los snapshots además siempre van por `updateApplicationContext`, los comandos no. *(Requiere
      protocolizar `WCSession` — opcional, se puede diferir.)*

---

## Fase 3 — E2E (XCUITest)

Pocos y gordos: son los más lentos y frágiles, así que solo los caminos que, si se rompen, hacen la
app inusable.

- [ ] **E2E-01** Primer arranque: la app siembra el plan y muestra el día de hoy.
- [ ] **E2E-02** Navegar el carrusel de días y saltar con la tira de la semana.
- [ ] **E2E-03** **El recorrido principal:** sesión guiada — cargar peso y reps con la rueda,
      "Hecho", entra en descanso, saltear, avanza a la serie siguiente.
- [ ] **E2E-04** Completar una sesión entera → el día queda marcado como completado.
- [ ] **E2E-05** Cambiar el próximo ejercicio a mitad de sesión.
- [ ] **E2E-06** Marcar un suplemento y verlo reflejado en Progreso.
- [ ] **E2E-07** Crear, editar y borrar un día en la tab Plan.
- [ ] **E2E-08** Completar una corrida (km + minutos) y ver el ritmo calculado.
- [ ] **E2E-09** Generar el reporte PDF → aparece la hoja de compartir.
- [ ] **E2E-10** Exportar el plan a PDF → aparece la hoja de compartir.

Los E2E necesitan que la app arranque con una base **determinística**. Agregar un launch argument
(`-uitesting`) que fuerce container en memoria + plan sembrado fijo. Sin eso, los tests dependen de
lo que haya quedado en el simulador y salen flaky.

---

## Cuándo corre cada cosa

| Gate | Qué corre | Tiempo | Bloquea |
|---|---|---|---|
| **pre-commit** (hook) | Escaneo de datos personales y secretos | < 2 s | el commit |
| **pre-push** (hook) | Unit + Integración | ~40 s | el push |
| **CI** (push a `main` + PRs) | Build iOS + watchOS + Catalyst, Unit + Integración + E2E | ~10-15 min | el merge |

**El pre-commit no corre tests.** Commitear tiene que ser barato: si tarda 20 segundos, uno empieza
a usar `--no-verify` y el hook deja de servir. Lo que sí corre es el escaneo de datos personales —
que en este repo **ya no es hipotético**: el HANDOFF tenía el email y los UDIDs de los dispositivos,
y hubo que reescribir el historial para sacarlos. El hook existe para que no vuelva a pasar.

**El pre-push corre la pirámide rápida.** Es el gate real: 40 segundos antes de publicar es un
precio razonable y ataja casi todas las regresiones sin esperar al CI.

**El CI corre todo.** Ahora que el repo es público, los runners macOS de GitHub Actions son gratis
(en repos privados consumen minutos a 10×, lo que habría cambiado el cálculo). Compila **los tres
targets** — importante, porque el reloj y la extensión **no** se compilan al correr los tests del
target iOS, y es fácil romperlos sin enterarse.

⚠️ **A verificar al armar el CI:** el proyecto exige **iOS 26.5 / watchOS 26.5** (Xcode 26.6). Hay
que confirmar que la imagen de runner de GitHub trae un Xcode 26.x. Si no, el CI queda bloqueado
hasta que actualicen la imagen y la alternativa es un runner self-hosted en la Mac.

**Antes de cada release:** la checklist manual (CloudKit, Live Activity, pulso, HealthKit,
notificaciones). Nada de eso lo cubre el CI.

---

## Cómo escribir un test

El andamio ya está. `GymLogTests/TestSupport.swift` da:

- **`TestDB()`** — base SwiftData en memoria, aislada por test. Guardala en una variable (ver la
  trampa del `SIGTRAP` en P0-3).
- **`date(2026, 7, 1)`** — fecha determinística, a mediodía.
- **`makeDay(...)`** y **`makeExercise(...)`** — constructores de modelos con defaults razonables.

Agregar un archivo `.swift` a `GymLogTests/` alcanza: el target lo toma solo.

```swift
@Suite("Volumen semanal")
struct WeeklyVolumeTests {
    @Test("El tonelaje ignora las series sin peso")
    func tonnageIgnoresBodyweightSets() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), in: db.context)
        makeExercise("Plancha", on: day, sets: [(nil, nil)], in: db.context)
        makeExercise("Press", on: day, sets: [(50, 10)], in: db.context)

        #expect(WeeklyVolume.tonnage(for: date(2026, 7, 1), among: day.orderedExercises) == 500)
    }
}
```

## Orden de ataque

No es el orden de la pirámide:

1. ~~**P0-1** (target de tests)~~ ✅ hecho, junto con ~~P0-2~~ y ~~P0-3~~.
2. **U-12..U-17** (serialización) — cero refactor, y es lo único que protege el contrato
   reloj↔iPhone.
3. **U-01..U-05** (`PlannedDistance.parse`) — la función más pura y con más casos raros.
4. **I-01..I-20** (el engine) — **cero refactor**, es el corazón de la app, y ahí están los bugs
   3, 4, 5 y 6. No esperar a P0-6.
5. **Resto de la Fase 1** — cero refactor, valor inmediato.
6. **P0-3..P0-5** (los refactors de persistencia) → **I-21..I-32** — acá salen los bugs 7, 8, 9 y 10.
7. **P0-7** → **I-33..I-35** (conectividad). **P0-6** cuando el engine ya esté verde.
8. **Fase 3** (E2E) — al final, cuando lo de abajo ya no se mueve.

Los pasos 2, 3 y 4 **no requieren tocar una línea de producción** más allá de crear el target. Ese
es el arranque: red debajo de lo más crítico antes de refactorizar nada.
