import Darwin
import Foundation

/// Reads another process's exact launch arguments, so each running Claude
/// copy can be matched to its account without parsing `ps` output.
public enum ProcessArguments {
    public static let userDataDirFlag = "--user-data-dir="

    /// The arguments of a running process, or nil if it cannot be read.
    public static func of(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))
    }

    /// KERN_PROCARGS2 layout: argc (Int32), executable path, NUL padding,
    /// then argc NUL-terminated arguments (environment follows; ignored).
    public static func parse(_ bytes: [UInt8]) -> [String]? {
        let header = MemoryLayout<Int32>.size
        guard bytes.count > header else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return nil }
        var index = header
        while index < bytes.count, bytes[index] != 0 { index += 1 }   // executable path
        while index < bytes.count, bytes[index] == 0 { index += 1 }   // padding
        var args: [String] = []
        while args.count < Int(argc), index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            args.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return args.count == Int(argc) ? args : nil
    }

    /// The value of `--user-data-dir=…`, or nil when the flag is absent
    /// (which means the default account).
    public static func userDataDir(in arguments: [String]) -> String? {
        guard let arg = arguments.first(where: { $0.hasPrefix(userDataDirFlag) }) else { return nil }
        let value = String(arg.dropFirst(userDataDirFlag.count))
        return value.isEmpty ? nil : value
    }

    /// True when a process with these arguments belongs to this profile.
    public static func belongs(_ arguments: [String], to profile: Profile) -> Bool {
        let dir = userDataDir(in: arguments)
        if profile.desktopDir.isEmpty { return dir == nil }
        guard let dir else { return false }
        return normalized(dir) == normalized(profile.desktopDir)
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
