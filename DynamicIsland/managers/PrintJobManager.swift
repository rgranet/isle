/*
 * Isle (built on Atoll / DynamicIsland)
 *
 * Polls the local CUPS print queue and exposes a closed-notch live-activity
 * state: whether a job is printing and its page progress ("1 of 1").
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

import Foundation
import SwiftUI
import Observation
import Combine
import Defaults

@Observable
@MainActor
final class PrintJobManager {
    static let shared = PrintJobManager()

    /// True while at least one job is pending/processing in the CUPS queue.
    private(set) var isPrinting: Bool = false
    /// Title of the job currently shown (the processing one, else the first).
    private(set) var jobTitle: String? = nil
    /// Localized "1 of 1" page label, or nil when the driver doesn't report pages.
    private(set) var pageLabel: String? = nil
    /// Number of active jobs in the queue.
    private(set) var jobCount: Int = 0

    private var timer: Timer?
    private let pollQueue = DispatchQueue(label: "com.withmii.isle.print.poll", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private let pollInterval: TimeInterval = 2.0

    private init() {
        startIfEnabled()

        Defaults.publisher(.enablePrintListener)
            .sink { [weak self] _ in
                Task { @MainActor in self?.startIfEnabled() }
            }
            .store(in: &cancellables)
    }

    private func startIfEnabled() {
        timer?.invalidate()
        timer = nil

        guard Defaults[.enablePrintListener] else {
            apply(jobs: [])
            return
        }

        poll()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        pollQueue.async {
            let jobs = IslePrintQueueReader.activeJobs()
            DispatchQueue.main.async { [weak self] in
                self?.apply(jobs: jobs)
            }
        }
    }

    private func apply(jobs: [IslePrintJobInfo]) {
        let active = jobs.first(where: { $0.processing }) ?? jobs.first
        let printing = active != nil

        var label: String? = nil
        if let job = active, job.totalSheets > 0 {
            // Show the sheet currently being printed (1-based), clamped to the total.
            let current = min(job.totalSheets, max(1, job.completedSheets + (job.processing ? 1 : 0)))
            label = String(format: NSLocalizedString("%lld of %lld", comment: "Print progress: current page of total"),
                           current, job.totalSheets)
        }

        // Only publish when something actually changed to avoid needless redraws.
        if printing != isPrinting { isPrinting = printing }
        if jobs.count != jobCount { jobCount = jobs.count }
        if active?.title != jobTitle { jobTitle = active?.title }
        if label != pageLabel { pageLabel = label }
    }
}
