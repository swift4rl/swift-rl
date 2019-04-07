import TensorFlow
import XCTest
@testable import CRetro
@testable import Retro

class EmulatorTests: XCTestCase {
  let emulatorConfig: EmulatorConfig<FilteredRetroActions> = {
    let retroURL = URL(fileURLWithPath: "/Users/eaplatanios/Development/GitHub/retro-swift/retro")
    return EmulatorConfig(
      coresInformationPath: retroURL.appendingPathComponent("cores"),
      coresPathHint: retroURL.appendingPathComponent("retro/cores"),
      gameDataPathHint: retroURL.appendingPathComponent("retro/data"))
  }()

  override func setUp() {
    try! initializeRetro(withConfig: emulatorConfig)
  }

  func testSupportedCores() {
    XCTAssert(supportedCores.keys.contains("Atari2600"))
    XCTAssert(supportedCores["Atari2600"]!.library == "stella")
    XCTAssert(supportedCores["Atari2600"]!.extensions == ["a26"])
    XCTAssert(supportedCores["Atari2600"]!.memorySize == 128)
    XCTAssert(supportedCores["Atari2600"]!.keyBinds == [
      "Z", nil, "TAB", "ENTER", "UP", "DOWN", "LEFT", "RIGHT"])
    XCTAssert(supportedCores["Atari2600"]!.buttons == [
      "BUTTON", nil, "SELECT", "RESET", "UP", "DOWN", "LEFT", "RIGHT"])
    XCTAssert(supportedCores["Atari2600"]!.actions == [
      [[], ["UP"], ["DOWN"]],
      [[], ["LEFT"], ["RIGHT"]],
      [[], ["BUTTON"]]])
  }

  // func testSupportedExtensions() {
  //   XCTAssert(supportedExtensions.keys.contains(".a26"))
  //   XCTAssert(supportedExtensions[".a26"]! == "Atari2600")
  // }

  func testGames() {
    XCTAssert(emulatorConfig.games().contains("Pong-Atari2600"))

    // print(emulatorConfig.states(for: "Pong-Atari2600"))
    // print(emulatorConfig.scenarios(for: "Pong-Atari2600"))

    let renderer = ShapedArrayPrinter<UInt8>(maxEntries: 10)
    let environment = try! Environment(for: "Airstriker-Genesis", withConfig: emulatorConfig)
    environment.reset()
    environment.render(using: renderer)
    let numButtons = environment.buttons.count
    let action = ShapedArray<Int32>(
      shape: [numButtons],
      scalars: [Int32](repeating: 1, count: numButtons))
    for _ in 0..<1000 {
      print(environment.step(taking: action).reward[0])
    }
    environment.render(using: renderer)
  }

	// func testEmulatorScreenRate() {
  //   let romPath = "/Users/eaplatanios/Development/GitHub/retro-swift/retro/tests/roms/Dekadence-Dekadrive.md"
  //   let emulator = emulatorCreate(romPath)
  //   let screenRate = emulatorGetScreenRate(emulator)
  //   XCTAssertEqual(screenRate, 0.0)
  // }
}

#if os(Linux)
extension EmulatorTests {
  static var allTests : [(String, (EmulatorTests) -> () throws -> Void)] {
    return [
      ("testSupportedCores", testSupportedCores),
      ("testSupportedExtensions", testSupportedExtensions),
      ("testGames", testGames)
    ]
  }
}
#endif
