import Foundation
import Observation
import Domain
import Persistence

/// How asking the assistant for something went.
public enum AssistantOutcome<Value> {
    case success(Value)
    /// The person has not agreed that meals are sent to the assistant. The screen asks (the
    /// `assistantConsent` alert in DesignSystem), calls `allowSharing()` on yes, and asks again.
    case needsConsent
    /// The allowance is used up. `AccessModel.request` is already set, so the Plus screen or the
    /// "comes back on" alert is on its way; the screen only stops waiting.
    case refused
    /// Nothing reached an answer. Nothing was counted.
    case failed(AssistantError)
    /// This build has no assistant.
    case unavailable
}

/// What happened, for product analytics. Counts only; no meal, no recipe, nothing the person wrote.
public enum AssistantEvent: Sendable {
    case estimated(source: EstimateSource, dishes: Int, meals: Int)
    case estimateFailed(source: EstimateSource, reason: String)
    case recipeOpened(cached: Bool, steps: Int)
    case recipeFailed(reason: String)
}

/// Where an estimate was asked from.
public enum EstimateSource: String, Sendable {
    /// A plan coming in, before it is saved.
    case importReview = "import_review"
    /// The whole active plan, from Today or the Plan tab.
    case plan
    /// One meal, from its screen.
    case meal
}

/// How the estimate of the active plan is going, for every screen that shows it: one started on
/// Today is still visibly running on the Plan tab.
public enum PlanEstimateProgress: Hashable, Sendable {
    case running(dishes: Int)
    case finished(meals: Int)
    case failed(AssistantError)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// The assistant's help with single meals: what a meal holds, and how to make it.
///
/// Every request made here:
/// - runs only once the person agreed that meals are sent to the assistant (`needsConsent`);
/// - is counted against the allowance (`AccessPoint.aiNutrition`, `.aiRecipe`), and given back when
///   it fails on our side;
/// - never changes what the plan or the person wrote: estimates fill only meals with no figures of
///   their own, and are marked as estimates.
///
/// A recipe written once is kept on the phone (`RecipeCache`) and opens again without a request.
@MainActor
@Observable
public final class MealAssistantModel {
    /// The active plan's estimate, while it runs and once it has finished.
    public private(set) var planEstimate: PlanEstimateProgress?
    /// Meals whose own estimate is running.
    public private(set) var estimatingMeals: Set<UUID> = []

    @ObservationIgnored private let client: (any MealAssistant)?
    @ObservationIgnored private let store: MealPlanStore
    @ObservationIgnored private let access: AccessModel
    @ObservationIgnored private let recipes: RecipeCache
    @ObservationIgnored private let language: String
    @ObservationIgnored private let report: @MainActor (AssistantEvent) -> Void

    public init(
        client: (any MealAssistant)?,
        store: MealPlanStore,
        access: AccessModel,
        recipes: RecipeCache = RecipeCache(),
        language: String = AppLanguage.assistantLanguageName(),
        report: @escaping @MainActor (AssistantEvent) -> Void = { _ in }
    ) {
        self.client = client
        self.store = store
        self.access = access
        self.recipes = recipes
        self.language = language
        self.report = report
    }

    /// False in a build without the assistant: then nothing that leads here is shown.
    public var isAvailable: Bool { client != nil }

    /// The person has not yet agreed that what they give the assistant is sent to it.
    public var needsConsent: Bool { !store.settings.allowsAssistantSharing }

    /// The person said yes to sending meals to the assistant.
    public func allowSharing() {
        store.updateSettings { $0.allowsAssistantSharing = true }
    }

    /// Uses of `point` left this period; nil when there is no limit.
    public func remaining(_ point: AccessPoint) -> Int? {
        access.remaining(point)
    }

    /// Whether `point` would run now, without counting it or showing anything.
    public func canAsk(_ point: AccessPoint) -> Bool {
        access.decision(point).isAllowed
    }

    // MARK: - Nutrition

    /// Distinct dishes of the active plan with no nutrition of their own: what an estimate of the
    /// plan would ask about. 0 when there is nothing to fill in.
    public var dishesNeedingEstimates: Int {
        NutritionRequestPlan(meals: store.activePlan?.meals ?? []).dishCount
    }

    /// Works out the nutrition the active plan's meals are missing and fills it in, marked as
    /// estimated. One use of the allowance, however many meals. Returns how many meals were filled.
    @discardableResult
    public func estimateActivePlan() async -> AssistantOutcome<Int> {
        guard let client else { return .unavailable }
        guard !needsConsent else { return .needsConsent }
        guard planEstimate?.isRunning != true else { return .success(0) }
        let request = NutritionRequestPlan(meals: store.activePlan?.meals ?? [])
        guard !request.isEmpty else { return .success(0) }
        guard access.use(.aiNutrition) else { return .refused }
        planEstimate = .running(dishes: request.dishCount)
        do {
            let estimates = try await answers(to: request, from: client)
            let filled = try store.applyNutritionEstimates(estimates)
            planEstimate = .finished(meals: filled)
            report(.estimated(source: .plan, dishes: request.dishCount, meals: filled))
            return .success(filled)
        } catch {
            let reason = Self.assistantError(error)
            access.refund(.aiNutrition)
            planEstimate = .failed(reason)
            report(.estimateFailed(source: .plan, reason: String(describing: reason)))
            return .failed(reason)
        }
    }

