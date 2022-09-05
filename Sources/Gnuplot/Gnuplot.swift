//  Copyright 2021 Daniel Müllenborn
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import Foundation

#if canImport(Cocoa)
import Cocoa
#endif
#if canImport(PythonKit)
import PythonKit
#endif
/// Create graphs using gnuplot.
public final class Gnuplot: CustomStringConvertible {
#if canImport(Cocoa) && !targetEnvironment(macCatalyst)
  public var image: NSImage? {
    guard let data = try? callAsFunction(.pngSmall("")) else { return nil }
#if swift(>=5.4)
    return NSImage(data: data)
#else
    return NSImage(data: data!)
#endif
  }
#endif
#if canImport(PythonKit)
  @discardableResult public func display() -> Gnuplot {
    settings["term"] = "svg size \(width),\(height)"
    settings["object"] =
    "rectangle from graph 0,0 to graph 1,1 behind fillcolor rgb '#EBEBEB' fillstyle solid noborder"
    guard let svg = svg else { return self }
    settings.removeValue(forKey: "term")
    settings.removeValue(forKey: "object")
    let display = Python.import("IPython.display")
    display.display(display.SVG(data: svg))
    return self
  }
#endif
  public init(data: String, style: Style = .linePoints) {
    self.datablock = "\n$data <<EOD\n" + data + "\n\n\nEOD\n\n"
    self.defaultPlot = "plot $data"
    self.settings = defaultSettings()
  }
  public init(plot: String, style: Style = .linePoints) {
    self.datablock = ""
    self.defaultPlot = plot
    self.settings = defaultSettings()
  }
#if os(Linux)
  deinit {
    if let process = Gnuplot.running, process.isRunning {
      let stdin = process.standardInput as! Pipe
      stdin.fileHandleForWriting.write("\nexit\n".data(using: .utf8)!)
      process.waitUntilExit()
      Gnuplot.running = nil
    }
  }
  private static var running: Process?
#endif

  public func svg(width: Int = width, height: Int = height)-> String? {
    do {
      guard let data = try callAsFunction(.svg(width: width, height: height)) else { return nil }
      let svg: Data = data.dropFirst(270)
      return #"<svg width="\#(width+25)" height="\#(height)" viewBox="0 0 \#(width+25) \#(height)" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">"#
      + String(decoding: svg, as: Unicode.UTF8.self)
    } catch {
      print(error)
      return nil
    }
  }

#if os(iOS)
  @discardableResult public func callAsFunction(_ terminal: Terminal) throws -> Data? {
    commands(terminal).data(using: .utf8)
  }
#else
  public static func process() -> Process {
#if os(Linux)
    if let process = Gnuplot.running { if process.isRunning { return process } }
    let gnuplot = Process()
    gnuplot.executableURL = "/usr/bin/gnuplot"
    gnuplot.arguments = ["--persist"]
    Gnuplot.running = gnuplot
#else
    let gnuplot = Process()
#endif
#if os(Windows)
    gnuplot.executableURL = "C:/bin/gnuplot.exe"
#elseif os(macOS)
    if #available(macOS 10.13, *) {
      gnuplot.executableURL = "/opt/homebrew/bin/gnuplot"
    } else {
      gnuplot.launchPath = "/opt/homebrew/bin/gnuplot"
    }
#endif
#if !os(Windows)
    gnuplot.standardInput = Pipe()
#endif
    gnuplot.standardOutput = Pipe()
    gnuplot.standardError = nil
    return gnuplot
  }
#endif
#if os(Windows)
  @discardableResult public func callAsFunction(_ terminal: Terminal) throws -> Data? {
    let gnuplot = Gnuplot.process()
    let plot = URL.temporaryFile().appendingPathExtension("plot")
    try commands(terminal).data(using: .utf8)!.write(to: plot)
    gnuplot.arguments = [plot.path]
    try gnuplot.run()
    let stdout = gnuplot.standardOutput as! Pipe
    let data = try stdout.fileHandleForReading.readToEnd()
    try plot.removeItem()
    return data
  }
#elseif !os(iOS)
  /// Execute the plot commands.
  @discardableResult public func callAsFunction(_ terminal: Terminal) throws -> Data? {
    let gnuplot = Gnuplot.process()
    if #available(macOS 10.13, *) {
      if !gnuplot.isRunning { try gnuplot.run() }
    } else {
      if !gnuplot.isRunning { gnuplot.launch() }
    }
    let stdin = gnuplot.standardInput as! Pipe
    stdin.fileHandleForWriting.write(commands(terminal).data(using: .utf8)!)
    let stdout = gnuplot.standardOutput as! Pipe
