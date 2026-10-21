import CoreMotion
import SpriteKit
import SwiftUI
import UIKit

/// Where plates sit when the table is at rest: a centred grid of square
/// cells, top-left origin. The SpriteKit scene starts every plate from
/// the same cell, so pressing Play lets go of the plates exactly where
/// they were drawn.
enum PlateTableLayout {
    static func cells(count: Int, in size: CGSize, spacing: CGFloat = Spacing.lg) -> [CGRect] {
        guard count > 0, size.width > 0, size.height > 0 else { return [] }
        let columns = count == 1 ? 1 : (count <= 6 ? 2 : 3)
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let side = max(0, min(
            (size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns),
            (size.height - spacing * CGFloat(rows + 1)) / CGFloat(rows)
        ))
        let blockWidth = side * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let blockHeight = side * CGFloat(rows) + spacing * CGFloat(rows - 1)
        let origin = CGPoint(x: (size.width - blockWidth) / 2, y: (size.height - blockHeight) / 2)
        return (0..<count).map { index in
            let row = index / columns
            let itemsInRow = min(columns, count - row * columns)
            // A short last row is centred rather than left-aligned.
            let rowInset = CGFloat(columns - itemsInRow) * (side + spacing) / 2
            return CGRect(
                x: origin.x + rowInset + CGFloat(index % columns) * (side + spacing),
                y: origin.y + CGFloat(row) * (side + spacing),
                width: side,
                height: side
            )
        }
    }

    /// `image` fitted inside `cell`, centred.
    static func fit(_ image: CGSize, in cell: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return cell }
        let scale = min(cell.width / image.width, cell.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// The table in play: every dish a rigid body that falls toward wherever
/// the phone is tilted, knocks into the others, and can be flicked.
final class PlateTableScene: SKScene, SKPhysicsContactDelegate {

    enum Mode: CaseIterable, Identifiable {
        /// Gravity follows the phone.
        case tumble
        /// No gravity; plates drift and bounce off the edges.
        case drift

        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .tumble: "Tumble"
            case .drift:  "Drift"
            }
        }

        var icon: String {
            switch self {
            case .tumble: "arrow.down.circle"
            case .drift:  "wind"
            }
        }
    }

    struct Plate {
        let id: UUID
        let image: UIImage
        let label: String
        /// Starting frame in SwiftUI's top-left coordinates.
        let frame: CGRect
    }

    var onTap: ((UUID) -> Void)?

    private let motion = CMMotionManager()
    private var plates: [UUID: SKSpriteNode] = [:]
    private var labels: [UUID: SKLabelNode] = [:]
    private var mode: Mode = .tumble
    private var showsLabels = true
    private var lastBump: TimeInterval = 0
    private var grab: (node: SKSpriteNode, start: CGPoint, time: TimeInterval, moved: Bool)?

