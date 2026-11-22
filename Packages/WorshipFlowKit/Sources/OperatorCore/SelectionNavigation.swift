// FIX-I item 2: where an arrow key moves the selection in the slide grid and in the media bin. Pure index arithmetic; the views supply the
// number of columns they really draw. Foundation only.
import Foundation

public enum BinNavigation {
    /// The index the selection moves to in a bin of `count` items drawn `columns` across, row by row. The selection stops at the ends (it does
    /// not wrap); Up and Down stay put when there is no row above or below, and land on the last item of a short last row. Nothing selected
    /// yet starts at the first item. Nil only for an empty bin.
    public static func target(count: Int, current: Int?, move: SelectionMove, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current, (0..<count).contains(current) else { return 0 }
        let width = max(1, columns)
        switch move {
        case .left: return max(0, current - 1)
        case .right: return min(count - 1, current + 1)
        case .up: return current - width >= 0 ? current - width : current
        case .down:
            if current + width < count { return current + width }
            // A short last row: go to its last item when there is a row below at all.
            let lastRow = (count - 1) / width
            return current / width < lastRow ? count - 1 : current
        }
    }
}

public enum SlideGridNavigation {
    /// The slide the selection moves to from `index` in a grid `columns` across, laid out as `runs` (one array of slide indices per section; each
    /// section starts a new row). Left and Right step one slide through the whole deck; Up and Down step a row, into the neighbouring section at
    /// the same column (or its last slide of a short row). Nil when the move leaves the deck: the caller may then cross into the neighbouring
    /// playlist item for Left and Right, and does nothing for Up and Down.
    public static func target(from index: Int, move: SelectionMove, columns: Int, runs: [[Int]]) -> Int? {
        let width = max(1, columns)
        let all = runs.flatMap { $0 }
        switch move {
        case .left: return index - 1 >= 0 && all.contains(index - 1) ? index - 1 : nil
        case .right: return all.contains(index + 1) ? index + 1 : nil
        case .up, .down:
            guard let r = runs.firstIndex(where: { $0.contains(index) }), let position = runs[r].firstIndex(of: index) else { return nil }
            let row = position / width, column = position % width
            if move == .down {
                let below = (row + 1) * width + column
                if below < runs[r].count { return runs[r][below] }
                if (row + 1) * width < runs[r].count { return runs[r].last }                // a short last row
                guard r + 1 < runs.count, !runs[r + 1].isEmpty else { return nil }
                let next = runs[r + 1]
                return next[min(column, next.count - 1)]
            } else {
                if row > 0 { return runs[r][(row - 1) * width + column] }
                guard r > 0, !runs[r - 1].isEmpty else { return nil }
                let previous = runs[r - 1]
                let lastRowStart = ((previous.count - 1) / width) * width
                return previous[min(lastRowStart + column, previous.count - 1)]
            }
        }
    }
}
