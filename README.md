# Gnuplot Swift

So, you have an amazing Swift project for which you need plotting capabilities.
You have searched around and discovered that the available options for swift programmers are 
rather limited compared to other programming languages, such as Python, for example, which has [matplotlib].

Instead of reinventing the wheel. Why not stick to the old tried and true.
And use this convenient wrapper around gnuplot.

Tested under Linux, macOS, and Windows.
Works also in Swift Playground.

## Example
```Swift
import Gnuplot

var curves = [[[Double]]](repeating: [[Double]](), count: 3)
curves = [ // Supports array of arrays
  [[1,2],[2,4],[3,5],[4,6],[5,7]],
  [[1,3],[2,4],[3,6],[4,6],[5,8]],
  [[1,1],[2,2],[3,4],[4,5],[5,6]]]

let plot = Gnuplot(xys: curves, titles: ["Best1", "Best2", "Best3"])
.set(title: "Curves").set(xlabel: "Iteration").set(ylabel: "Foo")

plot.svg // string with SVG plot (executes gnuplot)

plot.image // macOS only (executes gnuplot)

plot.commands(.svg(path: "")) // returns the gnuplot commands 

try plot(.png(path: "Curves.png")) // execute gnuplot
```

## Initializers
```Swift
    public init<T>(xys: [[[T]]], titles: [String] = [], style: Style = .linePoints) where T : FloatingPoint

    public init<T>(xy1s: [[[T]]], xy2s: [[[T]]] = [], titles: [String] = [], style: Style = .linePoints) where T : FloatingPoint

    public convenience init<S, F>(xys: S..., titles: [String] = [], style: Style = .linePoints) where S : Sequence, F : FloatingPoint, F : SIMDScalar, S.Element == SIMD2<F>

    public convenience init<S, F>(xys: S..., titles: [String] = [], style: Style = .linePoints) where S : Sequence, F : FloatingPoint, S.Element == [F]

    public convenience init<S, F>(xs: S..., ys: S..., titles: String..., style: Style = .linePoints) where S : Collection, F : FloatingPoint, F == S.Element

    public convenience init<X, Y, F, S>(xs: X, ys: Y, titles: String..., style: Style = .linePoints) where X : Collection, Y : Collection, F : FloatingPoint, F == X.Element, S : SIMD, S == Y.Element, X.Element == S.Scalar

    public convenience init<T>(xy1s: [[T]]..., xy2s: [[T]]..., titles: String..., style: Style = .linePoints) where T : FloatingPoint
```
