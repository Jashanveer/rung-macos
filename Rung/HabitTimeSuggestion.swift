import Foundation

/// Picks a "best time today" slot for a new habit by combining the
/// user's actual calendar with their energy curve. The output is a
/// concrete clock-time hint — "Try 10:30 AM" — that the AddHabitBar
/// surfaces below the title field. Cheap to compute (no HK fetch),
/// safe to call on the main actor.
///
/// The algorithm in plain English:
/// 1. Classify the habit by canonical key / keyword into a `TaskShape`
///    (peak / dip / wind-down / flexible). Hard cognitive work and
///    HIIT belong in peaks; laundry and chores belong in dips.
/// 2. Build a list of free 30-minute slots between now and 10 PM,
///    skipping anything covered by a calendar event.
/// 3. Score each slot against the *target band* for the task shape —
///    peak tasks reward proximity to either alertness peak (morning
///    or afternoon), dip tasks reward proximity to the post-lunch dip,
///    and flexible tasks fall back to the older "near acrophase"
///    heuristic.
/// 4. Return the highest-scoring slot, or nil if today is too packed
///    or it's already past evening.
///
/// This is intentionally NOT a full scheduler — we don't reserve
/// the slot, don't notify, and don't persist. It's a one-line UI
/// hint that the planner consumes for parallel-task suggestions
/// ("laundry now while you cook 5-6pm"). Reminders + scheduling
/// live in `HabitReminder`.
enum HabitTimeSuggestion {

    /// Public entry point. Pass in today's calendar events (already
    /// filtered to today) and an `EnergyForecast` snapshot. Either
    /// can be empty / nil — the function degrades gracefully.
    /// Returns a suggestion. When today's window has elapsed, falls
    /// back to tomorrow morning so the user always sees the chip on
    /// a habit they haven't done yet (instead of the chip vanishing
    /// every night around 9 pm and reappearing at 7 am).
    static func suggest(
        events: [CalendarEvent],
        forecast: EnergyForecast?,
        now: Date = Date(),
        latestHourOfDay: Int = 23,
        slotDurationMinutes: Int = 30,
        shape: TaskShape = .flexible
    ) -> Suggestion? {
        let cal = Calendar.current
        let endOfWindow = cal.date(bySettingHour: latestHourOfDay, minute: 0, second: 0, of: now) ?? now
        let slotStart = nextSlot(after: now, slotMinutes: slotDurationMinutes)
        let slotInterval = TimeInterval(slotDurationMinutes * 60)

        // Today's window — if there's still slack between the next slot
        // and the late-evening cutoff, score those slots first.
        var slots: [Date] = []
        if endOfWindow > now, slotStart < endOfWindow {
            var t = slotStart
            while t.addingTimeInterval(slotInterval) <= endOfWindow {
                if !overlaps(slot: t, duration: slotInterval, with: events) {
                    slots.append(t)
                }
                t = t.addingTimeInterval(slotInterval)
            }
        }

        // Tomorrow's window — used either when today is exhausted (it's
        // already past the cutoff) or when no events-free slot survived.
        // Without this fallback the per-habit chip silently disappears
        // every night, even though the user still has a pending habit
        // they could rehearse in the morning.
        if slots.isEmpty,
           let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
           let tomorrowMorning = cal.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrowStart) {
            let tomorrowEnd = cal.date(bySettingHour: latestHourOfDay, minute: 0, second: 0, of: tomorrowStart) ?? tomorrowMorning
            var t = tomorrowMorning
            while t.addingTimeInterval(slotInterval) <= tomorrowEnd {
                slots.append(t)   // events list only covers today; tomorrow gets a clean slate.
                t = t.addingTimeInterval(slotInterval)
            }
        }
        guard !slots.isEmpty else { return nil }

