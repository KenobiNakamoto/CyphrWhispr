import Foundation

/// A snapshot of the host's relevant compute characteristics. We only need three
/// signals to pick a Whisper tier: chip family, RAM, and Apple Silicon vs. Intel.
struct HardwareProfile: Equatable, Sendable {
    enum Family: String, Sendable {
        case intel
        case m1
        case m2
        case m3
        case m4
        case unknown
    }

    enum Variant: String, Sendable {
        case base       // plain "M3"
        case pro        // "M3 Pro"
        case max        // "M3 Max"
        case ultra      // "M3 Ultra"
        case unknown
    }

    /// Raw vendor string, e.g. "Apple M3 Pro" or "Intel(R) Core(TM) i7-9750H".
    let chipBrand: String
    let family: Family
    let variant: Variant
    let ramGB: Int
    let isAppleSilicon: Bool

    /// Human-friendly summary for the onboarding screen.
    var displayName: String {
        if isAppleSilicon {
            // chipBrand already reads "Apple M3 Pro" — leave it.
            return chipBrand
        }
        return chipBrand
    }
}

/// Reads chip and RAM information out of the kernel via `sysctlbyname`.
///
/// Why sysctl and not `ProcessInfo`: `ProcessInfo.processorCount` and
/// `physicalMemory` are useful but don't tell us the chip *family*. For the
/// recommender to distinguish "M2 base" from "M3 Pro" we need the brand string.
enum HardwareProfiler {
    static func profile() -> HardwareProfile {
        let brand = sysctlString(name: "machdep.cpu.brand_string") ?? "Unknown CPU"
        let memBytes = sysctlUInt64(name: "hw.memsize") ?? 0
        let ramGB = Int((Double(memBytes) / 1_073_741_824).rounded())
        let isArm = (sysctlInt(name: "hw.optional.arm64") ?? 0) == 1

        let (family, variant) = parseFamily(from: brand, isArm: isArm)

        return HardwareProfile(
            chipBrand: brand,
            family: family,
            variant: variant,
            ramGB: ramGB,
            isAppleSilicon: isArm
        )
    }

    // MARK: - Parsing

    private static func parseFamily(from brand: String, isArm: Bool) -> (HardwareProfile.Family, HardwareProfile.Variant) {
        guard isArm else { return (.intel, .unknown) }

        // Apple's brand strings look like "Apple M1", "Apple M2 Pro", "Apple M3 Max", "Apple M3 Ultra".
        let lower = brand.lowercased()
        let family: HardwareProfile.Family
        if lower.contains("m1") {
            family = .m1
        } else if lower.contains("m2") {
            family = .m2
        } else if lower.contains("m3") {
            family = .m3
        } else if lower.contains("m4") {
            family = .m4
        } else {
            family = .unknown
        }

        let variant: HardwareProfile.Variant
        if lower.contains("ultra") {
            variant = .ultra
        } else if lower.contains("max") {
            variant = .max
        } else if lower.contains("pro") {
            variant = .pro
        } else if family != .unknown {
            variant = .base
        } else {
            variant = .unknown
        }

        return (family, variant)
    }

    // MARK: - sysctl helpers

    private static func sysctlString(name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlUInt64(name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func sysctlInt(name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
