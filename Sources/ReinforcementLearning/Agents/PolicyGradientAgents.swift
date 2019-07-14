// Copyright 2019, Emmanouil Antonios Platanios. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.

import TensorFlow

// TODO: Add support for reward normalization.
// TODO: Add support for gradient clipping.
// TODO: L2 regularization support for networks.
// TODO: Reward normalizer.
// TODO: Observation normalizer.
// TODO: Reward norm clipping.

public protocol PolicyGradientAgent: ProbabilisticAgent {
  @discardableResult
  mutating func update(
    using environment: inout Environment,
    maxSteps: Int,
    maxEpisodes: Int,
    stepCallbacks: [(Trajectory<Observation, Action, Reward, State>) -> Void]
  ) -> Float
}

extension PolicyGradientAgent {
  @discardableResult
  public mutating func update(
    using environment: inout Environment,
    maxSteps: Int = Int.max,
    maxEpisodes: Int = Int.max,
    stepCallbacks: [(Trajectory<Observation, Action, Reward, State>) -> Void] = []
  ) -> Float {
    var trajectories = [Trajectory<Observation, Action, Reward, State>]()
    var currentStep = environment.currentStep()
    var numSteps = 0
    var numEpisodes = 0
    while numSteps < maxSteps && numEpisodes < maxEpisodes {
      let action = self.action(for: currentStep, mode: .probabilistic)
      let nextStep = environment.step(taking: action)
      let trajectory = Trajectory(
        stepKind: nextStep.kind,
        observation: currentStep.observation,
        action: action,
        reward: nextStep.reward,
        state: state)
      trajectories.append(trajectory)
      stepCallbacks.forEach { $0(trajectory) }
      numSteps += Int((1 - Tensor<Int32>(nextStep.kind.isLast())).sum().scalarized())
      numEpisodes += Int(Tensor<Int32>(nextStep.kind.isLast()).sum().scalarized())
      currentStep = nextStep
    }
    return update(using: Trajectory<Observation, Action, Reward, State>.stack(trajectories))
  }
}

public struct ReinforceAgent<
  Environment: ReinforcementLearning.Environment,
  Network: ReinforcementLearning.Network,
  Optimizer: TensorFlow.Optimizer
>: PolicyGradientAgent
where
  Environment.Observation == Network.Input,
  Environment.ActionSpace.ValueDistribution: DifferentiableDistribution,
  Environment.Reward == Tensor<Float>,
  Network.Output == Environment.ActionSpace.ValueDistribution,
  Optimizer.Model == Network
{
  public typealias Observation = Network.Input
  public typealias Action = ActionDistribution.Value
  public typealias ActionDistribution = Environment.ActionSpace.ValueDistribution
  public typealias Reward = Tensor<Float>
  public typealias State = Network.State

  public let actionSpace: Environment.ActionSpace
  public var network: Network
  public var optimizer: Optimizer

  public var state: State {
    get { network.state }
    set { network.state = newValue }
  }

  public let discountFactor: Float
  public let entropyRegularizationWeight: Float

  public private(set) var returnsNormalizer: StreamingTensorNormalizer<Float>?

  public init(
    for environment: Environment,
    network: Network,
    optimizer: Optimizer,
    discountFactor: Float,
    normalizeReturns: Bool = true,
    entropyRegularizationWeight: Float = 0.0
  ) {
    self.actionSpace = environment.actionSpace
    self.network = network
    self.optimizer = optimizer
    self.discountFactor = discountFactor
    self.returnsNormalizer = normalizeReturns ? StreamingTensorNormalizer(alongAxes: 0, 1) : nil
    self.entropyRegularizationWeight = entropyRegularizationWeight
  }

  public func actionDistribution(for step: Step<Observation, Reward>) -> ActionDistribution {
    network(step.observation)
  }

  @discardableResult
  public mutating func update(
    using trajectory: Trajectory<Observation, Action, Reward, State>
  ) -> Float {
    var returns = discountedReturns(
      discountFactor: discountFactor,
      stepKinds: trajectory.stepKind,
      rewards: trajectory.reward)
    network.state = trajectory.state
    let (loss, gradient) = network.valueWithGradient { network -> Tensor<Float> in
      let actionDistribution = network(trajectory.observation)
      returnsNormalizer?.update(using: returns)
      if let normalizer = returnsNormalizer {
        returns = normalizer.normalize(returns)
      }
      let actionLogProbs = actionDistribution.logProbability(of: trajectory.action)

      // The policy gradient loss is defined as the sum, over time steps, of action
      // log-probabilities multiplied with the cumulative return from that time step onward.
      let actionLogProbWeightedReturns = actionLogProbs * returns

      // REINFORCE requires completed episodes and thus we mask out incomplete ones.
      let mask = Tensor<Float>(trajectory.stepKind.completeEpisodeMask())
      let episodeCount = trajectory.stepKind.episodeCount()

      precondition(
        episodeCount.scalarized() > 0,
        "REINFORCE requires at least one completed episode.")
      
      // TODO: Mask out `isLast` steps?

      // We compute the mean of the policy gradient loss over the number of episodes.
      let policyGradientLoss = -(actionLogProbWeightedReturns * mask).sum() / episodeCount

      // If entropy regularization is being used for the action distribution, then we also
      // compute the entropy loss term.
      var entropyLoss = Tensor<Float>(0.0)
      if entropyRegularizationWeight > 0.0 {
        let entropy = actionDistribution.entropy()
        entropyLoss = entropyLoss - entropyRegularizationWeight * entropy.mean()
      }
      return policyGradientLoss + entropyLoss
    }
    optimizer.update(&network, along: gradient)
    return loss.scalarized()
  }
}