        // Score each free slot. Higher score = better.
        // - Band score: how well the slot matches the task's target band
        //   (peak / dip / wind-down). A workout in a peak slot scores 1.0;
        //   the same workout in a dip slot scores 0.0.
        // - Earliness preference: tiny tiebreaker only — too much weight
        //   here was causing every shape to collapse onto the earliest
        //   free slot (typically a midday lunch break) regardless of the
        //   shape's preferred energy band.
        let scored = slots.map { slot -> (Date, Double, Double) in
            let band = bandScore(for: slot, forecast: forecast, shape: shape)
            let hour = Double(cal.component(.hour, from: slot))
            // 0..1 with 9am=1.0, 10pm=0.5 — gentle linear decay.
            let earlinessScore = max(0, 1.0 - (hour - 9.0) / 26.0)
            return (slot, band, earlinessScore)
        }

        // Combine: 95% band fit, 5% earliness. Band fit must dominate so
        // a true dip-window slot at 1pm decisively beats a midday-lunch
        // slot, even when the lunch slot is earlier. Without this the
        // earliness bonus was pushing peak/dip/flexible shapes onto the
        // same first-free-after-9am slot — exactly the "all 12:00" bug.
        let best = scored.max(by: { lhs, rhs in
            let lhsScore = 0.95 * lhs.1 + 0.05 * lhs.2
            let rhsScore = 0.95 * rhs.1 + 0.05 * rhs.2
            return lhsScore < rhsScore
        })
        guard let pick = best else { return nil }

