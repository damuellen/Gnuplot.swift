// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Gnuplot",
  products: [.library(name: "Gnuplot", targets: ["Gnuplot"])],
  targets: [.target(name: "Gnuplot", dependencies: [])]
)