public struct ActorCriticOutput<ActionDistribution: DifferentiableDistribution>: Differentiable {
  public var actionDistribution: ActionDistribution
  public var value: Tensor<Float>

  @differentiable
  public init(actionDistribution: ActionDistribution, value: Tensor<Float>) {
    self.actionDistribution = actionDistribution
    self.value = value
  }
}

public struct A2CAgent<
  Environment: ReinforcementLearning.Environment,
  Network: ReinforcementLearning.Network,
  Optimizer: TensorFlow.Optimizer
>: PolicyGradientAgent
where
  Environment.Observation == Network.Input,
  Environment.Reward == Tensor<Float>,
  Network.Output == ActorCriticOutput<Environment.ActionSpace.ValueDistribution>,
  Optimizer.Model == Network
{
  public typealias Observation = Network.Input
  public typealias Action = ActionDistribution.Value
  public typealias ActionDistribution = Environment.ActionSpace.ValueDistribution
  public typealias Reward = Tensor<Float>
  public typealias State = Network.State

  public let actionSpace: Environment.ActionSpace
  public var network: Network
  public var optimizer: Optimizer

  public var state: State {
    get { network.state }
    set { network.state = newValue }
  }

  public let advantageFunction: AdvantageFunction
  public let valueEstimationLossWeight: Float
  public let entropyRegularizationWeight: Float

  public private(set) var advantagesNormalizer: StreamingTensorNormalizer<Float>?

  public init(
    for environment: Environment,
    network: Network,
    optimizer: Optimizer,
    advantageFunction: AdvantageFunction = GeneralizedAdvantageEstimation(discountFactor: 0.9),
    normalizeAdvantages: Bool = true,
    valueEstimationLossWeight: Float = 0.2,
    entropyRegularizationWeight: Float = 0.0
  ) {
    self.actionSpace = environment.actionSpace
    self.network = network
    self.optimizer = optimizer
    self.advantageFunction = advantageFunction
    self.advantagesNormalizer = normalizeAdvantages ? StreamingTensorNormalizer(alongAxes: 0, 1) : nil
    self.valueEstimationLossWeight = valueEstimationLossWeight
    self.entropyRegularizationWeight = entropyRegularizationWeight
  }

  public func actionDistribution(for step: Step<Observation, Reward>) -> ActionDistribution {
    network(step.observation).actionDistribution
  }

  @discardableResult
  public mutating func update(
    using trajectory: Trajectory<Observation, Action, Reward, State>
  ) -> Float {
    network.state = trajectory.state
    let (loss, gradient) = network.valueWithGradient { network -> Tensor<Float> in
      let networkOutput = network(trajectory.observation)

      // Split the trajectory such that the last step is only used to provide the final value
      // estimate used for advantage estimation.
      let sequenceLength = networkOutput.value.shape[0] - 1
      let stepKinds = StepKind(trajectory.stepKind.rawValue[0..<sequenceLength])
      let values = networkOutput.value[0..<sequenceLength]
      let finalValue = networkOutput.value[sequenceLength]

      // Estimate the advantages for the provided trajectory.
      let advantageEstimate = advantageFunction(
        stepKinds: stepKinds,
        rewards: trajectory.reward[0..<sequenceLength],
        values: withoutDerivative(at: values),
        finalValue: withoutDerivative(at: finalValue))
      var advantages = advantageEstimate.advantages
      advantagesNormalizer?.update(using: advantages)
      if let normalizer = advantagesNormalizer {
        advantages = normalizer.normalize(advantages)
      }
      let returns = advantageEstimate.discountedReturns

      // Compute the action log probabilities.
      let actionDistribution = networkOutput.actionDistribution
      let actionLogProbs = actionDistribution.logProbability(
        of: trajectory.action
      )[0..<sequenceLength]

      // TODO: Mask out `isLast` steps?

      // The policy gradient loss is defined as the sum, over time steps, of action
      // log-probabilities multiplied with the normalized advantages.
      let actionLogProbWeightedReturns = actionLogProbs * advantages
      let policyGradientLoss = -actionLogProbWeightedReturns.mean()

      // The value estimation loss is defined as the mean squared error between the value
      // estimates and the discounted returns.
      let valueMSE = (values - returns).squared().mean()
      let valueEstimationLoss = valueEstimationLossWeight * valueMSE

      // If entropy regularization is being used for the action distribution, then we also
      // compute the entropy loss term.
      var entropyLoss = Tensor<Float>(0.0)
      if entropyRegularizationWeight > 0.0 {
        let entropy = actionDistribution.entropy()[0..<sequenceLength]
        entropyLoss = entropyLoss - entropyRegularizationWeight * entropy.mean()
      }
      return policyGradientLoss + valueEstimationLoss + entropyLoss
    }
    optimizer.update(&network, along: gradient)
    return loss.scalarized()
  }
}