        return Suggestion(
            time: pick.0,
            isEnergyPeak: shape.isPeak && pick.1 >= 0.75,
            forecast: forecast,
            scoreBreakdown: ScoreBreakdown(energy: pick.1, earliness: pick.2),
            shape: shape
        )
    }

    /// Score a candidate slot against the target band for `shape`.
    /// Returns 0…1 — 1 = perfect fit, 0 = adversarial fit.
    ///
    /// Note: every shape multiplies its raw band score by a clock-window
    /// factor so the algorithm doesn't pick adversarial times even when
    /// the energy curve technically agrees. The post-lunch dip is the
    /// classic offender: a "dip = low energy" rule will happily pick
    /// 7 AM (sleep-inertia low) over 1 PM (the actual lunch dip), so we
    /// lock dip suggestions to the 12–16 window.
    private static func bandScore(
        for slot: Date,
        forecast: EnergyForecast?,
        shape: TaskShape
    ) -> Double {
        let hour = Double(Calendar.current.component(.hour, from: slot))
        // Forecast-derived energy when available, clock-heuristic
        // otherwise. We still apply the clock-window guard either way so
        // the LATEST AVAILABLE forecast can't pick adversarial slots.
        let energyValue: Double = {
            if let forecast { return forecast.energy(at: slot) / 100 }
            return shape.clockHeuristic(for: slot)
        }()

        switch shape {
        case .mentalPeak:
            // Cognitive tasks (deep work, learning, writing, code) land
            // in the morning cortisol-driven alertness peak. Body-temp
            // is climbing, but prefrontal-cortex performance peaks first.
            // 8–12 with a slight 9–11 sweet-spot bonus.
            let inWindow = (8...12).contains(Int(hour))
            let windowFactor: Double = inWindow ? 1.0 : 0.35
            let sweetSpot: Double = (9...11).contains(Int(hour)) ? 1.05 : 1.0
            return energyValue * windowFactor * sweetSpot
        case .physicalPeak:
            // Exercise / sport / running / lifting belong in the late-
            // afternoon body-temperature acrophase. Lung function, joint
            // flexibility, reaction time, and grip strength all peak
            // 15–18. Outside that window the score collapses so a
            // forecast-driven match doesn't push a 7 AM slot for "run".
            let inWindow = (15...18).contains(Int(hour))
            let windowFactor: Double = inWindow ? 1.0 : 0.35
            // Earlier morning (6–8) is a viable second-best for users
            // whose afternoons are blocked — score it modestly so the
            // calendar-gap solver can still surface it as a fallback.
            let earlyMorning: Double = (6...8).contains(Int(hour)) ? 0.6 : 0
            return max(energyValue * windowFactor, earlyMorning)
        case .dip:
            // Dip tasks (chores, admin) belong in the post-lunch dip —
            // 12–16 is the canonical window. Outside that range, score
            // collapses so the algorithm doesn't pick 7 AM (sleep
            // inertia is also "low energy" but the user isn't ready
            // for laundry yet).
            let inDipWindow = (12...16).contains(Int(hour))
            guard inDipWindow else { return 0.05 }
            // Within the dip window, prefer slots closest to wake+7h
            // (the modeled centre of the post-lunch dip). Falls back
            // to "1:30 PM is canonical" when no forecast is loaded.
            let dipCentreHour: Double = {
                if let forecast {
                    return forecast.wakeTime.timeIntervalSince(
                        Calendar.current.startOfDay(for: forecast.wakeTime)
                    ) / 3600 + 7
                }
                return 13.5
            }()
            let distance = abs(hour - dipCentreHour)
            return max(0, 1 - distance / 4)
        case .windDown:
            // Wind-down tasks are late-evening, low-to-moderate energy.
            let lateness = max(0, min(1, (hour - 18) / 4))   // 18:00=0 → 22:00=1
            return 0.5 * (1 - energyValue) + 0.5 * lateness
        case .flexible:
            // Symmetrical — peak is fine, dip is fine. Avoid the very-
            // low / very-high extremes by rewarding mid-energy slots.
            return 1 - 2 * abs(0.5 - energyValue)
        }
    }

    private static func nextSlot(after now: Date, slotMinutes: Int) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        guard let hour = comps.hour, let minute = comps.minute else { return now }
        let bucketed = (minute / slotMinutes + 1) * slotMinutes
        var newComps = comps
        if bucketed >= 60 {
            newComps.hour = hour + 1
            newComps.minute = bucketed - 60
        } else {
            newComps.minute = bucketed
        }
        return cal.date(from: newComps) ?? now
    }

    private static func overlaps(slot: Date, duration: TimeInterval, with events: [CalendarEvent]) -> Bool {
        let slotEnd = slot.addingTimeInterval(duration)
        return events.contains { event in
            !event.isAllDay && event.startDate < slotEnd && event.endDate > slot
        }
    }

    struct Suggestion {
        let time: Date
        /// True when this slot is within ~30 minutes of the user's
        /// circadian peak. Drives a different UI label so the user
        /// sees *why* this time was picked.
        let isEnergyPeak: Bool
        let forecast: EnergyForecast?
        let scoreBreakdown: ScoreBreakdown
        /// What kind of task this suggestion was tuned for. The chip
        /// label changes per shape so users see *why* a chore got a
        /// 2 PM slot instead of the morning peak.
        let shape: TaskShape
        /// On macOS 26+ / iOS 26+ the on-device LLM returns a richer
        /// reason ("peak after meetings clear, sharpest window"). When
        /// present, the chip renders this verbatim instead of the
        /// generic shape-based suffix.
        var aiReason: String? = nil

        /// User-facing label for the suggestion chip.
        /// Examples:
        ///   "Try 10:30 AM — your energy peaks then"
        ///   "Try 2:30 PM — afternoon dip is fine for chores"
        ///   "Try 9:30 PM — wind-down window"
        ///   "Try tomorrow 7 AM — peak focus window"
        var label: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let timeStr = formatter.string(from: time)
            // Prefix "tomorrow" when the suggestion has rolled past today's
            // cutoff — keeps the chip visible at night without misleading
            // the user into thinking they've still got time today.
            let isTomorrow = !Calendar.current.isDateInToday(time)
            let prefix = isTomorrow ? "Try tomorrow \(timeStr)" : "Try \(timeStr)"
            // AI-generated reason wins when present — the on-device LLM
            // produced a context-aware explanation and we want to honour
            // it instead of overriding with a generic shape suffix.
            if let aiReason, !aiReason.isEmpty {
                return "\(prefix) — \(aiReason)"
            }
            switch shape {
            case .mentalPeak:
                if isEnergyPeak, forecast?.chronotypeStable == true {
                    return "\(prefix) — your morning peak"
                }
                if isEnergyPeak {
                    return "\(prefix) — peak focus window"
                }
                return "\(prefix) — best free morning slot"
            case .physicalPeak:
                if isEnergyPeak, forecast?.chronotypeStable == true {
                    return "\(prefix) — afternoon body-temp peak"
                }
                if isEnergyPeak {
                    return "\(prefix) — peak performance window"
                }
                return "\(prefix) — best free afternoon slot"
            case .dip:
                return "\(prefix) — afternoon dip, fine for chores"
            case .windDown:
                return "\(prefix) — wind-down window"
            case .flexible:
                return "\(prefix) — first free slot"
            }
        }
    }

    struct ScoreBreakdown: Equatable {
        let energy: Double
        let earliness: Double
    }

    /// What kind of energy band a habit wants. Picked by
    /// `TaskShape.classify(_:)` from canonical key + title keywords,
    /// optionally upgraded by `HabitAITimeAdvisor` for ambiguous titles.
    ///
    /// The split between `.mentalPeak` and `.physicalPeak` mirrors real
    /// chronobiology: cortisol-driven cognitive alertness peaks in the
    /// morning, while body-temperature-driven physical performance peaks
    /// in the late afternoon. Lumping them into a single `.peak` was
    /// recommending 10 AM for "run" — fine cognitively, but worse than
    /// 5 PM for actual running performance.
    enum TaskShape: Equatable {
        /// Cognitive deep work — coding, writing, learning, study. Rewards
        /// the morning cortisol-driven alertness peak (~8–12).
        case mentalPeak
        /// Physical exertion — running, gym, HIIT, sport. Rewards the
        /// afternoon body-temperature acrophase (~15–18) where lung
        /// function, joint flexibility, and reaction time peak.
        case physicalPeak
        /// Low-cognitive chores or recovery: laundry, dishes, easy walks,
        /// admin email, mindless errands. Rewards the post-lunch dip so
        /// the user doesn't burn a peak on something they could do tired.
        case dip
        /// Calming, contemplative: read, journal, gratitude, prayer,
        /// stretching, family chat. Rewards late-evening / pre-bed.
        case windDown
        /// No strong preference — schedule the first free slot near the
        /// midpoint of the curve.
        case flexible

        /// True for either peak. Drives the chip's "your energy peaks
        /// then" copy when the suggestion lands at the right window.
        var isPeak: Bool { self == .mentalPeak || self == .physicalPeak }

        /// Fallback heuristic when we have no forecast yet — uses raw
        /// clock time bands so brand-new users still see sensible chips
        /// before HK has built the curve.
        func clockHeuristic(for slot: Date) -> Double {
            let hour = Double(Calendar.current.component(.hour, from: slot))
            switch self {
            case .mentalPeak:
                // Cognitive peak: 9–12 best; 8–13 acceptable.
                if (9...11).contains(hour) { return 1 }
                if (8...12).contains(hour) { return 0.85 }
                if (13...18).contains(hour) { return 0.45 }
                return 0.2
            case .physicalPeak:
                // Body-temp peak: 15–18 best; 6–8 morning is a viable
                // second-best; everything else degrades fast.
                if (16...17).contains(hour) { return 1 }
                if (15...18).contains(hour) { return 0.9 }
                if (6...8).contains(hour) { return 0.6 }
                if (9...14).contains(hour) { return 0.4 }
                return 0.2
            case .dip:
                // Dip-friendly: 13–15.
                if (13...15).contains(hour) { return 1 }
                if (12...16).contains(hour) { return 0.7 }
                return 0.3
            case .windDown:
                // Late evening only.
                if (19...22).contains(hour) { return 1 }
                if (17...22).contains(hour) { return 0.6 }
                return 0.2
            case .flexible:
                // Anything 8…21 is fine.
                if (8...21).contains(hour) { return 0.7 }
                return 0.3
            }
        }

        /// Classify a habit by canonical key first, then by free-text
        /// keyword search if no canonical match. Defaults to `.flexible`.
        ///
        /// Keyword matches use longest-match-wins so a title like
        /// "Run laundry" classifies as `.dip` (matched "laundry", 7
        /// chars) instead of `.physicalPeak` ("run", 3 chars). Without
        /// this fix the order of declaration in `keywordShape` silently
        /// determined the result.
        static func classify(canonicalKey: String?, title: String) -> TaskShape {
            if let canonicalKey, let shape = canonicalShape[canonicalKey] {
                return shape
            }
            let lowered = title.lowercased()
            var bestMatch: (length: Int, shape: TaskShape)?
            for (keyword, shape) in keywordShape {
                guard lowered.contains(keyword) else { continue }
                if bestMatch == nil || keyword.count > bestMatch!.length {
                    bestMatch = (keyword.count, shape)
                }
            }
            return bestMatch?.shape ?? .flexible
        }

        // Canonical keys map directly. Mirror with `CanonicalHabits.all`.
        private static let canonicalShape: [String: TaskShape] = [
            // Physical peak — exercise / sport
            "run":        .physicalPeak,
            "workout":    .physicalPeak,
            "cycle":      .physicalPeak,
            "swim":       .physicalPeak,
            // Mental peak — cognitive work
            "study":      .mentalPeak,
            // Flexible / movement (works in either peak)
            "walk":       .flexible,
            "yoga":       .flexible,
            // Dip / chore-y / hydration
            "water":      .flexible,
            "weighIn":    .dip,
            "eatHealthy": .flexible,
            "floss":      .windDown,
            "makeBed":    .dip,    // morning chore but in inertia → dip-y
            // Wind-down / contemplative
            "read":       .windDown,
            "meditate":   .windDown,
            "journal":    .windDown,
            "gratitude":  .windDown,
            "family":     .windDown,
            "sleep":      .windDown,
            // Avoidance habits — shape doesn't really apply, score loosely
            "noAlcohol":  .flexible,
            "screenTime": .flexible,
        ]

        // Keyword fallback for free-text titles. Longest match wins, not
        // first match — so put more specific terms anywhere.
        private static let keywordShape: [(String, TaskShape)] = [
            // Physical peak (exercise / sport)
            ("gym", .physicalPeak), ("workout", .physicalPeak),
            ("run", .physicalPeak), ("hiit", .physicalPeak),
            ("lift", .physicalPeak), ("crossfit", .physicalPeak),
            ("swim", .physicalPeak), ("cycle", .physicalPeak),
            ("bike", .physicalPeak), ("hike", .physicalPeak),
            ("sport", .physicalPeak), ("tennis", .physicalPeak),
            ("basketball", .physicalPeak), ("soccer", .physicalPeak),
            ("football", .physicalPeak), ("climbing", .physicalPeak),
            ("boxing", .physicalPeak), ("cardio", .physicalPeak),
            ("dance", .physicalPeak), ("pilates", .physicalPeak),
            ("rowing", .physicalPeak),
            // Mental peak (deep work / learning)
            ("study", .mentalPeak), ("focus", .mentalPeak),
            ("deep work", .mentalPeak), ("write", .mentalPeak),
            ("code", .mentalPeak), ("debug", .mentalPeak),
            ("review", .mentalPeak), ("interview", .mentalPeak),
            ("presentation", .mentalPeak), ("exam", .mentalPeak),
            ("test", .mentalPeak), ("research", .mentalPeak),
            ("design", .mentalPeak), ("learn", .mentalPeak),
            ("read paper", .mentalPeak),
            // Dip (chores / errands / admin)
            ("laundry", .dip), ("wash", .dip), ("dishes", .dip),
            ("clean", .dip), ("vacuum", .dip), ("sweep", .dip),
            ("groceries", .dip), ("shopping", .dip), ("errand", .dip),
            ("email", .dip), ("inbox", .dip), ("admin", .dip),
            ("paperwork", .dip), ("invoice", .dip), ("expense", .dip),
            ("filing", .dip), ("organize", .dip), ("tidy", .dip),
            ("cook", .dip), ("meal prep", .dip),
            // Wind-down (calming, evening)
            ("read", .windDown), ("journal", .windDown),
            ("meditate", .windDown), ("pray", .windDown),
            ("stretch", .windDown), ("family", .windDown),
            ("call mom", .windDown), ("call parents", .windDown),
            ("plan tomorrow", .windDown), ("gratitude", .windDown),
            // Flexible (movement, hydration, social)
            ("walk", .flexible), ("yoga", .flexible),
            ("water", .flexible), ("hydrate", .flexible),
        ]
    }
}
