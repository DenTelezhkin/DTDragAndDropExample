/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A collection view controller that displays the photos in a photo album. Supports drag and drop and reordering of photos in the album.
*/

import UIKit

class PhotoCollectionViewController: UICollectionViewController, DTCollectionViewManageable {
    
    private weak var albumTableViewController: AlbumTableViewController?
    
    private var album: PhotoAlbum? {
        didSet {
            title = album?.title
        }
    }
    
    /// Stores the album state when the drag begins.
    private var albumBeforeDrag: PhotoAlbum?
    
    private func photo(at indexPath: IndexPath) -> Photo {
        return manager.memoryStorage.item(at: indexPath) as! Photo
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        manager.startManaging(withDelegate: self)
        manager.register(PhotoCollectionViewCell.self)
        configureDrag()
        configureDrop()
        
        updateRightBarButtonItem()
        
        manager.memoryStorage.setItems(album?.photos ?? [])
    }
    
    func configureDrag() {
        manager.itemsForBeginningDragSession(from: PhotoCollectionViewCell.self) { [weak self] _, _, _, indexPath in
            return [self?.dragItem(forPhotoAt: indexPath)].flatMap { $0 }
        }
        manager.itemsForAddingToDragSession(from: PhotoCollectionViewCell.self) { [weak self] _, _, _, _, indexPath in
            return [self?.dragItem(forPhotoAt: indexPath)].flatMap { $0 }
        }
        manager.dragPreviewParameters(for: PhotoCollectionViewCell.self) { cell, _, _  in
            let previewParameters = UIDragPreviewParameters()
            previewParameters.visiblePath = UIBezierPath(rect: cell.clippingRectForPhoto)
            return previewParameters
        }
        manager.dragSessionWillBegin { [weak self] _ in
            self?.albumBeforeDrag = self?.album
        }
        manager.dragSessionDidEnd { [weak self] _ in
            guard let collectionView = self?.collectionView else { return }
            if let uuid = self?.album?.identifier, let newAlbum = PhotoLibrary.sharedInstance.album(for: uuid) {
                self?.deleteItems(forPhotosMovedFrom: collectionView, albumAfterDrag: newAlbum)
            }
            self?.albumBeforeDrag = nil
            self?.reloadAlbums()
        }
    }
    
