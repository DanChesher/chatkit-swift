import Foundation

/// A view model which provides a collection of all `Room`s joined by the user.
///
/// Construct an instance of this class using `Chatkit.createJoinedRoomsViewModel(...)`
///
/// This class is intended to be bound to a UICollectionView or UITableView.
///
/// The rooms are sorted in descending order of the time of their last message, or their creation time if they contain no messages.
///
/// ## Understanding the `state` of the ViewModel
///
/// The ViewModel provides both live updates to current data, and paged access to older data.
///
/// The `JoinedRoomsViewModel.state` tuple allows you to understand the current state of both:
///
/// - the `realTime` component (an instance of `RealTimeProviderState`) describes the state of the live update connection, either
///   - `.connected`: updates are flowing live, or
///   - `.degraded`: updates may be delayed due to network problems.
/// - the `paged` component (an instance of `PagedProviderState`) describes whether the fill set of data has been fetched or not, either
///   - `.fullyPopulated`: all data has been retrieved,
///   - `.partiallyPopulated`: more data can be fetched from the Chatkit service, or
///   - `.fetching`: more data is currently being requested from the Chatkit service.
///
public class JoinedRoomsViewModel {
    
    // MARK: - Properties
    
    private let provider: JoinedRoomsProvider
    
    /// The array of all rooms joined by the user.
    public private(set) var rooms: [Room]
    
    /// The current state of the provider used by the view model as the data source.
    ///
    /// - Parameters:
    ///     - realTime: The current state of the provider related to the real time web service.
    ///     - paged: The current state of the provider related to the non-real time web service.
    public var state: RealTimeProviderState {
        return self.provider.state
    }
    
    /// The object that is notified when the content of the maintained collection of rooms changed.
    public weak var delegate: JoinedRoomsViewModelDelegate?
    
    // MARK: - Initializers
    
    init(provider: JoinedRoomsProvider) {
        self.rooms = []
        
        self.provider = provider
        self.provider.delegate = self
        
        self.reload()
    }
    
    // MARK: - Private methods
    
    private func reload() {
        self.rooms = Array(self.provider.rooms)
        self.sort()
    }
    
    private func sort() {
        self.rooms.sort { lhs, rhs -> Bool in
            if let lhsLastMessage = lhs.lastMessage, let rhsLastMessage = rhs.lastMessage {
                return lhsLastMessage.createdAt > rhsLastMessage.createdAt
            }
            else {
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
    
    private func index(of room: Room) -> Int? {
        return self.rooms.firstIndex { storedRoom -> Bool in
            return storedRoom.identifier == room.identifier
        }
    }
    
}

// MARK: - JoinedRoomsProviderDelegate

/// :nodoc:
extension JoinedRoomsViewModel: JoinedRoomsProviderDelegate {
    
    public func joinedRoomsProvider(_ joinedRoomsProvider: JoinedRoomsProvider, didJoinRoom room: Room) {
        // TODO: Optimize if necessary
        
        self.rooms.append(room)
        self.sort()
        
        guard let index = self.index(of: room) else {
            return
        }
        
        self.delegate?.joinedRoomsViewModel(self, didAddRoomAt: index, changeReason: .userJoined)
    }
    
    public func joinedRoomsProvider(_ joinedRoomsProvider: JoinedRoomsProvider, didUpdateRoom room: Room, previousValue: Room) {
        // TODO: Optimize if necessary
        
        guard let previousIndex = self.index(of: previousValue) else {
            return
        }
        
        self.rooms[previousIndex] = room
        self.sort()
        
        guard let currentIndex = self.index(of: room) else {
            return
        }
        
        let currentMessage = room.lastMessage
        let previousMessage = previousValue.lastMessage
        let changeReason: JoinedRoomsViewModel.ChangeReason = currentMessage != nil && currentMessage?.identifier != previousMessage?.identifier ? .messageReceived : .dataUpdated
        
        if currentIndex != previousIndex {
            self.delegate?.joinedRoomsViewModel(self, didMoveRoomFrom: previousIndex, to: currentIndex, changeReason: changeReason)
        }
        else {
            self.delegate?.joinedRoomsViewModel(self, didUpdateRoomAt: currentIndex, changeReason: changeReason)
        }
    }
    
    public func joinedRoomsProvider(_ joinedRoomsProvider: JoinedRoomsProvider, didLeaveRoom room: Room) {
        guard let index = self.index(of: room) else {
            return
        }
        
        self.rooms.remove(at: index)
        
        self.delegate?.joinedRoomsViewModel(self, didRemoveRoomAt: index, changeReason: .userLeft)
    }
    
}

// MARK: - Delegate

/// A delegate protocol that describes methods that will be called by the associated
/// `JoinedRoomsViewModel` when the maintainted collection of rooms have changed.
public protocol JoinedRoomsViewModelDelegate: class {
    
    /// Notifies the receiver that a new room has been added to the maintened collection of rooms.
    ///
    /// - Parameters:
    ///     - joinedRoomsViewModel: The `JoinedRoomsViewModel` that called the method.
    ///     - index: The index of the room added to the maintened collection of rooms.
    ///     - changeReason: The semantic reson that triggered the change.
    func joinedRoomsViewModel(_ joinedRoomsViewModel: JoinedRoomsViewModel, didAddRoomAt index: Int, changeReason: JoinedRoomsViewModel.ChangeReason)
    
    /// Notifies the receiver that a room from the maintened collection of rooms has been updated.
    ///
    /// - Parameters:
    ///     - joinedRoomsViewModel: The `JoinedRoomsViewModel` that called the method.
    ///     - index: The index of the room updated in the maintened collection of rooms.
    ///     - changeReason: The semantic reson that triggered the change.
    func joinedRoomsViewModel(_ joinedRoomsViewModel: JoinedRoomsViewModel, didUpdateRoomAt index: Int, changeReason: JoinedRoomsViewModel.ChangeReason)
    
    /// Notifies the receiver that a room from the maintened collection of rooms has been moved.
    ///
    /// - Parameters:
    ///     - joinedRoomsViewModel: The `JoinedRoomsViewModel` that called the method.
    ///     - oldIndex: The old index of the room before the move.
    ///     - newIndex: The new index of the room after the move.
    ///     - changeReason: The semantic reson that triggered the change.
    func joinedRoomsViewModel(_ joinedRoomsViewModel: JoinedRoomsViewModel, didMoveRoomFrom oldIndex: Int, to newIndex: Int, changeReason: JoinedRoomsViewModel.ChangeReason)
    
    /// Notifies the receiver that a room from the maintened collection of rooms has been removed.
    ///
    /// - Parameters:
    ///     - joinedRoomsViewModel: The `JoinedRoomsViewModel` that called the method.
    ///     - index: The index of the room removed from the maintened collection of rooms.
    ///     - changeReason: The semantic reson that triggered the change.
    func joinedRoomsViewModel(_ joinedRoomsViewModel: JoinedRoomsViewModel, didRemoveRoomAt index: Int, changeReason: JoinedRoomsViewModel.ChangeReason)
    
}

// MARK: - Change Reason

public extension JoinedRoomsViewModel {
    
    // TODO: Define change reasons.
    /// An enumeration representing semantic reasons that might trigger a change
    /// in the `JoinedRoomsViewModel` class.
    enum ChangeReason {
        
        /// The user joined the room.
        case userJoined
        
        /// The user left the room.
        case userLeft
        
        /// A new message received by the room.
        case messageReceived
        
        /// A new value of `name` or `customData` properties received by the room.
        case dataUpdated
        
    }
    
}
