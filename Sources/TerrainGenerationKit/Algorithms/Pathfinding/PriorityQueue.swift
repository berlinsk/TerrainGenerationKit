import Foundation

public struct PriorityQueue<T: Comparable> {
    
    private var heap: [T] = []
    
    public var isEmpty: Bool {
        heap.isEmpty
    }
    
    public var count: Int {
        heap.count
    }
    
    public init() {}
    
    public mutating func insert(_ element: T) {
        heap.append(element)
        siftUp(heap.count - 1)
    }
    
    public mutating func pop() -> T? {
        guard !heap.isEmpty else {
            return nil
        }
        if heap.count == 1 {
            return heap.removeLast()
        }
        
        let first = heap[0]
        heap[0] = heap.removeLast()
        siftDown(0)
        return first
    }
    
    public func peek() -> T? {
        heap.first
    }
    
    private mutating func siftUp(_ index: Int) {
        var child = index
        var parent = (child - 1) / 2
        
        while child > 0 && heap[child] < heap[parent] {
            heap.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }
    
    private mutating func siftDown(_ index: Int) {
        var parent = index
        
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent
            
            if left < heap.count && heap[left] < heap[smallest] {
                smallest = left
            }
            if right < heap.count && heap[right] < heap[smallest] {
                smallest = right
            }
            
            if smallest == parent {
                break
            }
            
            heap.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
