import UIKit

/// Start and finish photos for every catalog exercise, bundled as
/// `<id>_0.jpg` / `<id>_1.jpg` from free-exercise-db (Unlicense) by
/// `scripts/exercise-photos.py`. Custom exercises have none and keep the
/// muscle map.
enum ExercisePhotos {
    struct Pair {
        let start: UIImage
        let finish: UIImage
    }

    /// UIKit's named-image cache keeps scrolling lists from decoding twice.
    static func pair(for exerciseID: String) -> Pair? {
        guard let start = UIImage(named: "\(exerciseID)_0.jpg"),
              let finish = UIImage(named: "\(exerciseID)_1.jpg") else { return nil }
        return Pair(start: start, finish: finish)
    }

    static func start(for exerciseID: String) -> UIImage? {
        UIImage(named: "\(exerciseID)_0.jpg")
    }
}
