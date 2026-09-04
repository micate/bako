import XCTest
@testable import BakoApp

final class SkillMetadataParserTests: XCTestCase {
    func testParsesFoldedDescriptionInsteadOfMarker() {
        let text = """
        ---
        name: openyida
        description: >
          宜搭应用开发总入口技能。
          用于创建和修改完整应用。
        ---
        # Instructions
        """
        let metadata = SkillMetadataParser.parse(text)
        XCTAssertEqual(metadata.name, "openyida")
        XCTAssertEqual(metadata.description, "宜搭应用开发总入口技能。 用于创建和修改完整应用。")
    }

    func testParsesLiteralAndQuotedValues() {
        let text = """
        ---
        name: "demo"
        description: |-
          first line
          second line
        ---
        """
        let metadata = SkillMetadataParser.parse(text)
        XCTAssertEqual(metadata.name, "demo")
        XCTAssertEqual(metadata.description, "first line second line")
    }
}