    /// Points per metre in SpriteKit's physics; gravity is in m/s².
    private static let earth: CGFloat = 9.8
    private static let bumpImpulse: CGFloat = 12
    private static let bumpInterval: TimeInterval = 0.12

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.contactDelegate = self
    }

    required init?(coder aDecoder: NSCoder) { return nil }

    override func didMove(to view: SKView) {
        updateEdges()
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 60
        motion.startDeviceMotionUpdates()
    }

    override func willMove(from view: SKView) {
        motion.stopDeviceMotionUpdates()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        updateEdges()
    }

    private func updateEdges() {
        let edges = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
        edges.friction = 0.3
        edges.restitution = 0.3
        physicsBody = edges
    }

    // MARK: - Plates

    func place(_ newPlates: [Plate], labelColor: UIColor) {
        plates.values.forEach { $0.removeFromParent() }
        labels.values.forEach { $0.removeFromParent() }
        plates = [:]
        labels = [:]
        let font = UIFont.preferredFont(forTextStyle: .caption1)
        for plate in newPlates {
            let node = SKSpriteNode(texture: SKTexture(image: plate.image), size: plate.frame.size)
            node.position = CGPoint(x: plate.frame.midX, y: size.height - plate.frame.midY)
            node.name = plate.id.uuidString
            node.physicsBody = body(for: node)
            addChild(node)
            plates[plate.id] = node

            let label = SKLabelNode(text: plate.label)
            label.fontName = font.fontName
            label.fontSize = font.pointSize
            label.fontColor = labelColor
            label.verticalAlignmentMode = .top
            label.isHidden = !showsLabels
            label.zPosition = 10
            addChild(label)
            labels[plate.id] = label
        }
        apply(mode)
    }

    private func body(for node: SKSpriteNode) -> SKPhysicsBody {
        let radius = min(node.size.width, node.size.height) / 2
        let body = node.texture.map { SKPhysicsBody(texture: $0, alphaThreshold: 0.5, size: node.size) }
            ?? SKPhysicsBody(circleOfRadius: radius * 0.95)
        body.friction = 0.4
        body.usesPreciseCollisionDetection = true
        body.contactTestBitMask = 1
        return body
    }

    func setLabelsVisible(_ visible: Bool) {
        showsLabels = visible
        labels.values.forEach { $0.isHidden = !visible }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        apply(newMode)
    }

    private func apply(_ mode: Mode) {
        for node in plates.values {
            guard let body = node.physicsBody else { continue }
            switch mode {
            case .tumble:
                body.restitution = 0.35
                body.linearDamping = 0.3
                body.angularDamping = 0.4
            case .drift:
                body.restitution = 0.9
                body.linearDamping = 0.02
                body.angularDamping = 0.1
                body.applyImpulse(randomImpulse(strength: 18))
            }
        }
    }

    /// Throws every plate up and sideways, to land again under gravity.
    func toss() {
        for node in plates.values {
            node.physicsBody?.applyImpulse(randomImpulse(strength: 40))
            node.physicsBody?.applyAngularImpulse(CGFloat.random(in: -0.4...0.4))
        }
        Haptics.impact(.medium)
    }

    private func randomImpulse(strength: CGFloat) -> CGVector {
        let angle = CGFloat.random(in: 0.25 * .pi...0.75 * .pi)
        let mass = 1 + CGFloat.random(in: 0...0.5)
        return CGVector(dx: cos(angle) * strength * mass, dy: sin(angle) * strength * mass)
    }

    // MARK: - Simulation

    override func update(_ currentTime: TimeInterval) {
        switch mode {
        case .tumble:
            if let gravity = motion.deviceMotion?.gravity {
                physicsWorld.gravity = CGVector(dx: gravity.x * Self.earth, dy: gravity.y * Self.earth)
            } else {
                physicsWorld.gravity = CGVector(dx: 0, dy: -Self.earth)
            }
        case .drift:
            physicsWorld.gravity = .zero
        }
    }

    /// Labels follow their plate without turning with it.
    override func didSimulatePhysics() {
        for (id, node) in plates {
            labels[id]?.position = CGPoint(x: node.position.x, y: node.position.y - node.size.height / 2 - 4)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard contact.collisionImpulse > Self.bumpImpulse else { return }
        let now = CACurrentMediaTime()
        guard now - lastBump > Self.bumpInterval else { return }
        lastBump = now
        Haptics.impact(contact.collisionImpulse > Self.bumpImpulse * 4 ? .medium : .light)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        guard let node = nodes(at: point).compactMap({ $0 as? SKSpriteNode }).first(where: { $0.physicsBody != nil }) else { return }
        grab = (node, point, touch.timestamp, false)
        node.zPosition = 5
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, var held = grab else { return }
        let point = touch.location(in: self)
        if hypot(point.x - held.start.x, point.y - held.start.y) > 8 { held.moved = true }
        grab = held
        // Spring toward the finger rather than teleporting, so the plate
        // still collides on the way and keeps its speed when let go.
        held.node.physicsBody?.velocity = CGVector(
            dx: (point.x - held.node.position.x) * 18,
            dy: (point.y - held.node.position.y) * 18
        )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { grab = nil }
        guard let touch = touches.first, let held = grab else { return }
        held.node.zPosition = 0
        let quick = touch.timestamp - held.time < 0.35
        if !held.moved, quick, let name = held.node.name, let id = UUID(uuidString: name) {
            onTap?(id)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        grab?.node.zPosition = 0
        grab = nil
    }
}
