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

public protocol LearningRateSchedule {
  associatedtype Scalar: FloatingPoint
  func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar
}

extension LearningRateSchedule {
  public func composed<Schedule: LearningRateSchedule>(
    with other: Schedule
  ) -> ComposedLearningRateSchedule<Self, Schedule> {
    ComposedLearningRateSchedule(schedule1: self, schedule2: other)
  }
}

public struct ComposedLearningRateSchedule<
  Schedule1: LearningRateSchedule,
  Schedule2: LearningRateSchedule
>: LearningRateSchedule where Schedule1.Scalar == Schedule2.Scalar {
  public typealias Scalar = Schedule1.Scalar

  public let schedule1: Schedule1
  public let schedule2: Schedule2

  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    schedule1(step: step, learningRate: schedule2(step: step, learningRate: learningRate))
  }
}

/// Dummy learning rate schedule that represents no schedule being used. This is useful as a
/// default value whenever a learning rate schedule argument is used.
public struct FixedLearningRate<Scalar: FloatingPoint>: LearningRateSchedule {
  @inlinable
  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    learningRate
  }
}

/// Linear learning rate decay schedule.
///
/// The decayed learning rate is computed as follows:
/// ```
/// decayed = learningRate + step * slope
/// decayedLearningRate = max(lowerBound * learningRate, decayed)
/// ```
public struct LinearLearningRateDecay<Scalar: FloatingPoint>: LearningRateSchedule {
  public let slope: Scalar
  public let lowerBound: Scalar
  public let startStep: UInt64

  /// Creates a new linear learning rate decay schedule.
  ///
  /// - Parameters:
  ///   - slope: Slope of the linear decay.
  ///   - lowerBound: Minimum decayed learning rate value as a fraction of the original learning
  ///     rate value.
  ///   - startStep: Step after which to start decaying the learning rate.
  @inlinable
  public init(slope: Scalar, lowerBound: Scalar = Scalar(0), startStep: UInt64 = 0) {
    self.slope = slope
    self.lowerBound = lowerBound
    self.startStep = startStep
  }

  @inlinable
  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    if step < startStep { return learningRate }
    let step = step - startStep
    let decayed = learningRate + Scalar(step) * slope
    return max(lowerBound * learningRate, decayed)
  }
}

/// Exponential learning rate decay schedule.
///
/// The decayed learning rate is computed as follows:
/// ```
/// decay = decayRate ^ (step / decaySteps)
/// decayedLearningRate = learningRate * ((1 - lowerBound) * decay + lowerBound)
/// ```
/// where if `staircase = true`, then `step / decaySteps` uses integer division and the decayed
/// learning rate follows a staircase function.
public struct ExponentialLearningRateDecay<
  Scalar: FloatingPoint & ElementaryFunctions
>: LearningRateSchedule {
  public let decayRate: Scalar
  public let decaySteps: UInt64
  public let staircase: Bool
  public let lowerBound: Scalar
  public let startStep: UInt64

  /// Creates a new exponential learning rate decay schedule.
  ///
  /// - Parameters:
  ///   - decayRate: Decay rate.
  ///   - decaySteps: Decay steps.
  ///   - staircase: If `true`, the decay will occur at discrete intervals.
  ///   - lowerBound: Minimum decayed learning rate value as a fraction of the original learning
  ///     rate value.
  ///   - startStep: Step after which to start decaying the learning rate.
  @inlinable
  public init(
    decayRate: Scalar,
    decaySteps: UInt64,
    staircase: Bool = false,
    lowerBound: Scalar = Scalar(0),
    startStep: UInt64 = 0
  ) {
    self.decayRate = decayRate
    self.decaySteps = decaySteps
    self.staircase = staircase
    self.lowerBound = lowerBound
    self.startStep = startStep
  }

  @inlinable
  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    if step < startStep { return learningRate }
    let step = step - startStep
    let power = Scalar(step) / Scalar(decaySteps)
    let decay = Scalar.pow(decayRate, staircase ? power.rounded(.down) : power)
    return learningRate * ((1 - lowerBound) * decay + lowerBound)
  }
}

/// Reciprocal square root learning rate decay schedule.
///
/// The decayed learning rate is computed as follows:
/// ```
/// decay = decayFactor / sqrt(max(step, decayThreshold))
/// decayedLearningRate = learningRate * ((1 - lowerBound) * decay + lowerBound)
/// ```
public struct RSqrtLearningRateDecay<
  Scalar: FloatingPoint & ElementaryFunctions