#if os(Linux)
    let endOfData: Data
    if case .svg(_,_) = terminal {
      endOfData = "</svg>\n\n".data(using: .utf8)!
    } else if case .pdf(let path) = terminal, path.isEmpty {
      endOfData = Data([37, 37, 69, 79, 70, 10])  // %%EOF
    } else if case .pngSmall(let path) = terminal, path.isEmpty {
      endOfData = Data([73, 69, 78, 68, 174, 66, 96, 130])  // IEND
    } else {
      return nil
    }
    var data = Data()
    while data.suffix(endOfData.count) != endOfData {
      data.append(stdout.fileHandleForReading.availableData)
    }
    return data
#else
    if #available(macOS 10.15.4, *) {
      try stdin.fileHandleForWriting.close()
      return try stdout.fileHandleForReading.readToEnd()
    } else {
      stdin.fileHandleForWriting.closeFile()
      return stdout.fileHandleForReading.readDataToEndOfFile()
    }
#endif
  }
#endif
  public func commands(_ terminal: Terminal? = nil) -> String {
    let config: String
    if let terminal = terminal {
      if case .svg = terminal {
        config = settings.merging(terminal.output) { old, _ in old }.concatenated + SVG.concatenated
      } else if case .pdf = terminal {
        config = settings.merging(terminal.output) { old, _ in old }.concatenated + PDF.concatenated
      } else {
        config =
        settings.merging(terminal.output) { old, _ in old }.concatenated + PNG.concatenated
        + SVG.concatenated
      }
    } else {
      config = settings.concatenated
    }
    let plot = userPlot ?? defaultPlot
    if multiplot > 1 {
      let layout: (rows: Int, cols: Int)
      if multiplot == 9 {
        layout = (3, 3)
      } else {
        let z = multiplot.quotientAndRemainder(dividingBy: 2)
        let (x, y) = (z.quotient, (multiplot / z.quotient))
        layout = (min(x, y), max(x, y) + (x > 1 && z.remainder > 0 ? 1 : 0))
      }
      return datablock + config + "\n"
      + "set multiplot layout \(layout.rows),\(layout.cols) rowsfirst\n"
      + plot + "\nreset session\nunset multiplot\n"
    }
    return datablock + config + "\n" + plot + "\nreset session\n"
  }
  public var description: String { commands() }
  public var settings: [String: String]
  public var userPlot: String? = nil

  @discardableResult public func plot(
    multi: Bool = false, index i: Int = 0, x: Int = 1, y: Int = 2, style: Style = .linePoints
  ) -> Self {
    let (s, l) = style.raw
    multiplot += multi ? 1 : 0
    if styles.isEmpty { styles = Array(stride(from: 11, through: 14, by: 1)).shuffled() }
    let command =
    "$data i \(i) u \(x):\(y) \(s) w \(l) ls \(styles.removeLast()) title columnheader(1)"

    if let plot = userPlot {
      userPlot = plot + (multi ? "\nplot " : ", ") + command
    } else {
      userPlot = "plot " + command
    }
    return self
  }

  @discardableResult public func plot(
    index i: Int = 0, x: Int = 1, y: Int = 2, label: Int, rotate: Int = 45, offset: String = "3,1.5"
  ) -> Self {
    let command =
    "$data i \(i) u \(x):\(y):\(label) with labels tc ls 18 rotate by \(rotate) offset \(offset) notitle"
    if let plot = userPlot {
      userPlot = plot + ", " + command
    } else {
      userPlot = "plot " + command
    }
    return self
  }
  @discardableResult public func set(title: String) -> Self {
    settings["title"] = "'\(title)'"
    return self
  }
  @discardableResult public func set(xlabel: String) -> Self {
    settings["xlabel"] = "'\(xlabel)'"
    return self
  }
  @discardableResult public func set(ylabel: String) -> Self {
    settings["ylabel"] = "'\(ylabel)'"
    return self
  }
  @discardableResult public func set<T: FloatingPoint>(xrange x: ClosedRange<T>) -> Self {
    settings["xrange"] = "\(x.lowerBound):\(x.upperBound)"
    return self
  }
  @discardableResult public func set<T: FloatingPoint>(yrange y: ClosedRange<T>) -> Self {
    settings["yrange"] = "\(y.lowerBound):\(y.upperBound)"
    return self
  }
  @available(macOS 10.12, *)
  @discardableResult public func set(xrange: DateInterval) -> Self {
    settings["xrange"] = "\(xrange.start.timeIntervalSince1970):\(xrange.end.timeIntervalSince1970)"
    settings["xdata"] = "time"
    settings["timefmt"] = "'%s'"
    settings["xtics rotate"] = ""

    if xrange.duration > 86400 {
      settings["xtics"] = "86400"
      settings["format x"] = "'%a'"
    } else {
      settings["xtics"] = "1800"
      settings["format x"] = "'%R'"
    }
    if xrange.duration > 86400 * 7 {
      settings["format x"] = "'%d.%m'"
    }
    return self
  }
  
  public init<Scalar: FloatingPoint, Vector: RandomAccessCollection, Tensor: RandomAccessCollection, Series: Collection>
  (y1s: Series, y2s: Series) where Tensor.Element == Vector, Vector.Element == Scalar, Series.Element == Tensor, Scalar: LosslessStringConvertible {
    var tables = [String]()
    for y1 in y1s {
      let table: String = y1.transposed().map(\.row).joined()
      tables.append("-\n" + table)
    }
    for y2 in y2s {
      let table: String = y2.transposed().map(\.row).joined()
      tables.append("-\n" + table)
    }
    self.datablock = "\n$data <<EOD\n" + tables.joined(separator: "\n\n") + "\n\n\nEOD\n\n"
    let setting = [
      "key": "off", "xdata": "time", "timefmt": "'%s'", "format x": "'%k'",
      "xtics": "21600 ", "yrange": "0:1", "ytics": "0.25", "term": "pdfcairo size 7.1, 10",
    ]
    self.settings = defaultSettings().merging(setting) { _, new in new }
    let y = y1s.count
    self.defaultPlot = y1s.enumerated().map { i, y1 -> String in
      "\nset multiplot layout 8,4 rowsfirst\n"
      + (1...y1.count).map { c in
        "plot $data i \(i) u ($0*300):\(c) axes x1y1 w l ls 31, $data i \(i+y) u ($0*300):\(c) axes x1y2 w l ls 32"
      }.joined(separator: "\n") + "\nunset multiplot"
    }.joined(separator: "\n")
  }

  public init<Scalar: FloatingPoint, Vector: Collection, Tensor: Collection, Series: Collection>
  (xys: Series, xylabels: [[String]] = [], titles: [String] = [], style: Style = .linePoints)
  where Tensor.Element == Vector, Vector.Element == Scalar, Series.Element == Tensor, Scalar: LosslessStringConvertible {
    var headers = titles.makeIterator()
    var tables = [String]()
    for (i, xy) in xys.enumerated() {
      let table: String
      if xylabels.endIndex > i {
        table = zip(xy, xylabels[i]).map { xy, label -> String in
          let vector: String = xy.map(String.init).joined(separator: " ")
          return vector + " " + label + "\n"
        }.joined()
      } else {
        table = xy.map(\.row).joined()
      }
      if let title = headers.next() {
        tables.append(title + "\n" + table)
      } else {
        tables.append("-\n" + table)
      }
    }
    self.datablock = "\n$data <<EOD\n" + tables.joined(separator: "\n\n") + "\n\nEOD\n\n"
    self.settings = defaultSettings()
    let (s, l) = style.raw
    var plot = "plot "
    plot += xys.enumerated()
      .map { i, t -> String in
        if (t.first?.count ?? 0) > 1 {
          return (2...t.first!.count).map { c -> String in
            "$data i \(i) u 1:\(c) \(s) w \(l) ls \(i+c+29) title columnheader(1)"
          }.joined(separator: ", \\\n")
        } else {
          return "$data i \(i) u 0:1 \(s) w \(l) ls \(i+31) title columnheader(1)"
        }
      }
      .joined(separator: ", \\\n")
    plot += (xylabels.isEmpty
       ? ""
       : ", \\\n"
       + xylabels.indices.map { i -> String in
      "$data i \(i) u 1:2:3 with labels tc ls 18 offset char 0,1 notitle"
    }.joined(separator: ", \\\n"))
    self.defaultPlot = plot
  }

  public init<Scalar: FloatingPoint, Vector: Collection, Tensor: Collection, Series: Collection>
  (xy1s: Series, xy2s: Series, titles: [String] = [], style: Style = .linePoints)
  where Tensor.Element == Vector, Vector.Element == Scalar, Series.Element == Tensor, Scalar: LosslessStringConvertible {
    let missingTitles = xy1s.count + xy2s.count - titles.count
    var titles = titles
    if missingTitles > 0 { titles.append(contentsOf: repeatElement("-", count: missingTitles)) }
    self.settings = defaultSettings().merging(["ytics": "nomirror", "y2tics": ""]) {
      (_, new) in new
    }
    let y1: String = zip(titles, xy1s).map { title, xys -> String in
      title + "\n" + xys.map(\.row).joined()
    }.joined(separator: "\n\n")
    let y2: String = zip(titles.dropFirst(xy1s.count), xy2s).map { title, xys -> String in
      title + " \n" + xys.map(\.row).joined()
    }.joined(separator: "\n\n")
    self.datablock =
    "\n$data <<EOD\n\(y1)" + (xy2s.isEmpty ? "" : "\n\n\(y2)") + "\n\n\nEOD\n\n"
    let (s, l) = style.raw
    var plot = "plot "
    plot += xy1s.enumerated()
      .map { i, xy -> String in
        if (xy.first?.count ?? 0) > 1 {
          return (2...xy.first!.count).map { c -> String in
            let ls = (xy2s.isEmpty ? 0 : 20) + i+c+9
            return "$data i \(i) u 1:\(c) \(s) axes x1y1 w \(l) ls \(ls) title columnheader(1)"
          }.joined(separator: ", \\\n")
        } else {
          let ls = (xy2s.isEmpty ? 0 : 20) + i+11
          return "$data i \(i) u 0:1 \(s) axes x1y1 w \(l) ls \(ls) title columnheader(1)"
        }
      }
      .joined(separator: ", \\\n") + ", \\\n"
    plot += xy2s.enumerated()
      .map { i, xy -> String in
        if (xy.first?.count ?? 0) > 1 {
          return (2...xy.first!.count).map { c -> String in
            "$data i \(i + xy1s.count) u 1:\(c) \(s) axes x1y2 w \(l) ls \(i+c+19) title columnheader(1)"
          }.joined(separator: ", \\\n")
        } else {
          return "$data i \(i + xy1s.count) u 0:1 \(s) axes x1y2 w \(l) ls \(i+21) title columnheader(1)"
        }
      }
      .joined(separator: ", \\\n")
    self.defaultPlot = plot
  }

  @available(macOS 10.12, *)
  public init<Scalar: FloatingPoint, Vector: Collection, Tensor: Collection, Series: Collection>
  (y1s: Series, y2s: Series, titles: [String] = [], range: DateInterval)
  where Tensor.Element == Vector, Vector.Element == Scalar, Series.Element == Tensor, Scalar: LosslessStringConvertible {
    var headers = titles.makeIterator()
    var tables = [String]()
    for y1 in y1s {
      let table: String = y1.map(\.row).joined()
      if let title = headers.next() {
        tables.append(title + "\n" + table)
      } else {
        tables.append("-\n" + table)
      }
    }
    for y2 in y2s {
      let table: String = y2.map(\.row).joined()
      if let title = headers.next() {
        tables.append(title + "\n" + table)
      } else {
        tables.append("-\n" + table)
      }
    }
    self.datablock = "\n$data <<EOD\n" + tables.joined(separator: "\n\n") + "\n\nEOD\n\n"
    var setting: [String: String] = [
      "xdata": "time", "timefmt": "'%s'",
      "xrange": "[\(range.start.timeIntervalSince1970):\(range.end.timeIntervalSince1970)]"
    ]
    if !y2s.isEmpty {
      setting["ytics"] = "nomirror"
      setting["y2tics"] = ""
    }

    if range.duration > 86400 {
      setting["xtics"] = "86400"
      setting["format x"] = "'%j'"
    } else {
      setting["xtics"] = "1800"
      setting["format x"] = "'%R'"
      setting["xtics rotate"] = ""
    }

    self.settings = defaultSettings().merging(setting) { _, new in new }
    var plot = "plot "
    plot += y1s.enumerated().map { i, ys -> String in
      "$data i \(i) u ($0*\(range.duration / Double(ys.count))+\(range.start.timeIntervalSince1970)):\(1) axes x1y1 w l ls \(i+11) title columnheader(1)"
    }.joined(separator: ", \\\n")
    if !y2s.isEmpty {
      plot += ", \\\n" + y2s.enumerated().map { i, ys -> String in
        "$data i \(i + y1s.count) u ($0*\(range.duration / Double(ys.count))+\(range.start.timeIntervalSince1970)):\(1) axes x1y2 w l ls \(i+21) title columnheader(1)"
      }.joined(separator: ", \\\n")
    }
    self.defaultPlot = plot
  }

  public enum Style {
    case lines(smooth: Bool)
    case linePoints
    case points
    var raw: (String, String) {
      let s: String
      let l: String
      switch self {
      case .lines(let smooth):
        s = smooth ? "smooth csplines" : ""
        l = "l"
      case .linePoints:
        s = ""
        l = "lp"
      case .points:
        s = ""
        l = "points"
      }
      return (s, l)
    }
  }
  public enum Terminal {
    case svg(width: Int, height: Int)
    case pdf(_ toFile: String)
    case png(_ toFile: String)
    case pngSmall(_ toFile: String)
    case pngLarge(_ toFile: String)
    var output: [String: String] {
#if os(Linux)
      let font = "enhanced font 'Times,"
#else
      let font = "enhanced font ',"
#endif
      switch self {
      case .svg(let w, let h):
        return ["term": "svg size \(w),\(h)", "output": ""]
      case .pdf(let path):
        return [
          "term": "pdfcairo size 10,7.1 \(font)14'", "output": path.isEmpty ? "" : "'\(path)'",
        ]
      case .png(let path):
        return [
          "term": "pngcairo size 1440, 900 \(font)12'", "output": path.isEmpty ? "" : "'\(path)'",
        ]
      case .pngSmall(let path):
        return [
          "term": "pngcairo size 1024, 720 \(font)12'", "output": path.isEmpty ? "" : "'\(path)'",
        ]
      case .pngLarge(let path):
        return [
          "term": "pngcairo size 1920, 1200 \(font)14'", "output": path.isEmpty ? "" : "'\(path)'",
        ]
      }
    }
  }
  private var styles: [Int] = []
  private var multiplot: Int = 0
  private let datablock: String
  private let defaultPlot: String
  private let SVG = ["border 31 lw 0.5 lc rgb 'black'", "grid ls 19"]
  private let PDF = ["border 31 lw 1 lc rgb 'black'", "grid ls 18"]
  private let PNG = [
    "object rectangle from graph 0,0 to graph 1,1 behind fillcolor rgb '#EBEBEB' fillstyle solid noborder"
  ]
}

