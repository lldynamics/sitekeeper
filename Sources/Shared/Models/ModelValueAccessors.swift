import Foundation

extension LaborRecord {
    /// A missing worker count is legacy workload; an explicit zero stays zero.
    var totalWorkload: QuantityValue {
        workers.isEmpty ? hours : workers * hours
    }
}
