import Foundation

/// A deliberately small TOML subset: comments, `[table]`, `[[array-of-tables]]`
/// and `key = value` where value is a string, integer, float or boolean.
/// That is all the GridKeys config needs, and it keeps the tool dependency-free.
public enum TOMLValue: Equatable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var intValue: Int? { if case .integer(let i) = self { return i }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var doubleValue: Double? {
        switch self {
        case .float(let d): return d
        case .integer(let i): return Double(i)
        default: return nil
        }
    }
}

public typealias TOMLTable = [String: TOMLValue]

public struct TOMLDocument: Equatable {
    public var root: TOMLTable = [:]
    public var tables: [String: TOMLTable] = [:]
    public var arrays: [String: [TOMLTable]] = [:]
    /// 1-based source line of each array-of-tables entry, for error messages.
    public var arrayLines: [String: [Int]] = [:]
}

public struct TOMLError: Error, CustomStringConvertible, Equatable {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }
}

public enum TOMLParser {
    public static func parse(_ text: String) throws -> TOMLDocument {
        var doc = TOMLDocument()
        enum Target { case root, table(String), array(String) }
        var target = Target.root

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNo = index + 1
            let line = try stripComment(rawLine, line: lineNo).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]") else { throw TOMLError(line: lineNo, message: "unterminated [[table]] header") }
                let name = try headerName(String(line.dropFirst(2).dropLast(2)), line: lineNo)
                doc.arrays[name, default: []].append([:])
                doc.arrayLines[name, default: []].append(lineNo)
                target = .array(name)
                continue
            }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else { throw TOMLError(line: lineNo, message: "unterminated [table] header") }
                let name = try headerName(String(line.dropFirst().dropLast()), line: lineNo)
                if doc.tables[name] != nil { throw TOMLError(line: lineNo, message: "table [\(name)] defined twice") }
                doc.tables[name] = [:]
                target = .table(name)
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw TOMLError(line: lineNo, message: "expected `key = value`")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard isBareKey(key) else { throw TOMLError(line: lineNo, message: "invalid key '\(key)'") }
            let value = try parseValue(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces), line: lineNo)

            func insert(into table: inout TOMLTable) throws {
                if table[key] != nil { throw TOMLError(line: lineNo, message: "duplicate key '\(key)'") }
                table[key] = value
            }
            switch target {
            case .root: try insert(into: &doc.root)
            case .table(let name): try insert(into: &doc.tables[name]!)
            case .array(let name):
                var entries = doc.arrays[name]!
                try insert(into: &entries[entries.count - 1])
                doc.arrays[name] = entries
            }
        }
        return doc
    }

    private static func headerName(_ raw: String, line: Int) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard isBareKey(name) else { throw TOMLError(line: line, message: "invalid table name '\(name)'") }
        return name
    }

    private static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-"
        }
    }

    private static func stripComment(_ line: String, line lineNo: Int) throws -> String {
        var inString = false
        var escaped = false
        for (offset, ch) in line.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "#" {
                return String(line.prefix(offset))
            }
        }
        if inString { throw TOMLError(line: lineNo, message: "unterminated string") }
        return line
    }

    private static func parseValue(_ raw: String, line: Int) throws -> TOMLValue {
        if raw.isEmpty { throw TOMLError(line: line, message: "missing value") }
        if raw.hasPrefix("\"") { return .string(try parseString(raw, line: line)) }
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        let numeric = raw.replacingOccurrences(of: "_", with: "")
        if let i = Int(numeric) { return .integer(i) }
        if let d = Double(numeric), numeric.contains(".") { return .float(d) }
        throw TOMLError(line: line, message: "unsupported value '\(raw)' (use a \"string\", number or true/false)")
    }

    private static func parseString(_ raw: String, line: Int) throws -> String {
        var result = ""
        var chars = raw.dropFirst().makeIterator()
        var closed = false
        while let ch = chars.next() {
            if ch == "\"" { closed = true; break }
            if ch == "\\" {
                guard let esc = chars.next() else { break }
                switch esc {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: throw TOMLError(line: line, message: "unsupported escape \\\(esc)")
                }
            } else {
                result.append(ch)
            }
        }
        guard closed else { throw TOMLError(line: line, message: "unterminated string") }
        if chars.next() != nil { throw TOMLError(line: line, message: "unexpected text after string") }
        return result
    }

    public static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out + "\""
    }
}