fileprivate func defaultSettings() -> [String: String] {
  var dict: [String: String] = [
    "style line 18": "lt 1 lw 1 dashtype 3 lc rgb 'black'",
    "style line 19": "lt 0 lw 0.5 lc rgb 'black'",
    "label": "textcolor rgb 'black'",
    "key": "above tc ls 18",
  ]

  let dark: [String] = ["1F78B4", "33A02C", "E31A1C", "FF7F00"]
  let light: [String] = ["A6CEE3", "B2DF8A", "FB9A99", "FDBF6F"]
  let pt = [4,6,8,10].shuffled()
  pt.indices.forEach { i in
    dict["style line \(i+11)"] = "lt 1 lw 1.5 pt \(pt[i]) ps 1.0 lc rgb '#\(dark[i])'"
    dict["style line \(i+21)"] = "lt 1 lw 1.5 pt \(pt[i]+1) ps 1.0 lc rgb '#\(light[i])'"
  }
  let mat = ["0072bd", "d95319", "edb120", "7e2f8e", "77ac30", "4dbeee", "a2142f"]
  mat.indices.forEach { i in
    dict["style line \(i+31)"] = "lt 1 lw 1.5 pt 7 ps 1.0 lc rgb '#\(mat[i])'"
  }
  return dict
}

public let height = 800
public let width = 1255

extension Array where Element == String {
  var concatenated: String { self.map { "set " + $0 + "\n" }.joined() }
}
extension Dictionary where Key == String, Value == String {
  var concatenated: String { self.map { "set " + $0.key + " " + $0.value + "\n" }.joined() }
}
extension Collection where Element: FloatingPoint, Element: LosslessStringConvertible {
  var row: String { self.lazy.map(String.init).joined(separator: " ") + "\n" }
}

#if os(Windows)
extension URL {
  static func temporaryFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
  func removeItem() throws { try FileManager.default.removeItem(at: self) }
}
#endif
