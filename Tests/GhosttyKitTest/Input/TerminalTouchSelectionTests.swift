import Foundation
import Testing

@testable import GhosttyTerminal

@MainActor
struct TerminalTouchSelectionTests {
    @Test func geometryIncludesLargePaddingAndRetinaScale() throws {
        let grid = try #require(
            TerminalSelectionGrid(
                metrics: .init(
                    columns: 10, rows: 5, widthPixels: 240, heightPixels: 300,
                    cellWidthPixels: 20, cellHeightPixels: 40
                ),
                scale: 2, firstBaseline: CGPoint(x: 12, y: 54), imeBottom: 100
            )
        )
        #expect(grid.origin == CGPoint(x: 12, y: 40))
        #expect(grid.cell(at: CGPoint(x: 35, y: 65), viewportOffset: 50) == 512)
        #expect(
            grid.rects(for: 509 ... 521, viewportOffset: 50) == [
                CGRect(x: 102, y: 40, width: 10, height: 20),
                CGRect(x: 12, y: 60, width: 100, height: 20),
                CGRect(x: 12, y: 80, width: 20, height: 20),
            ]
        )
        #expect(grid.rects(for: 0 ... 20, viewportOffset: 50).isEmpty)
    }

    @Test func readsAndSelectsWideAndCombinedCharactersWithoutMouseInput() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)
        let columns = Int(try #require(surface.size()).columns)
        harness.receive("\u{1B}[2J\u{1B}[Hhello 你好 e\u{301} 😀\r\nsecond line\u{1B}[?1003h\u{1B}[?1006h")
        #expect(surface.readCells(0 ... 4, columns: columns)?.text == "hello")
        #expect(surface.wordCells(at: 7, columns: columns) == 6 ... 9)
        #expect(surface.glyphCells(at: 7, columns: columns) == 6 ... 7)
        #expect(surface.readCells(6 ... 9, columns: columns)?.text == "你好")
        #expect(surface.readCells(11 ... 11, columns: columns)?.text == "e\u{301}")
        #expect(surface.glyphCells(at: 14, columns: columns) == 13 ... 14)
        #expect(surface.readCells(columns ... (columns + 5), columns: columns)?.text == "second")
        let bytes = await harness.drain()
        #expect(!bytes.contains(Data("\u{1B}[<".utf8)))
    }

    @Test func nearestTextRowSkipsWhitespaceAndStaysWithinTheVisibleRows() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)
        let metrics = try #require(surface.size())
        let columns = Int(metrics.columns)
        let rows = 0 ..< Int(metrics.rows)
        #expect(surface.nearestTextRow(to: 3, in: rows, columns: columns) == nil)
        harness.receive("\u{1B}[2J\u{1B}[Hfirst row\r\n   \r\n你好\r\n\r\nlast row")
        #expect(surface.nearestTextRow(to: 0, in: rows, columns: columns) == 0)
        #expect(surface.nearestTextRow(to: 1, in: rows, columns: columns) == 0)
        #expect(surface.nearestTextRow(to: 3, in: rows, columns: columns) == 2)
        #expect(surface.nearestTextRow(to: rows.upperBound - 1, in: rows, columns: columns) == 4)
        #expect(surface.nearestTextRow(to: 1, in: 1 ..< 4, columns: columns) == 2)
        #expect(surface.nearestTextRow(to: 5, in: 5 ..< rows.upperBound, columns: columns) == nil)
    }

    @Test func selectAllStopsAfterContentAndKeepsBothCellsOfTheLastGlyph() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)
        let metrics = try #require(surface.size())
        let columns = Int(metrics.columns)
        harness.receive("\u{1B}[2J\u{1B}[Hhello\r\n你好")
        #expect(surface.lastTextCell(rows: Int(metrics.rows), columns: columns) == columns + 3)
        #expect(surface.readCells(0 ... (columns + 3), columns: columns)?.text == "hello\n你好")
    }

    @Test func copyingAcrossSoftWrapsDoesNotInsertNewlines() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)
        let columns = Int(try #require(surface.size()).columns)
        let text = String(repeating: "a", count: columns - 2) + "你好tail"
        harness.receive("\u{1B}[2J\u{1B}[H" + text)
        #expect(surface.readCells(0 ... (columns + 5), columns: columns)?.text == text)
    }

    @Test func readsAbsoluteHistoryRowsBeforeAndAfterScrolling() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)
        let metrics = try #require(surface.size())
        let columns = Int(metrics.columns)
        let lines = (0 ..< (Int(metrics.rows) * 3)).map { String(format: "history-%03d", $0) }
        harness.receive("\u{1B}[2J\u{1B}[H" + lines.joined(separator: "\r\n"))
        for row in [0, Int(metrics.rows), lines.count - 1] {
            let start = row * columns
            #expect(surface.readCells(start ... (start + 10), columns: columns)?.text == lines[row])
        }
        #expect(surface.scrollToRow(10))
        for row in [0, Int(metrics.rows), lines.count - 1] {
            let start = row * columns
            #expect(surface.readCells(start ... (start + 10), columns: columns)?.text == lines[row])
        }
        #expect(surface.readCells(0 ... 10, columns: columns, viewport: true)?.text == lines[10])
    }
}
