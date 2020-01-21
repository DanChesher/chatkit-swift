import XCTest
@testable import PusherChatkit


class DummyStoreDelegate: DummyBase, StoreDelegate {
    func store(_ store: Store, didUpdateState state: State) {
        DummyFail(sender: self, function: #function)
    }
}


class StubStoreDelegate: StubBase, StoreDelegate {

    private var didUpdateState_expectedCallCount: UInt
    private(set) var didUpdateState_stateLastReceived: State?

    init(didUpdateState_expectedCallCount: UInt = 0,
         file: StaticString = #file, line: UInt = #line) {
        
        self.didUpdateState_expectedCallCount = didUpdateState_expectedCallCount
        
        super.init(file: file, line: line)
    }

    // MARK: StoreDelegate
    
    func store(_ store: Store, didUpdateState state: State) {
        guard didUpdateState_expectedCallCount > 0 else {
            XCTFail("Unexpected call of `\(#function)` made to \(String(describing: self))", file: file, line: line)
            return
        }
        didUpdateState_expectedCallCount = didUpdateState_expectedCallCount - 1
        self.didUpdateState_stateLastReceived = state
    }
}