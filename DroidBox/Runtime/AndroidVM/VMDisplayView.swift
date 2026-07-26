import SwiftUI

/// Draws the guest framebuffer and forwards touches as VNC pointer events.
struct VMDisplayView: View {
    let controller: VMDisplayController

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.black
                if let frame = controller.frame {
                    Image(decorative: frame.image, scale: 1, orientation: .up)
                        .interpolation(.low)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Android 画面")
                } else {
                    ProgressView().tint(.white)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { controller.dragChanged(to: $0.location, in: size) }
                    .onEnded { controller.dragEnded(at: $0.location, in: size) }
            )
        }
        .ignoresSafeArea()
    }
}

/// Back and Home, the two guest keys a game player actually needs. They map to X11
/// keysyms that QEMU turns into Linux key codes the Android input stack recognizes.
struct VMSystemKeysView: View {
    let controller: VMDisplayController

    var body: some View {
        HStack(spacing: 24) {
            Button { controller.sendKey(RFBKeysym.escape) } label: {
                Label("返回", systemImage: "chevron.backward.circle")
            }
            Button { controller.sendKey(RFBKeysym.home) } label: {
                Label("主屏幕", systemImage: "house.circle")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55), in: .capsule)
    }
}
