/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A collection view cell used to display a photo in a photo album.
*/

import UIKit

class PhotoCollectionViewCell: UICollectionViewCell, ModelTransfer {
    
    @IBOutlet private weak var photoImageView: UIImageView!
    
    var clippingRectForPhoto: CGRect {
        return photoImageView.contentClippingRect
    }
    
    /// Configures the cell to display the photo.
    func update(with photo: Photo) {
        photoImageView.image = photo.image
    }
}
