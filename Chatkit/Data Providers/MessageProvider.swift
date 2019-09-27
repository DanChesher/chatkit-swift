import Foundation
import CoreData
import PusherPlatform

public class MessageProvider: NSObject, DataProvider {
    
    // MARK: - Properties
    
    public private(set) var isFetchingOlderMessages: Bool
    public let logger: PPLogger?
    
    public weak var delegate: MessageProviderDelegate? {
        didSet {
            if delegate == nil {
                self.messageFactory.stopReceivingNewMessages()
            }
            else {
                self.messageFactory.startReceivingNewMessages()
            }
        }
    }
    
    private let persistenceController: PersistenceController
    private let roomID: NSManagedObjectID
    private let fetchedResultsController: FetchedResultsController<MessageEntity>
    
    private let messageFactory: MessageEntityFactory
    
    // MARK: - Accessors
    
    public var numberOfAvailableMessages: Int {
        return self.fetchedResultsController.numberOfObjects
    }
    
    // MARK: - Initializers
    
    init(room: Room, persistenceController: PersistenceController, logger: PPLogger? = nil) {
        self.persistenceController = persistenceController
        self.roomID = room.objectID
        self.isFetchingOlderMessages = false
        self.logger = logger
        
        self.messageFactory = MessageEntityFactory(roomID: room.objectID, persistenceController: self.persistenceController)
        
        let context = self.persistenceController.mainContext
        let predicate = NSPredicate(format: "%K == %@", #keyPath(MessageEntity.room), self.roomID)
        let sortDescriptor = NSSortDescriptor(key: #keyPath(MessageEntity.identifier), ascending: true) { (lhs, rhs) -> ComparisonResult in
            guard let lhsString = lhs as? String, let lhs = Int(lhsString), let rhsString = rhs as? String, let rhs = Int(rhsString) else {
                return .orderedSame
            }
            
            return NSNumber(value: lhs).compare(NSNumber(value: rhs))
        }
        
        self.fetchedResultsController = FetchedResultsController(sortDescriptors: [sortDescriptor], predicate: predicate, context: context)
        
        super.init()
        
        self.fetchedResultsController.delegate = self
        
        self.messageFactory.receiveInitialMessages(numberOfMessages: 10, delay: 1.0)
    }
    
    // MARK: - Public methods
    
    public func message(at index: Int) -> Message? {
        return (try? self.fetchedResultsController.object(at: index)?.snapshot()) ?? nil
    }
    
    public func fetchOlderMessages(numberOfMessages: UInt, completionHandler: CompletionHandler? = nil) {
        guard !self.isFetchingOlderMessages, let lastMessageIdentifier = self.message(at: 0)?.identifier else {
            if let completionHandler = completionHandler {
                // TODO: Return error
                completionHandler(nil)
            }
            
            return
        }
        
        self.isFetchingOlderMessages = true
        
        self.messageFactory.receiveOldMessages(numberOfMessages: Int(numberOfMessages), lastMessageIdentifier: lastMessageIdentifier, delay: 1.0) {
            self.isFetchingOlderMessages = false
            
            if let completionHandler = completionHandler {
                completionHandler(nil)
            }
        }
    }
    
}

extension MessageProvider: FetchedResultsControllerDelegate {
    func fetchedResultsController<ResultType>(_ fetchedResultsController: FetchedResultsController<ResultType>, didInsertObjectsWithRange range: Range<Int>) where ResultType : NSManagedObject {
        self.delegate?.messageProvider(self, didReceiveMessagesWithRange: range)
    }
    
    func fetchedResultsController<ResultType>(_ fetchedResultsController: FetchedResultsController<ResultType>, didUpdateObject: ResultType, at index: Int) where ResultType : NSManagedObject {
        guard let object = self.fetchedResultsController.object(at: index), let message = try? object.snapshot() else {
            return
        }
        
        self.delegate?.messageProvider(self, didChangeMessageAtIndex: index, previousValue: message)
    }
    
    func fetchedResultsController<ResultType>(_ fetchedResultsController: FetchedResultsController<ResultType>, didDeleteObject: ResultType, at index: Int) where ResultType : NSManagedObject {
        guard let object = self.fetchedResultsController.object(at: index), let message = try? object.snapshot() else {
            return
        }
        
        self.delegate?.messageProvider(self, didDeleteMessageAtIndex: index, previousValue: message)
    }
    
}

// MARK: - Delegate

public protocol MessageProviderDelegate: class {
    
    func messageProvider(_ messageProvider: MessageProvider, didReceiveMessagesWithRange range: Range<Int>)
    func messageProvider(_ messageProvider: MessageProvider, didChangeMessageAtIndex index: Int, previousValue: Message)
    func messageProvider(_ messageProvider: MessageProvider, didDeleteMessageAtIndex index: Int, previousValue: Message)
    
}