public struct PPOClip {
  public let epsilon: Float

  public init(epsilon: Float = 0.2) {
    self.epsilon = epsilon
  }
}

public struct PPOPenalty {
  public let klCutoffFactor: Float
  public let klCutoffCoefficient: Float
  public let adaptiveKLTarget: Float
  public let adaptiveKLToleranceFactor: Float
  public let adaptiveKLBetaScalingFactor: Float

  public fileprivate(set) var adaptiveKLBeta: Float?

  public init(
    klCutoffFactor: Float = 0.2,
    klCutoffCoefficient: Float = 1000.0,
    adaptiveKLTarget: Float = 0.01,
    adaptiveKLToleranceFactor: Float = 1.5,
    adaptiveKLBetaScalingFactor: Float = 2.0,
    adaptiveKLBeta: Float? = 1.0
  ) {
    precondition(adaptiveKLBetaScalingFactor > 0, "The beta scaling factor must be positive.")
    self.klCutoffFactor = klCutoffFactor
    self.klCutoffCoefficient = klCutoffCoefficient
    self.adaptiveKLTarget = adaptiveKLTarget
    self.adaptiveKLToleranceFactor = adaptiveKLToleranceFactor
    self.adaptiveKLBetaScalingFactor = adaptiveKLBetaScalingFactor
    self.adaptiveKLBeta = adaptiveKLBeta
  }
}

public struct PPOEntropyRegularization {
  public let weight: Float

  public init(weight: Float) {
    self.weight = weight
  }
}

public struct PPOAgent<
  Environment: ReinforcementLearning.Environment,
  Network: ReinforcementLearning.Network,
  Optimizer: TensorFlow.Optimizer