    func configureDrop() {
        manager.canHandleDropSession { [weak self] session in
            guard self?.album != nil else { return false}
            return session.hasItemsConforming(toTypeIdentifiers: UIImage.readableTypeIdentifiersForItemProvider)
        }
        manager.dropSessionDidUpdate { session, _ in
            if session.localDragSession != nil {
                return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            } else {
                return UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
            }
        }
        manager.dropPreviewParameters { [weak self] indexPath in
            guard let cell = self?.collectionView?.cellForItem(at: indexPath) as? PhotoCollectionViewCell else { return nil }
            let previewParameters = UIDragPreviewParameters()
            previewParameters.visiblePath = UIBezierPath(rect: cell.clippingRectForPhoto)
            return previewParameters
        }
        manager.performDropWithCoordinator { [weak self] coordinator in
            guard self?.album != nil else { return }

            let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: 0, section: 0)

            switch coordinator.proposal.operation {
            case .copy:
                // Receiving items from another app.
                self?.loadAndInsertItems(at: destinationIndexPath, with: coordinator)
            case .move:
                let items = coordinator.items
                if items.contains(where: { $0.sourceIndexPath != nil }) {
                    if items.count == 1, let item = items.first {
                        // Reordering a single item from this collection view.
                        self?.reorder(item, to: destinationIndexPath, with: coordinator)
                    }
                } else {
                    // Moving items from somewhere else in this app.
                    self?.moveItems(to: destinationIndexPath, with: coordinator)
                }
            default: return
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        stopInsertions()
    }
    
    private var isPerformingAutomaticInsertions = false
    
    private func updateRightBarButtonItem() {
        let startInsertionsBarButtonItem = UIBarButtonItem(title: "Start Insertions", style: .plain, target: self, action: #selector(startInsertions))
        let stopInsertionsBarButtonItem = UIBarButtonItem(title: "Stop Insertions", style: .done, target: self, action: #selector(stopInsertions))
        navigationItem.rightBarButtonItem = isPerformingAutomaticInsertions ? stopInsertionsBarButtonItem : startInsertionsBarButtonItem
    }
    
    @objc
    private func startInsertions() {
        guard let album = album else { return }
        PhotoLibrary.sharedInstance.startAutomaticInsertions(into: album, photoCollectionViewController: self)
        isPerformingAutomaticInsertions = true
        updateRightBarButtonItem()
    }
    
    @objc
    private func stopInsertions() {
        PhotoLibrary.sharedInstance.stopAutomaticInsertions()
        isPerformingAutomaticInsertions = false
        updateRightBarButtonItem()
    }
    
    func loadAlbum(_ album: PhotoAlbum, from albumTableViewController: AlbumTableViewController) {
        self.album = album
        self.albumTableViewController = albumTableViewController
        if albumBeforeDrag == nil {
            collectionView?.reloadData()
        }
    }
    
    /// Performs updates to the photo library backing store, then loads the latest album & photo values from it.
    private func updatePhotoLibrary(updates: (PhotoLibrary) -> Void) {
        updates(PhotoLibrary.sharedInstance)
    }
    
    /// Loads the latest album & photo values from the photo library backing store.
    private func reloadAlbumFromPhotoLibrary() {
        if let albumIdentifier = album?.identifier {
            album = PhotoLibrary.sharedInstance.album(for: albumIdentifier)
        }
        reloadAlbums()
    }
    
    private func reloadAlbums() {
        albumTableViewController?.reloadAlbumsFromPhotoLibrary()
        albumTableViewController?.updateVisibleAlbumCells()
    }
    
    /// Called when an photo has been automatically inserted into the album this collection view is displaying.
    func insertedItem(_ item: Any, at index: Int) {
        _ = try? manager.memoryStorage.insertItem(item, to: IndexPath(item: index, section: 0))
        reloadAlbums()
    }
    
    /// Helper method to obtain a drag item for the photo at the index path.
    private func dragItem(forPhotoAt indexPath: IndexPath) -> UIDragItem {
        let photo = self.photo(at: indexPath)
        let itemProvider = photo.itemProvider
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = photo
        return dragItem
    }
    
    /// Compares the album state before & after the drag to delete items in the collection view that represent photos moved elsewhere.
    private func deleteItems(forPhotosMovedFrom collectionView: UICollectionView, albumAfterDrag: PhotoAlbum) {
        guard let albumBeforeDrag = albumBeforeDrag else { return }
        
        var indexPathsToDelete = [IndexPath]()
        for (index, photo) in albumBeforeDrag.photos.enumerated() {
            if !albumAfterDrag.photos.contains(photo) {
                indexPathsToDelete.append(IndexPath(item: index, section: 0))
            }
        }
        manager.memoryStorage.removeItems(at: indexPathsToDelete)
    }
    
    /// Loads data using the item provider and inserts a new item in the collection view for each item in the drop session, using placeholders while the data loads asynchronously.
    private func loadAndInsertItems(at destinationIndexPath: IndexPath, with coordinator: UICollectionViewDropCoordinator) {
        guard let album = album else { return }
        
        for item in coordinator.items {
            let dragItem = item.dragItem
            guard dragItem.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
            
            var placeholderContext: DTCollectionViewDropPlaceholderContext? = nil
            
            // Start loading the image for this drag item.
            let progress = dragItem.itemProvider.loadObject(ofClass: UIImage.self) { (droppedImage, _) in
                if let image = droppedImage as? UIImage {
                    let photo = Photo(image: image)
                    // The image loaded successfully, commit the insertion to exchange the placeholder for the final cell.
                    placeholderContext?.commitInsertion(ofItem: photo, { insertionIndexPath in
                        // Update the photo library backing store to insert the new photo, using the insertionIndexPath passed into the closure.
                        self.updatePhotoLibrary { photoLibrary in
                            photoLibrary.insert(photo, into: album, at: insertionIndexPath.item)
                        }
                        self.reloadAlbums()
                    })
                } else {
                    // The data transfer for this item was canceled or failed, delete the placeholder.
                    placeholderContext?.deletePlaceholder()
                }
            }
            let placeholder = UICollectionViewDropPlaceholder(insertionIndexPath: destinationIndexPath, reuseIdentifier: PhotoPlaceholderCollectionViewCell.identifier)
            placeholder.cellUpdateHandler = { cell in
                guard let placeholderCell = cell as? PhotoPlaceholderCollectionViewCell else { return }
                placeholderCell.configure(with: progress)
            }
            
            // Insert and animate to a placeholder for this item, configuring the placeholder cell to display the progress of the data transfer for this item.
            placeholderContext = manager.drop(dragItem, to: placeholder, with: coordinator)
        }
        
        // Disable the system progress indicator as we are displaying the progress of drag items in the placeholder cells.
        coordinator.session.progressIndicatorStyle = .none
    }
    
    /// Moves an item (photo) in this collection view from one index path to another index path.
    private func reorder(_ item: UICollectionViewDropItem, to destinationIndexPath: IndexPath, with coordinator: UICollectionViewDropCoordinator) {
        guard let album = album, let sourceIndexPath = item.sourceIndexPath else { return }
        
        // Update the photo library backing store and perform the move on an item in collection view.
        updatePhotoLibrary { photoLibrary in
            photoLibrary.movePhoto(in: album, from: sourceIndexPath.item, to: destinationIndexPath.item)
        }
        reloadAlbums()
        manager.memoryStorage.moveItem(at: sourceIndexPath, to: destinationIndexPath)
        
        // Animate the drag item to the newly inserted item in the collection view.
        coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
    }
    
    /// Moves one or more photos from a different album into this album by inserting items into this collection view.
    private func moveItems(to destinationIndexPath: IndexPath, with coordinator: UICollectionViewDropCoordinator) {
        guard let album = album else { return }
        
        var destinationIndex = destinationIndexPath.item
        for item in coordinator.items {
            // Use the localObject of the drag item to get the photo synchronously without needing to use the item provider.
            guard let photo = item.dragItem.localObject as? Photo, !album.contains(photo: photo) else { continue }
            
            let insertionIndexPath = IndexPath(item: destinationIndex, section: 0)
            
            // Perform batch updates to update the photo library backing store and perform the insert on the collection view.
            updatePhotoLibrary { photoLibrary in
                photoLibrary.movePhoto(photo, to: album, index: destinationIndex)
            }
            reloadAlbums()
            _ = try? manager.memoryStorage.insertItem(photo, to: insertionIndexPath)
            
            // Animate the drag item to the newly inserted item in the collection view.
            coordinator.drop(item.dragItem, toItemAt: insertionIndexPath)
            
            destinationIndex += 1
        }
    }
    
}
