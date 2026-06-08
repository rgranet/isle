/*
 * Isle (built on Atoll / DynamicIsland)
 *
 * Closed-notch live activity shown while a document is printing: a printer
 * glyph on the left, the notch body in the middle, and the "1 of 1" page
 * progress on the right. Mirrors DownloadLiveActivity's geometry so it plays
 * nicely with hover/expand without breaking notch hit-testing.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

struct PrintLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var printManager = PrintJobManager.shared

    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    @State private var isExpanded: Bool = false

    private var tint: Color { .accentColor }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: printer icon capsule
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(tint.opacity(0.14))

                                Image(systemName: "printer.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(tint)
                            }
                            .frame(
                                width: vm.effectiveClosedNotchHeight - 12,
                                height: vm.effectiveClosedNotchHeight - 12
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(
                    width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0,
                    height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                )

            // Center: closed notch body (slightly wider while printing)
            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width
                        + (isHovering ? 8 : 0)
                        + (printManager.isPrinting ? 40 : 0)
                )

            // Right side: page progress ("1 of 1") or a spinner if unknown
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            if let label = printManager.pageLabel {
                                Text(label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.trailing, 8)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(tint)
                                    .padding(.trailing, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .frame(
                    width: isExpanded ? max(60, vm.effectiveClosedNotchHeight) : 0,
                    height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                )
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = true
            }
        }
        .onChange(of: printManager.isPrinting) { _, newValue in
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = newValue
            }
        }
    }
}
