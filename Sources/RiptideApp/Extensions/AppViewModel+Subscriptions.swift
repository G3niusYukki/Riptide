import Foundation
import Riptide

// MARK: - Subscription Management

extension AppViewModel {

    /// Starts the subscription auto-update scheduler (5-minute interval).
    internal func startSubscriptionScheduler() {
        let scheduler = SubscriptionUpdateScheduler(manager: subscriptionManager, checkInterval: 300)
        Task { await scheduler.start() }
        subscriptionScheduler = scheduler
    }

    /// Stops the subscription auto-update scheduler.
    internal func stopSubscriptionScheduler() {
        guard let scheduler = subscriptionScheduler else { return }
        Task { await scheduler.stop() }
        subscriptionScheduler = nil
    }

    /// Loads subscriptions from the backend and refreshes their display profiles.
    public func loadSubscriptionsFromBackend() async {
        let subs = await subscriptionManager.allSubscriptions()
        await MainActor.run {
            subscriptions = subs.map { sub in
                // Match by subscription ID only (name may change over time)
                let profileCount = profiles.count {
                    guard case let .subscription(id, _) = $0.source else { return false }
                    return id == sub.id
                }
                return SubscriptionDisplay(
                    id: sub.id, name: sub.name, url: sub.url,
                    autoUpdate: sub.autoUpdate, lastUpdated: sub.lastUpdated,
                    lastError: sub.lastError, profileCount: profileCount,
                    userinfo: sub.userinfo
                )
            }
        }
        await notifyExpiringSubscriptions(subs)
    }

    /// Surfaces a system notification for any subscription that is within
    /// 3 days of expiry. Called whenever the subscription list is reloaded.
    private func notifyExpiringSubscriptions(_ subs: [Riptide.Subscription]) async {
        for sub in subs {
            guard let userinfo = sub.userinfo,
                  let expiry = userinfo.expireDate else { continue }
            let secondsRemaining = expiry.timeIntervalSinceNow
            guard secondsRemaining > 0, secondsRemaining <= 3 * 24 * 3600 else { continue }
            let days = max(1, Int((secondsRemaining / 86_400).rounded(.up)))
            await UserNotificationManager.shared.notifySubscriptionExpiring(
                name: sub.name, daysRemaining: days
            )
        }
    }

    /// Adds a new subscription, fetches its nodes, and creates a profile.
    public func addSubscription(url subscriptionURL: String, name: String, autoUpdate: Bool, interval: TimeInterval) async {
        let sub = await subscriptionManager.addSubscription(
            name: name, url: subscriptionURL, autoUpdate: autoUpdate, interval: interval
        )
        let result = await subscriptionManager.updateSubscription(id: sub.id)
        switch result {
        case .success(let proxies):
            let config = RiptideConfig(
                mode: .rule,
                proxies: proxies,
                rules: [],
                proxyGroups: [],
                dnsPolicy: DNSPolicy()
            )
            let profile = Profile(name: name, config: config, source: .subscription(id: sub.id, name: sub.name))
            await MainActor.run {
                lastError = nil  // Clear any previous error
                profiles.append(profile)
                if activeProfile == nil { activeProfile = profile }
                rebuildProxyGroupDisplays()
            }
        case .failure(let error):
            await MainActor.run { lastError = "订阅拉取失败: \(error)" }
        case .noChange:
            await MainActor.run { lastError = nil }  // Clear stale error
        }
        await loadSubscriptionsFromBackend()
    }

    /// Removes a subscription and its associated profile.
    public func removeSubscription(id: UUID) async {
        await subscriptionManager.removeSubscription(id: id)
        await MainActor.run {
            profiles.removeAll { profile in
                if case .subscription(let subID, _) = profile.source { return subID == id }
                return false
            }
            if let active = activeProfile,
               case .subscription(let subID, _) = active.source, subID == id {
                activeProfile = profiles.first
            }
            rebuildProxyGroupDisplays()
        }
        await loadSubscriptionsFromBackend()
    }

    /// Refresh every subscription sequentially. Used by the dashboard quick-action
    /// button. Failures are recorded on each subscription's `lastError` and don't
    /// short-circuit the rest.
    public func refreshAllSubscriptions() async {
        for sub in await subscriptionManager.allSubscriptions() {
            await updateSubscription(id: sub.id)
        }
    }

    /// Subscription-backed profiles are held in memory only (not written to
    /// ProfileStore), so after a relaunch they are gone until refreshed —
    /// previously the user had to click 更新 once per session to get a usable
    /// profile. On launch, recreate any subscription whose profile is missing by
    /// refreshing it (updateSubscription creates the profile when none exists).
    internal func ensureSubscriptionProfiles() async {
        for sub in await subscriptionManager.allSubscriptions() {
            let hasProfile = await MainActor.run {
                profiles.contains { profile in
                    if case .subscription(let sid, _) = profile.source { return sid == sub.id }
                    return false
                }
            }
            if !hasProfile {
                await updateSubscription(id: sub.id)
            }
        }
    }

    /// Updates (refreshes) a subscription by fetching fresh nodes.
    public func updateSubscription(id: UUID) async {
        let result = await subscriptionManager.updateSubscription(id: id)
        switch result {
        case .success(let proxies):
            let sub = await subscriptionManager.subscription(id: id)
            if let sub {
                let config = RiptideConfig(
                    mode: .rule,
                    proxies: proxies,
                    rules: [],
                    proxyGroups: [],
                    dnsPolicy: DNSPolicy()
                )
                await MainActor.run {
                    if let idx = profiles.firstIndex(where: { profile in
                        if case .subscription(let sid, _) = profile.source { return sid == id }
                        return false
                    }) {
                        // Preserve original profile ID so activeProfile reference stays valid
                        let existingProfile = profiles[idx]
                        let wasActiveProfile = activeProfile?.id == existingProfile.id
                        let refreshedProfile = Profile(
                            id: existingProfile.id,
                            name: sub.name, config: config,
                            source: .subscription(id: sub.id, name: sub.name)
                        )
                        profiles[idx] = refreshedProfile
                        if wasActiveProfile { activeProfile = refreshedProfile }
                        rebuildProxyGroupDisplays()
                    } else {
                        // No profile exists yet for this subscription (e.g. the
                        // initial add-time fetch failed, or profiles weren't
                        // persisted across launches). Create one now so refreshing
                        // a subscription always yields a usable, selectable profile.
                        let newProfile = Profile(
                            name: sub.name, config: config,
                            source: .subscription(id: sub.id, name: sub.name)
                        )
                        profiles.append(newProfile)
                        if activeProfile == nil { activeProfile = newProfile }
                        rebuildProxyGroupDisplays()
                    }
                }
            }
        case .failure(let error):
            await MainActor.run { lastError = "订阅更新失败: \(error)" }
        case .noChange:
            break
        }
        await loadSubscriptionsFromBackend()
    }

    /// Edits subscription properties.
    public func editSubscription(id: UUID, name: String? = nil, url: String? = nil, autoUpdate: Bool? = nil, interval: TimeInterval? = nil) async {
        await subscriptionManager.updateSubscription(
            id: id, name: name, url: url, autoUpdate: autoUpdate, interval: interval
        )
        await loadSubscriptionsFromBackend()
    }
}
