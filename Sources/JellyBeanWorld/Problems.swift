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

import NELFramework

public struct CombinedReward: JellyBeanWorldRewardFunction {
  public let rewardFunctions: [JellyBeanWorldRewardFunction]

  public init(_ rewardFunctions: JellyBeanWorldRewardFunction...) {
    self.rewardFunctions = rewardFunctions
  }

  public func callAsFunction(
    previousItems: [Item: UInt32]?,
    currentItems: [Item: UInt32]?
  ) -> Float {
    var reward: Float = 0.0
    for rewardFunction in rewardFunctions {
      reward += rewardFunction(previousItems: previousItems, currentItems: currentItems)
    }
    return reward
  }
}

public struct ItemCollectionReward: JellyBeanWorldRewardFunction {
  public let item: Item
  public let reward: Float

  public init(item: Item, reward: Float) {
    self.item = item
    self.reward = reward
  }

  public func callAsFunction(
    previousItems: [Item: UInt32]?,
    currentItems: [Item: UInt32]?
  ) -> Float {
    Float((currentItems?[item] ?? 0) - (previousItems?[item] ?? 0)) * reward
  }
}
