import Foundation

struct SkillMetadata: Equatable {
    var name: String?
    var description: String?
}

enum SkillMetadataParser {
    static func parse(_ text: String) -> SkillMetadata {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return SkillMetadata()
        }

        let end = lines.dropFirst().firstIndex {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        } ?? lines.endIndex
        var metadata = SkillMetadata()
        var index = 1

        while index < end {
            let line = lines[index]
            if line.isEmpty {
                index += 1
                continue
            }
            if let first = line.first, first == " " || first == "\t" {
                index += 1
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                index += 1
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
            let value: String
            if [">", ">-", ">+", "|", "|-", "|+"].contains(rawValue) {
                var blockLines: [String] = []
                index += 1
                while index < end {
                    let blockLine = lines[index]
                    if blockLine.isEmpty {
                        blockLines.append("")
                        index += 1
                        continue
                    }
                    guard blockLine.first == " " || blockLine.first == "\t" else { break }
                    blockLines.append(blockLine.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                value = blockLines
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                value = unquoted(rawValue)
                index += 1
            }

            if key == "name", !value.isEmpty { metadata.name = value }
            if key == "description", !value.isEmpty { metadata.description = value }
        }
        return metadata
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
