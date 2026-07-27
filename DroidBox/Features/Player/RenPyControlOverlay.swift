import UIKit

@MainActor
final class RenPyControlOverlay {
    static let shared = RenPyControlOverlay()

    private var window: PassthroughOverlayWindow?
    private weak var environment: AppEnvironment?
    private var exitAction: (() -> Void)?
    private var keyButtons: [UIButton] = []

    func show(environment: AppEnvironment, exit: @escaping () -> Void) {
        self.environment = environment
        exitAction = exit
        if window == nil { makeWindow() }
        refreshVirtualKeys()
        window?.isHidden = false
    }

    func hide() {
        window?.isHidden = true
    }

    private func makeWindow() {
        let overlay: PassthroughOverlayWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            overlay = PassthroughOverlayWindow(windowScene: scene)
        } else {
            overlay = PassthroughOverlayWindow(frame: UIScreen.main.bounds)
        }
        overlay.windowLevel = .alert + 2
        overlay.backgroundColor = .clear

        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        overlay.rootViewController = controller

        let gear = UIButton(type: .system)
        gear.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        gear.tintColor = .white
        gear.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        gear.layer.cornerRadius = 22
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.addAction(UIAction { [weak self] _ in self?.presentSettings() }, for: .touchUpInside)
        controller.view.addSubview(gear)
        NSLayoutConstraint.activate([
            gear.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            gear.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            gear.widthAnchor.constraint(equalToConstant: 44),
            gear.heightAnchor.constraint(equalToConstant: 44)
        ])
        window = overlay
    }

    private func presentSettings() {
        guard let controller = window?.rootViewController, let environment else { return }
        let settings = environment.settings
        let alert = UIAlertController(
            title: "游戏设置",
            message: "分辨率：\(settings.playerResolution.title)",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "设置分辨率", style: .default) { [weak self] _ in
            self?.presentResolution()
        })
        alert.addAction(UIAlertAction(
            title: settings.virtualControlsEnabled ? "隐藏虚拟按键" : "显示虚拟按键",
            style: .default
        ) { [weak self] _ in
            guard let self, let settings = self.environment?.settings else { return }
            settings.virtualControlsEnabled.toggle()
            self.refreshVirtualKeys()
        })
        alert.addAction(UIAlertAction(title: "退出当前游戏", style: .destructive) { [weak self] _ in
            self?.exitAction?()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: 34, y: 70, width: 1, height: 1)
        }
        controller.present(alert, animated: true)
    }

    private func presentResolution() {
        guard let controller = window?.rootViewController, let settings = environment?.settings else { return }
        let alert = UIAlertController(title: "分辨率", message: nil, preferredStyle: .actionSheet)
        for resolution in PlayerResolution.allCases {
            let title = resolution == settings.playerResolution
                ? "✓ \(resolution.title)" : resolution.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let settings = self?.environment?.settings else { return }
                settings.playerResolution = resolution
                if let size = resolution.size {
                    DroidBoxApplyGameResolution(Int32(size.width), Int32(size.height))
                }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: 34, y: 70, width: 1, height: 1)
        }
        controller.present(alert, animated: true)
    }

    private func refreshVirtualKeys() {
        keyButtons.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()
        guard let root = window?.rootViewController?.view,
              let settings = environment?.settings,
              settings.virtualControlsEnabled else { return }

        // SDL key codes: arrows use SDL's scancode-keycode range; Enter is ASCII.
        let keys: [(String, Int32, CGFloat, CGFloat)] = [
            ("←", 1_073_741_904, 18, -66),
            ("→", 1_073_741_903, 126, -66),
            ("↑", 1_073_741_906, 72, -118),
            ("↓", 1_073_741_905, 72, -14),
            ("OK", 13, -78, -66)
        ]
        for (title, key, x, y) in keys {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
            button.backgroundColor = UIColor.black.withAlphaComponent(
                settings.virtualControlsOpacity * 0.72
            )
            button.layer.cornerRadius = 24
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addAction(UIAction { _ in DroidBoxSendGameKey(key, 1) }, for: .touchDown)
            button.addAction(UIAction { _ in DroidBoxSendGameKey(key, 0) }, for: [
                .touchUpInside, .touchUpOutside, .touchCancel
            ])
            root.addSubview(button)
            keyButtons.append(button)
            if x < 0 {
                button.trailingAnchor.constraint(
                    equalTo: root.safeAreaLayoutGuide.trailingAnchor,
                    constant: x
                ).isActive = true
            } else {
                button.leadingAnchor.constraint(
                    equalTo: root.safeAreaLayoutGuide.leadingAnchor,
                    constant: x
                ).isActive = true
            }
            NSLayoutConstraint.activate([
                button.bottomAnchor.constraint(
                    equalTo: root.safeAreaLayoutGuide.bottomAnchor,
                    constant: y
                ),
                button.widthAnchor.constraint(equalToConstant: 48),
                button.heightAnchor.constraint(equalToConstant: 48)
            ])
        }
    }
}

private final class PassthroughOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === rootViewController?.view ? nil : result
    }
}
