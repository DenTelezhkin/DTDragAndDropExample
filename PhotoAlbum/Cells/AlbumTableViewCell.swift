/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A table view cell used to display a photo album in the photo library.
*/

import UIKit
import DTModelStorage

class AlbumTableViewCell: UITableViewCell, ModelTransfer {
    
    /// Returns a rect for the image view that displays the album thumbnail in the coordinate space of the cell, if it is visible.
    var rectForAlbumThumbnail: CGRect? {
        if let imageView = imageView, imageView.bounds.size.width > 0, imageView.bounds.size.height > 0, imageView.superview != nil {
            return convert(imageView.bounds, from: imageView)
        }
        return nil
    }
    
    /// Configures the cell to display the album.
    func update(with album: PhotoAlbum) {
        accessoryType = .disclosureIndicator
        textLabel?.text = album.title
        imageView?.image = album.thumbnail
    }
}