    /// Clears a finished or failed plan estimate, once its result has been seen.
    public func dismissPlanEstimate() {
        if planEstimate?.isRunning == false { planEstimate = nil }
    }

    /// Works out one meal's nutrition, and gives it to every meal of the plan that is the same dish.
    /// One use of the allowance.
    @discardableResult
    public func estimate(_ meal: Meal) async -> AssistantOutcome<Int> {
        guard let client else { return .unavailable }
        guard !needsConsent else { return .needsConsent }
        guard meal.lacksNutrition, !estimatingMeals.contains(meal.id) else { return .success(0) }
        let sameDish = (store.activePlan?.meals ?? []).filter { $0.dishKey == meal.dishKey }
        let request = NutritionRequestPlan(meals: sameDish.isEmpty ? [meal] : sameDish)
        guard !request.isEmpty else { return .success(0) }
        guard access.use(.aiNutrition) else { return .refused }
        estimatingMeals.insert(meal.id)
        defer { estimatingMeals.remove(meal.id) }
        do {
            let estimates = try await answers(to: request, from: client)
            let filled = try store.applyNutritionEstimates(estimates)
            report(.estimated(source: .meal, dishes: request.dishCount, meals: filled))
            return .success(filled)
        } catch {
            let reason = Self.assistantError(error)
            access.refund(.aiNutrition)
            report(.estimateFailed(source: .meal, reason: String(describing: reason)))
            return .failed(reason)
        }
    }

    /// Estimates for meals that are not stored yet: a plan under review before it is saved. One use
    /// of the allowance. The caller fills them in (`Meal.filling`), so they are saved with the plan.
    public func estimates(for meals: [Meal]) async -> AssistantOutcome<[UUID: NutritionEstimate]> {
        guard let client else { return .unavailable }
        guard !needsConsent else { return .needsConsent }
        let request = NutritionRequestPlan(meals: meals)
        guard !request.isEmpty else { return .success([:]) }
        guard access.use(.aiNutrition) else { return .refused }
        do {
            let estimates = try await answers(to: request, from: client)
            report(.estimated(source: .importReview, dishes: request.dishCount, meals: estimates.count))
            return .success(estimates)
        } catch {
            let reason = Self.assistantError(error)
            access.refund(.aiNutrition)
            report(.estimateFailed(source: .importReview, reason: String(describing: reason)))
            return .failed(reason)
        }
    }

    /// Every batch of `request`, side by side. Batches that answer count even if another fails; when
    /// none answers, the first failure is what went wrong.
    private func answers(to request: NutritionRequestPlan, from client: any MealAssistant) async throws -> [UUID: NutritionEstimate] {
        let language = language
        let results = await withTaskGroup(of: Result<[String: NutritionEstimate], any Error>.self) { group in
            for batch in request.batches {
                group.addTask {
                    do {
                        return .success(try await client.estimateNutrition(batch, language: language))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<[String: NutritionEstimate], any Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var answers: [String: NutritionEstimate] = [:]
        var firstFailure: (any Error)?
        for result in results {
            switch result {
            case .success(let part): answers.merge(part) { first, _ in first }
            case .failure(let error): firstFailure = firstFailure ?? error
            }
        }
        if answers.isEmpty, let firstFailure { throw firstFailure }
        guard !answers.isEmpty else { throw AssistantError.unavailable }
        return request.estimates(from: answers)
    }

    // MARK: - Recipes

    /// The request a recipe for `meal` is, in the app's language.
    public func recipeRequest(for meal: Meal, servings: Int = 1) -> RecipeRequest {
        RecipeRequest(meal: meal, servings: servings, language: language)
    }

    /// A recipe already written for `meal` and `servings`, opened without asking anything.
    public func cachedRecipe(for meal: Meal, servings: Int = 1) -> Recipe? {
        recipes.recipe(for: recipeRequest(for: meal, servings: servings).cacheKey)
    }

    /// How to make `meal`: the kept recipe when there is one (free), otherwise one use of the
    /// allowance and a request.
    public func recipe(for meal: Meal, servings: Int = 1) async -> AssistantOutcome<Recipe> {
        let request = recipeRequest(for: meal, servings: servings)
        if let kept = recipes.recipe(for: request.cacheKey) {
            report(.recipeOpened(cached: true, steps: kept.steps.count))
            return .success(kept)
        }
        guard let client else { return .unavailable }
        guard !needsConsent else { return .needsConsent }
        guard access.use(.aiRecipe) else { return .refused }
        do {
            let recipe = try await client.recipe(request, avoiding: store.settings.foodsToAvoid.trimmedNonEmpty)
            recipes.save(recipe, for: request.cacheKey)
            report(.recipeOpened(cached: false, steps: recipe.steps.count))
            return .success(recipe)
        } catch {
            let reason = Self.assistantError(error)
            access.refund(.aiRecipe)
            report(.recipeFailed(reason: String(describing: reason)))
            return .failed(reason)
        }
    }

    /// Forgets every kept recipe, with the rest of the person's data.
    public func forgetRecipes() {
        recipes.removeAll()
    }

    private static func assistantError(_ error: any Error) -> AssistantError {
        if let known = error as? AssistantError { return known }
        if error is CancellationError { return .offline }
        return .unavailable
    }
}
