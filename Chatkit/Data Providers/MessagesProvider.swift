import Foundation
import CoreData
import PusherPlatform

/// A provider which exposes a collection of messages for a given room.
///
/// Initially the most recent messages are available.
///
/// New messages are added in real time.
///
/// More older messages can be fetched and added to the collection by calling methods on this provider.
public class MessagesProvider {
    
    // MARK: - Properties
    
    /// The identifier of the room for which the provider manages a collection of messages.
    public let roomIdentifier: String
    
    /// The current state of the provider.
    ///
    /// - Parameters:
    ///     - realTime: The current state of the provider related to the real time web service.
    ///     - paged: The current state of the provider related to the non-real time web service.
    public private(set) var state: (realTime: RealTimeProviderState, paged: PagedProviderState)
    
    /// The object that is notified when the list `messages` has changed.
    public weak var delegate: MessagesProviderDelegate?
    
    private let roomManagedObjectID: NSManagedObjectID
    private let fetchedResultsController: FetchedResultsController<MessageEntity>
    private let dataSimulator: DataSimulator
    
    /// The array of available messages for the given room.
    ///
    /// The array contains all messages for the room which have been received by the client device.
    ///
    /// Initially this will be some of the most recent messages.
    ///
    /// New messages are always added to this array.
    ///
    /// If more older messages are required, call `fetchOlderMessages(...)` to have them added to this array.
    public var messages: [Message] {
        return self.fetchedResultsController.objects.compactMap { try? $0.snapshot() }
    }
    
    // A quick and dirty hack that is here to enable user testing. We should get rid of this in the final version.
    private static var controllers = [String : FetchedResultsController<MessageEntity>]()
    
    // MARK: - Initializers
    
    init(room: Room, persistenceController: PersistenceController, dataSimulator: DataSimulator) {
        self.roomIdentifier = room.identifier
        
        self.dataSimulator = dataSimulator
        self.roomManagedObjectID = room.objectID
        
        self.state.realTime = .connected
        self.state.paged = dataSimulator.pagedState(for: room.objectID)
        
        let context = persistenceController.mainContext
        let predicate = NSPredicate(format: "%K == %@", #keyPath(MessageEntity.room), self.roomManagedObjectID)
        let sortDescriptor = NSSortDescriptor(key: #keyPath(MessageEntity.identifier), ascending: true) { (lhs, rhs) -> ComparisonResult in
            guard let lhsString = lhs as? String, let lhs = Int(lhsString), let rhsString = rhs as? String, let rhs = Int(rhsString) else {
                return .orderedSame
            }
            
            return NSNumber(value: lhs).compare(NSNumber(value: rhs))
        }
        
        if let fetchedResultsController = MessagesProvider.controllers[room.identifier] {
            self.fetchedResultsController = fetchedResultsController
        }
        else {
            self.fetchedResultsController = FetchedResultsController(sortDescriptors: [sortDescriptor], predicate: predicate, context: context)
            MessagesProvider.controllers[room.identifier] = self.fetchedResultsController
        }
        
        self.fetchedResultsController.delegate = self
    }
    
    // MARK: - Methods
    
    /// Fetch more old messages from the Chatkit service and add them to the `messages` array.
    ///
    /// This call is asynchronous because messages may need to be retrieved from the network.
    ///
    /// On success, the completion handler receives `nil`, and the messages are added to the `messages` array.
    ///
    /// The `delegate` will be informed of the change to the `messages` array.
    ///
    /// - Parameters:
    ///     - numberOfMessages: The maximum number of messages that should be retrieved from
    ///     the web service.
    ///     - completionHandler:An optional completion handler invoked when the operation is complete.
    ///     The completion handler receives an Error, or nil on success.
    public func fetchOlderMessages(numberOfMessages: UInt, completionHandler: CompletionHandler? = nil) {
        guard self.state.paged == .partiallyPopulated else {
            if let completionHandler = completionHandler {
                // TODO: Return error
                completionHandler(nil)
            }
            
            return
        }
        
        self.state.paged = .fetching
        
        self.dataSimulator.fetchOlderMessages(for: self.roomManagedObjectID) {
            self.state.paged = self.dataSimulator.pagedState(for: self.roomManagedObjectID)
            
            if let completionHandler = completionHandler {
                completionHandler(nil)
            }
        }
    }
    
    /// Marks the `lastReadMessage` and all preceding messages as read.
    ///
    /// This will propagate to the currrent user's unread counts and other users which are watching the read state of the message via the Chatkit service.
    ///
    /// - Parameters:
    ///     - lastReadMessage: The last message read by the user.
    public func markMessagesAsRead(lastReadMessage: Message) {
        self.dataSimulator.markMessagesAsRead(lastReadMessage: lastReadMessage)
    }
    
    // MARK: - Memory management
    
    deinit {
        self.fetchedResultsController.delegate = nil
    }
    
}

// MARK: - FetchedResultsControllerDelegate

extension MessagesProvider: FetchedResultsControllerDelegate {
    
