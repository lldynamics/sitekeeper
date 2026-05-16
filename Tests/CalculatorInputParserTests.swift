import Testing
@testable import sitekeeper

struct CalculatorInputParserTests {
    @Test func doubleParsesGroupedInteger() {
        #expect(CalculatorInputParser.double("1,234") == 1234)
    }

    @Test func doubleParsesCommaDecimal() {
        let value = CalculatorInputParser.double("1,5")
        #expect(abs((value ?? 0) - 1.5) < 0.000_001)
    }

    @Test func doubleParsesMixedSeparators() {
        let value = CalculatorInputParser.double("1.234,56")
        #expect(abs((value ?? 0) - 1234.56) < 0.000_001)
    }

    @Test func doubleRejectsNonNumericInput() {
        #expect(CalculatorInputParser.double("abc") == nil)
        #expect(CalculatorInputParser.double("￥1,234") == nil)
    }
}