>: LearningRateSchedule {
  public let decayFactor: Scalar
  public let decayThreshold: Scalar
  public let lowerBound: Scalar
  public let startStep: UInt64

  /// Creates a new reciprocal square root learning rate decay schedule.
  ///
  /// - Parameters:
  ///   - decayFactor: Decay factor.
  ///   - decayThreshold: Decay threshold.
  ///   - lowerBound: Minimum decayed learning rate value as a fraction of the original learning
  ///     rate value.
  ///   - startStep: Step after which to start decaying the learning rate.
  @inlinable
  public init(
    decayFactor: Scalar,
    decayThreshold: Scalar,
    lowerBound: Scalar = Scalar(0),
    startStep: UInt64 = 0
  ) {
    self.decayFactor = decayFactor
    self.decayThreshold = decayThreshold
    self.lowerBound = lowerBound
    self.startStep = startStep
  }

  @inlinable
  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    if step < startStep { return learningRate }
    let step = step - startStep
    let decay = decayFactor / Scalar.sqrt(max(Scalar(step), decayThreshold))
    return learningRate * ((1 - lowerBound) * decay + lowerBound)
  }
}

/// Cosine learning rate decay schedule.
///
/// The decayed learning rate is computed as follows:
/// ```
/// decay = 0.5 * (1 + cos(pi * min(step, cycleStepCount) / cycleStepCount))
/// decayedLearningRate = learningRate * ((1 - lowerBound) * decay + lowerBound)
/// ```
public struct CosineLearningRateDecay<
  Scalar: FloatingPoint & ElementaryFunctions
>: LearningRateSchedule {
  public let cycleStepCount: UInt64
  public let lowerBound: Scalar
  public let startStep: UInt64

  /// Creates a new cosine learning rate decay schedule.
  ///
  /// - Parameters:
  ///   - cycleStepCount: Cosine decay cycle in terms of number of steps.
  ///   - lowerBound: Minimum decayed learning rate value as a fraction of the original learning
  ///     rate value.
  ///   - startStep: Step after which to start decaying the learning rate.
  @inlinable
  public init(
    cycleStepCount: UInt64,
    lowerBound: Scalar = Scalar(0),
    startStep: UInt64 = 0
  ) {
    self.cycleStepCount = cycleStepCount
    self.lowerBound = lowerBound
    self.startStep = startStep
  }

  @inlinable
  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    if step < startStep { return learningRate }
    let step = step - startStep
    let cosine = Scalar.cos(Scalar(min(step, cycleStepCount)))
    let decay = (1 + cosine) * Scalar.pi / Scalar(2 * cycleStepCount)
    return learningRate * ((1 - lowerBound) * decay + lowerBound)
  }
}

/// Cycle-linear 10x learning rate decay schedule.
///
/// The decayed learning rate is computed as follows:
/// ```
/// cyclePosition = 1 - abs((step % (2 * cycleStepCount) - cycleStepCount) / cycleStepCount)
/// decay = (0.1 + cyclePosition) * 3
/// decayedLearningRate = learningRate * ((1 - lowerBound) * decay + lowerBound)
/// ```
public struct CycleLinear10xLearningRateDecay<
  Scalar: FloatingPoint & ElementaryFunctions
>: LearningRateSchedule {
  public let cycleStepCount: UInt64
  public let lowerBound: Scalar
  public let startStep: UInt64

  /// Creates a new cycle-linear 10x learning rate decay schedule.
  ///
  /// - Parameters:
  ///   - cycleStepCount: Cycle-linear 10x decay cycle in terms of number of steps.
  ///   - lowerBound: Minimum decayed learning rate value as a fraction of the original learning
  ///     rate value.
  ///   - startStep: Step after which to start decaying the learning rate.
  @inlinable
  public init(
    cycleStepCount: UInt64,
    lowerBound: Scalar = Scalar(0),
    startStep: UInt64 = 0
  ) {
    self.cycleStepCount = cycleStepCount
    self.lowerBound = lowerBound
    self.startStep = startStep
  }

  @inlinable
  public func callAsFunction(step: UInt64, learningRate: Scalar) -> Scalar {
    if step < startStep { return learningRate }
    let step = step - startStep
    let ratio = Scalar((step % (2 * cycleStepCount) - cycleStepCount)) / Scalar(cycleStepCount)
    let cyclePosition = 1 - abs(ratio)
    let decay = (1 / Scalar(10) + cyclePosition) * 3 // 10x difference in each cycle (0.3 - 3).
    return learningRate * ((1 - lowerBound) * decay + lowerBound)
  }
}
