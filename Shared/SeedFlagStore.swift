//
//  SeedFlagStore.swift
//  Maraton (compartido iOS + watchOS)
//
//  Dónde viven los flags de sembrado ("¿qué versión del plan ya sembré?", "¿ya limpié los días
//  de la recuperación de rodilla?").
//
//  Antes cada seed hablaba directo con `UserDefaults` y con el Key-Value Store de iCloud, y
//  repetía la misma lógica en tres lugares. El problema no era la repetición: era que dejaba a
//  los seeds **sin costura**. Un test tenía que resetear seis claves globales, y aun así el
//  resultado dependía de si el bundle de tests tiene entitlement de iCloud —sin él, el KVS
//  devuelve 0/false y **descarta las escrituras en silencio**—. Una fábrica de flakes.
//

import Foundation

/// Lectura y escritura de los flags de sembrado.
protocol SeedFlagStore {
    func integer(forKey key: String) -> Int
    func setInteger(_ value: Int, forKey key: String)
    func bool(forKey key: String) -> Bool
    func setBool(_ value: Bool, forKey key: String)
}

/// El store real: `UserDefaults` (siempre) más el Key-Value Store de iCloud (si la sync está
/// activa), que es lo que evita re-sembrar al reinstalar o al estrenar un dispositivo.
///
/// Con `cloud == nil` queda la rama "sin iCloud": solo local. Esa rama existía antes pero era
/// **inalcanzable desde un test**, porque colgaba de `AppData.iCloudSyncEnabled`, que es un
/// `static let`. Ahora se elige construyendo el store.
struct DefaultSeedFlagStore: SeedFlagStore {
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?

    init(
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = AppData.iCloudSyncEnabled ? .default : nil
    ) {
        self.defaults = defaults
        self.cloud = cloud
    }

    /// Gana el más alto entre la nube y lo local: si otro dispositivo ya sembró una versión más
    /// nueva, esta instalación no la vuelve a sembrar.
    func integer(forKey key: String) -> Int {
        let local = defaults.integer(forKey: key)
        guard let cloud else { return local }
        return max(Int(cloud.longLong(forKey: key)), local)
    }

    func setInteger(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
        cloud?.set(Int64(value), forKey: key)
        cloud?.synchronize()
    }

    /// Misma regla que `integer`, en booleano: alcanza con que **alguno** de los dos lo tenga
    /// marcado para considerar el trabajo hecho.
    func bool(forKey key: String) -> Bool {
        let local = defaults.bool(forKey: key)
        guard let cloud else { return local }
        return local || cloud.bool(forKey: key)
    }

    func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
        cloud?.set(value, forKey: key)
        cloud?.synchronize()
    }
}
