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

public protocol Network: Layer {
  associatedtype State
  var state: State { get set }
  func initialize(using input: Input)
  func copy() -> Self
}

public struct LayerNetwork<WrappedLayer: Layer>: Network {
  public typealias State = None

  @noDerivative public var state: State = None()

  public var layer: WrappedLayer

  public init(_ layer: WrappedLayer) {
    self.layer = layer
  }

  public func initialize(using input: WrappedLayer.Input) {}

  @differentiable
  public func callAsFunction(_ input: WrappedLayer.Input) -> WrappedLayer.Output {
    layer(input)
  }

  public func copy() -> LayerNetwork<WrappedLayer> {
    LayerNetwork(layer)
  }
}
