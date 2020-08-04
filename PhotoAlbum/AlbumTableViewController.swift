/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A table view controller that displays the albums in the photo library. Supports drag and drop of the photos in each album, as well as reordering of the albums.
*/

import UIKit
import DTTableViewManager

class AlbumTableViewController: UITableViewController, DTTableViewManageable {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        manager.register(AlbumTableViewCell.self) { [unowned manager, weak self] mapping in
            mapping.shouldIndentWhileEditing { _,_,_ in false }
            mapping.editingStyle { _,_ in .none }
            mapping.moveRowTo { to, _, album, from in
                PhotoLibrary.sharedInstance.moveAlbum(at: from.row, to: to.row)
                manager.memoryStorage.moveItemWithoutAnimation(from: from, to: to)
            }
            mapping.itemsForBeginningDragSession { _, _, _, indexPath in
                guard let self = self else { return [] }
                if self.tableView.isEditing {
                    // User wants to reorder a row, don't return any drag items. The table view will allow a drag to begin for reordering only.
                    return []
                }
                return self.dragItems(forAlbumAt: indexPath)
            }
        }
        configureDrag()
        configureDrop()
        
        navigationItem.rightBarButtonItem = editButtonItem
        
        tableView.isSpringLoaded = true
        
        manager.memoryStorage.setItems(PhotoLibrary.sharedInstance.albums, forSection: 0)
    }
    
    func configureDrag() {
        manager.dragSessionWillBegin { [weak self] _ in
            self?.navigationItem.rightBarButtonItem?.isEnabled = false
        }
        manager.dragSessionDidEnd { [weak self] _ in
            self?.navigationItem.rightBarButtonItem?.isEnabled = true
        }
    }
    
    func configureDrop() {
        manager.canHandleDropSession { session in
            return session.hasItemsConforming(toTypeIdentifiers: UIImage.readableTypeIdentifiersForItemProvider)
        }
        
        manager.dropSessionDidUpdate { [weak self] session, destinationIndexPath in
            guard let tableView = self?.tableView, let storage = self?.manager.memoryStorage else { return UITableViewDropProposal(operation: .cancel)}
            if tableView.isEditing && tableView.hasActiveDrag {
                // The user is reordering albums in this table view.
                return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            } else if tableView.isEditing || tableView.hasActiveDrag {
                // Disallow drops while editing (if not reordering), or if there's already an active drag from this table view.
                return UITableViewDropProposal(operation: .forbidden)
            } else if let destinationIndexPath = destinationIndexPath, destinationIndexPath.row < storage.items(inSection: 0)?.count ?? 0 {
                // Allow drops into an existing album.
                if session.localDragSession != nil {
                    // If the drag began in this app, perform a move.
                    return UITableViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
                } else {
                    // Insert a new copy of the data if the drag originated in a different app.
                    return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
                }
            }
            
            // The destinationIndexPath is nil or does not correspond to an existing album.
            return UITableViewDropProposal(operation: .cancel)
        }
        
        manager.performDropWithCoordinator { [weak self] coordinator in
            // Since we only support dropping into existing rows, make sure the destinationIndexPath is valid.
            guard let destinationIndexPath = coordinator.destinationIndexPath, destinationIndexPath.row < self?.manager.memoryStorage.items(inSection: 0)?.count ?? 0 else { return }
            
            switch coordinator.proposal.operation {
            case .copy:
                // Receiving items from another app.
                self?.loadAndInsertItems(into: destinationIndexPath, with: coordinator)
            case .move:
                // Moving items from somewhere else in this app.
                self?.moveItems(into: destinationIndexPath, with: coordinator)
            default:
                return
            }
        }
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        // Disable spring loading while the table view is editing.
        tableView.isSpringLoaded = !editing
    }
    
    /// Performs updates to the photo library backing store, then loads the latest album values from it.
    private func updatePhotoLibrary(_ updates: (PhotoLibrary) -> Void) {
        updates(PhotoLibrary.sharedInstance)
        reloadAlbumsFromPhotoLibrary()
    }
    
    /// Loads the latest album values from the photo library backing store.
    func reloadAlbumsFromPhotoLibrary() {
        manager.memoryStorage.section(atIndex: 0)?.items = PhotoLibrary.sharedInstance.albums
    }
    
    /// Updates the visible cells to display the latest values for albums.
    func updateVisibleAlbumCells() {
        manager.updateVisibleCells { cell in
            cell.setNeedsLayout()
        }
    }
    
    /// Updates the visible album cells in this table view, as well the visible photos in the selected album.
    private func updateVisibleAlbumsAndPhotos() {
        updateVisibleAlbumCells()
        
        guard let selectedIndexPath = tableView.indexPathForSelectedRow,
            let splitViewController = splitViewController,
            let detailNavigationController = splitViewController.viewControllers.count > 1 ? splitViewController.viewControllers[1] as? UINavigationController : nil,
            let photosCollectionViewController = detailNavigationController.topViewController as? PhotoCollectionViewController
            else { return }
        
        guard let album = manager.memoryStorage.item(at: selectedIndexPath) as? PhotoAlbum else { return }
        photosCollectionViewController.loadAlbum(album, from: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let selectedIndexPath = tableView.indexPathForSelectedRow,
            let navigationController = segue.destination as? UINavigationController,
            let photosViewController = navigationController.topViewController as? PhotoCollectionViewController
            else { return }
        
        // Load the selected album in the collection view to display its photos.
        guard let album = manager.memoryStorage.item(at: selectedIndexPath) as? PhotoAlbum else { return }
        photosViewController.loadAlbum(album, from: self)
    }
    
    /// Helper method to obtain drag items for the photos inside the album at the index path.
    private func dragItems(forAlbumAt indexPath: IndexPath) -> [UIDragItem] {
        guard let album = manager.memoryStorage.item(at: indexPath) as? PhotoAlbum else { return [] }
        let dragItems = album.photos.map { (photo) -> UIDragItem in
            let itemProvider = photo.itemProvider
            let dragItem = UIDragItem(itemProvider: itemProvider)
            dragItem.localObject = photo
            dragItem.previewProvider = photo.previewProvider
            return dragItem
        }
        return dragItems
    }
    
    /// Loads data using the item provider for each item in the drop session, inserting photos inside the album as they load.
    private func loadAndInsertItems(into destinationIndexPath: IndexPath, with coordinator: UITableViewDropCoordinator) {
        guard let destinationAlbum = manager.memoryStorage.item(at: destinationIndexPath) as? PhotoAlbum else { return }
        
        for item in coordinator.items {
            let dragItem = item.dragItem
            guard dragItem.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
            
            // Start loading the image for this drag item.
            dragItem.itemProvider.loadObject(ofClass: UIImage.self) { (droppedImage, _) in
                DispatchQueue.main.async {
                    if let image = droppedImage as? UIImage {
                        // The image loaded successfully, update the photo library backing store to insert the new photo.
                        let photo = Photo(image: image)
                        self.updatePhotoLibrary { photoLibrary in
                            photoLibrary.add(photo, to: destinationAlbum)
                        }
                        self.updateVisibleAlbumsAndPhotos()
                    }
                }
            }
            
            // Animate the drag item into the cell for the album.
            if let cell = tableView.cellForRow(at: destinationIndexPath) as? AlbumTableViewCell {
                let rect = cell.rectForAlbumThumbnail ?? CGRect(origin: cell.contentView.center, size: .zero)
                coordinator.drop(dragItem, intoRowAt: destinationIndexPath, rect: rect)
            }
        }
    }
    
    /// Moves one or more photos from an album into another album.
    private func moveItems(into destinationIndexPath: IndexPath, with coordinator: UITableViewDropCoordinator) {
        guard let destinationAlbum = manager.memoryStorage.item(at: destinationIndexPath) as? PhotoAlbum else { return }
        
        for item in coordinator.items {
            let dragItem = item.dragItem
            // Use the localObject of the drag item to get the photo synchronously without needing to use the item provider.
            guard let photo = dragItem.localObject as? Photo else { continue }
            
            // Update the photo library backing store to move the photo.
            updatePhotoLibrary { photoLibrary in
                photoLibrary.movePhoto(photo, to: destinationAlbum)
            }
            
            // Animate the drag item into the cell for the album.
            if let cell = tableView.cellForRow(at: destinationIndexPath) as? AlbumTableViewCell {
                let rect = cell.rectForAlbumThumbnail ?? CGRect(origin: cell.contentView.center, size: .zero)
                coordinator.drop(dragItem, intoRowAt: destinationIndexPath, rect: rect)
            }
        }
        
        updateVisibleAlbumsAndPhotos()
    }
}
