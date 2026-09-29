import Foundation

/// Reviewed versions, not an inference from popularity, file extension, or a Valheim category.
public enum ModCompatibility {
    public static let bundled: [String:(name:String,version:String)] = [
        // Pack 5.4.2350/2351 uses BepInEx 5.4.23.5, the core built by build-management.sh.
        // This is the supported dependency-pack version; the native loader has its own version.
        "denikson-BepInExPack_Valheim":("BepInEx","5.4.2351"),
        "ValheimModding-Jotunn":("Jötunn","2.30.2"),
        "MidnightMods-NetworkPerformanceSystem":("NetworkPerformanceSystem","1.6.0")
    ]
    public static func verified(package:String,version:String) -> Bool { bundled[package]?.version == version }
    public static func catalogEligible(_ package:ModPackage) -> Bool {
        guard package.requirement != .clientOnly, !isExternalManager(package) else { return false }
        let tags = Set(package.categories.map { $0.lowercased().replacingOccurrences(of:"_",with:"-").replacingOccurrences(of:" ",with:"-") })
        return tags.isDisjoint(with:["windows-only","linux-only","macos-incompatible","mac-incompatible"])
    }
    private static func isExternalManager(_ package: ModPackage) -> Bool {
        let description = package.latest?.description.lowercased() ?? ""
        let name = package.name.lowercased()
        return name == "r2modman" || name.contains("modmanager") || description.contains("mod manager for thunderstore")
    }
    public static func label(package:String,version:String) -> String {
        verified(package:package,version:version) ? "Mac tested" : "Mac compatibility unverified"
    }
    public static func split(_ pin: String) -> (name: String, version: String)? {
        guard let range = pin.range(of: #"-\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?$"#, options: .regularExpression) else { return nil }
        return (String(pin[..<range.lowerBound]), String(pin[pin.index(after: range.lowerBound)...]))
    }
    public static func satisfies(package: String, version: String?, pin: String) -> Bool {
        guard let required = split(pin), required.name == package, let version else { return false }
        if version == required.version { return true }
        // Do not substitute prereleases for stable releases or compare unknown version formats.
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              required.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return false }
        return version.compare(required.version, options: .numeric) == .orderedDescending
    }
    public static func dependency(_ pin: String, in mods: [StoredMod]) -> StoredMod? {
        mods.filter { satisfies(package: $0.package, version: $0.version, pin: pin) }.sorted {
            if $0.selected != $1.selected { return $0.selected }
            return ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedDescending
        }.first
    }
    public static func supplies(_ pin:String) -> Bool {
        // The loader and Jötunn are deployed whenever custom mods are enabled.
        // Optional networking is not a substitute unless selected in the server library.
        // The generic Mono pack 5.4.2100 contains BepInEx 5.4.21; our native 5.4.23.5
        // supplies that API without importing the Windows bootstrap. Do not alias game-specific
        // packs or newer unreviewed versions by name alone.
        if satisfies(package:"BepInEx-BepInExPack",version:"5.4.2100",pin:pin) { return true }
        return ["denikson-BepInExPack_Valheim", "ValheimModding-Jotunn"].contains { package in
            satisfies(package: package, version: bundled[package]?.version, pin: pin)
        }
    }
}