>: PolicyGradientAgent
where
  Environment.Observation == Network.Input,
  Environment.ActionSpace.ValueDistribution: DifferentiableKLDivergence,
  Environment.Reward == Tensor<Float>,
  Network.Output == ActorCriticOutput<Environment.ActionSpace.ValueDistribution>,
  Optimizer.Model == Network
{
  public typealias Observation = Network.Input
  public typealias Action = ActionDistribution.Value
  public typealias ActionDistribution = Environment.ActionSpace.ValueDistribution
  public typealias Reward = Tensor<Float>
  public typealias State = Network.State

  public let actionSpace: Environment.ActionSpace
  public var network: Network
  public var optimizer: Optimizer

  public var state: State {
    get { network.state }
    set { network.state = newValue }
  }

  public let clip: PPOClip?
  public let penalty: PPOPenalty?
  public let entropyRegularization: PPOEntropyRegularization?
  public let advantageFunction: AdvantageFunction
  public let useTDLambdaReturn: Bool
  public let valueEstimationLossWeight: Float
  public let epochCount: Int

  public private(set) var advantagesNormalizer: StreamingTensorNormalizer<Float>?

  public init(
    for environment: Environment,
    network: Network,
    optimizer: Optimizer,
    clip: PPOClip? = PPOClip(),
    penalty: PPOPenalty? = nil,
    entropyRegularization: PPOEntropyRegularization? = nil,
    advantageFunction: AdvantageFunction = GeneralizedAdvantageEstimation(
      discountFactor: 0.99,
      discountWeight: 0.95),
    normalizeAdvantages: Bool = true,
    useTDLambdaReturn: Bool = false,
    valueEstimationLossWeight: Float = 0.2,
    epochCount: Int = 4
  ) {
    self.actionSpace = environment.actionSpace
    self.network = network
    self.optimizer = optimizer
    self.clip = clip
    self.penalty = penalty
    self.entropyRegularization = entropyRegularization
    self.advantageFunction = advantageFunction
    self.advantagesNormalizer = normalizeAdvantages ? StreamingTensorNormalizer(alongAxes: 0, 1) : nil
    self.useTDLambdaReturn = useTDLambdaReturn
    self.valueEstimationLossWeight = valueEstimationLossWeight
    self.epochCount = epochCount
  }

  public func actionDistribution(for step: Step<Observation, Reward>) -> ActionDistribution {
    network(step.observation).actionDistribution
  }

  @discardableResult
  public mutating func update(
    using trajectory: Trajectory<Observation, Action, Reward, State>
  ) -> Float {
    network.state = trajectory.state
    let networkOutput = network(trajectory.observation)

    // Split the trajectory such that the last step is only used to provide the final value
    // estimate used for advantage estimation.
    let sequenceLength = networkOutput.value.shape[0] - 1
    let stepKinds = StepKind(trajectory.stepKind.rawValue[0..<sequenceLength])
    let values = networkOutput.value[0..<sequenceLength]
    let finalValue = networkOutput.value[sequenceLength]

    // Estimate the advantages for the provided trajectory.
    let advantageEstimate = advantageFunction(
      stepKinds: stepKinds,
      rewards: trajectory.reward[0..<sequenceLength],
      values: values,
      finalValue: finalValue)
    var advantages = advantageEstimate.advantages
    advantagesNormalizer?.update(using: advantages)
    if let normalizer = advantagesNormalizer {
      advantages = normalizer.normalize(advantages)
    }
    let usingGAE = advantageFunction is GeneralizedAdvantageEstimation
    let returns = useTDLambdaReturn && usingGAE ?
      advantages + withoutDerivative(at: values) :
      advantageEstimate.discountedReturns

    // Compute the action log probabilities.
    let actionDistribution = networkOutput.actionDistribution
    let actionLogProbs = actionDistribution.logProbability(
      of: trajectory.action
    )[0..<sequenceLength]
    
    var lastEpochLoss: Float = 0.0
    for _ in 0..<epochCount {
      // Restore the network state before computing the loss function.
      network.state = trajectory.state
      let (loss, gradient) = network.valueWithGradient { network -> Tensor<Float> in
        let newNetworkOutput = network(trajectory.observation)

        // Compute the new action log probabilities.
        let newActionDistribution = newNetworkOutput.actionDistribution
        let newActionLogProbs = newActionDistribution.logProbability(
          of: trajectory.action
        )[0..<sequenceLength]

        // TODO: Mask out `isLast` steps?

        let importanceRatio = exp(newActionLogProbs - actionLogProbs)
        var loss = importanceRatio * advantages
        
        // Importance ratio clipping loss term.
        if let c = clip {
          let ε = Tensor<Float>(c.epsilon)
          let importanceRatioClipped = importanceRatio.clipped(min: 1 - ε, max: 1 + ε)
          loss = -min(loss, importanceRatioClipped * advantages).mean()
        } else {
          loss = -loss.mean()
        }

        // KL penalty loss term.
        if let p = penalty {
          let klDivergence = actionDistribution.klDivergence(to: newActionDistribution)
          let klMean = klDivergence.mean()
          let klCutoffLoss = max(klMean - p.klCutoffFactor * p.adaptiveKLTarget, 0).squared()
          loss = loss + p.klCutoffCoefficient * klCutoffLoss
          if let beta = p.adaptiveKLBeta {
            loss = loss + beta * klMean
          }
        }

        // Entropy regularization loss term.
        if let e = entropyRegularization {
          let entropy = actionDistribution.entropy()[0..<sequenceLength]
          loss = loss - e.weight * entropy.mean()
        }

        // Value estimation loss term.
        let values = newNetworkOutput.value[0..<sequenceLength]
        let valueMSE = (values - returns).squared().mean()
        return loss + valueEstimationLossWeight * valueMSE
      }
      optimizer.update(&network, along: gradient)
      lastEpochLoss = loss.scalarized()
    }

    // After the network is updated, we may need to update the adaptive KL beta.
    if var p = penalty, let beta = p.adaptiveKLBeta {
      let klDivergence = network(trajectory.observation).actionDistribution.klDivergence(
        to: actionDistribution)
      let klMean = klDivergence.mean().scalarized()
      if klMean < p.adaptiveKLTarget / p.adaptiveKLToleranceFactor {
        p.adaptiveKLBeta = max(beta / p.adaptiveKLBetaScalingFactor, 1e-16)
      } else if klMean > p.adaptiveKLTarget * p.adaptiveKLToleranceFactor {
        p.adaptiveKLBeta = beta * p.adaptiveKLBetaScalingFactor
      }
    }

    // TODO: Update reward and observation normalizers.

    return lastEpochLoss
  }
}