    func fetchedResultsController<ResultType>(_ fetchedResultsController: FetchedResultsController<ResultType>, didInsertObjectsWithRange range: Range<Int>) where ResultType : NSManagedObject {
        if range.lowerBound == 0 {
            let messages = self.fetchedResultsController.objects[range].compactMap { try? $0.snapshot() }
            self.delegate?.messagesProvider(self, didReceiveOlderMessages: messages)
        }
        else {
            for index in range {
                guard index < self.fetchedResultsController.numberOfObjects,
                    let entity = self.fetchedResultsController.object(at: index),
                    let message = try? entity.snapshot() else {
                        continue
                }
                
                self.delegate?.messagesProvider(self, didReceiveNewMessage: message)
            }
        }
    }
    
    func fetchedResultsController<ResultType>(_ fetchedResultsController: FetchedResultsController<ResultType>, didUpdateObject object: ResultType, at index: Int) where ResultType : NSManagedObject {
        guard let object = object as? MessageEntity, let message = try? object.snapshot() else {
            return
        }
        
        // TODO: Generate the old value based on the new value and the changeset.
        
        self.delegate?.messagesProvider(self, didUpdateMessage: message, previousValue: message)
    }
    
    func fetchedResultsController<ResultType>(_ fetchedResultsController: FetchedResultsController<ResultType>, didDeleteObject object: ResultType, at index: Int) where ResultType : NSManagedObject {
        guard let object = object as? MessageEntity, let message = try? object.snapshot() else {
            return
        }
        
        self.delegate?.messagesProvider(self, didRemoveMessage: message)
    }
    
}

// MARK: - Delegate

/// A delegate protocol for being notified when the `messages` array of a `MessagesProvider` has changed.
public protocol MessagesProviderDelegate: class {
    
    /// Called when old messages requested with `MessagesProvider.fetchOlderMessages(...)` have been added to the collection.
    ///
    /// - Parameters:
    ///     - messagesProvider: The `MessagesProvider` that called the method.
    ///     - messages: The array of older messages received from the web service.
    func messagesProvider(_ messagesProvider: MessagesProvider, didReceiveOlderMessages messages: [Message])
    
    /// Called when new messages have been added to the collection.
    ///
    /// - Parameters:
    ///     - messagesProvider: The `MessagesProvider` that called the method.
    ///     - messages: The new message received from the web service.
    func messagesProvider(_ messagesProvider: MessagesProvider, didReceiveNewMessage message: Message)
    
    /// Called when a message in the collection has been updated.
    ///
    /// - Parameters:
    ///     - messagesProvider: The `MessagesProvider` that called the method.
    ///     - message: The updated value of the message.
    ///     - previousValue: The value of the message prior to the update.
    func messagesProvider(_ messagesProvider: MessagesProvider, didUpdateMessage message: Message, previousValue: Message)
    
    /// Called when a message in the collection has been deleted.
    ///
    /// - Parameters:
    ///     - messagesProvider: The `MessagesProvider` that called the method.
    ///     - message: The message removed from the maintened collection of messages.
    func messagesProvider(_ messagesProvider: MessagesProvider, didRemoveMessage message: Message)
    
}