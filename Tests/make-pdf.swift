import Cocoa
let text = "The results shows that our method have a lower estimation error.\nThe response is proportional to the square of the displacement."
let data = NSMutableData()
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let consumer = CGDataConsumer(data: data as CFMutableData)!
let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
context.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let title = "Academic Assistant — PDF selection test"
title.draw(in: CGRect(x: 54, y: 675, width: 504, height: 40), withAttributes: [.font: NSFont(name: "Helvetica-Bold", size: 19)!])
text.draw(in: CGRect(x: 54, y: 530, width: 504, height: 120), withAttributes: [.font: NSFont(name: "Helvetica", size: 16)!])
NSGraphicsContext.restoreGraphicsState()
context.endPDFPage(); context.closePDF()
guard CommandLine.arguments.count == 2 else { fatalError("Usage: make-pdf <output.pdf>") }
try (data as Data).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
