import AppKit
import QuartzCore
final class DataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
 func numberOfRows(in tableView: NSTableView) -> Int { 3 }
 func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { let view = HighlightRow(); view.style = .mist; return view }
 func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
  let view = CandidateCellView(frame:NSRect(x:0,y:0,width:500,height:60))
  let label = NSTextField(labelWithString:"候选 \(row)"); label.frame = NSRect(x:20,y:20,width:200,height:25);view.addSubview(label);view.textField=label;let path=NSTextField(labelWithString:"/example/path");view.subtitleField=path;view.addSubview(path);return view
 }
}
@main struct Test {
 static func main() {
  let app = NSApplication.shared;app.setActivationPolicy(.accessory)
  let window = NSWindow(contentRect:NSRect(x:0,y:0,width:550,height:260),styleMask:.borderless,backing:.buffered,defer:false)
  window.level = .floating;window.center()
  let root = NSView(frame:window.contentView!.bounds);root.wantsLayer = true;window.contentView=root
  let scroll = NSScrollView(frame:NSRect(x:10,y:10,width:530,height:220));scroll.drawsBackground=false
  if #available(macOS 26.0, *) { let glass=NSGlassEffectView(frame:root.bounds);let content=NSView(frame:root.bounds);glass.contentView=content;root.addSubview(glass);content.addSubview(scroll) } else {root.addSubview(scroll)}
  let table=NSTableView(frame:scroll.bounds);let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("name"));column.width=520;table.addTableColumn(column);table.headerView=nil;table.rowHeight=60;table.backgroundColor = .clear
  let data=DataSource();table.dataSource=data;table.delegate=data;scroll.documentView=table
  table.reloadData();table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
  app.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil);app.finishLaunching()
  func pump(_ seconds: Double) {
   let deadline=Date().addingTimeInterval(seconds)
   while Date()<deadline {
    if let event=app.nextEvent(matching:.any,until:Date().addingTimeInterval(0.03),inMode:.default,dequeue:true){app.sendEvent(event)}
    app.updateWindows()
   }
  }
  func material(_ row: Int) -> HDRSelectionView {
   table.rowView(atRow:row,makeIfNecessary:false)!.subviews.compactMap{$0 as? HDRSelectionView}.first!
  }
  pump(3)
  precondition(material(0).hasPresentedFrame, "Selected table row must actually present, not merely have a Metal device")
  precondition(material(0).metalLayer.drawableSize.width > 0)
  let idleCount=material(0).presentedFrameCount
  pump(0.5)
  precondition(material(0).presentedFrameCount == idleCount, "Idle row must not enter a presentation loop")
  let stableSurface = material(0)
  let status = NSTextField(labelWithString: "索引状态")
  status.frame=NSRect(x:10,y:235,width:400,height:20);root.addSubview(status)
  for index in 0..<8 {
   status.stringValue="增量更新 · 索引 \(index) 项"
   root.needsDisplay=true
   table.reloadData(forRowIndexes:IndexSet(integer:0),columnIndexes:IndexSet(integer:0))
   table.layoutSubtreeIfNeeded()
   pump(0.05)
   precondition(material(0) === stableSurface && material(0).hasPresentedFrame, "Cell/status refresh must retain the presented HDR surface")
  }
  precondition(material(0).presentedFrameCount == idleCount,"Status-only refresh must not re-render Metal")
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  pump(1)
  precondition(!material(0).active && !material(0).hasPresentedFrame)
  precondition(material(1).hasPresentedFrame && !material(2).active)
  let pearlRow = table.rowView(atRow:1,makeIfNecessary:false)! as! HighlightRow
  pearlRow.style = .pearl
  pump(1)
  precondition(material(1).material == .pearl && material(1).hasPresentedFrame, "Pearl must use a newly presented HDR frame after switching")
  precondition(material(1).glowLayer.shadowOpacity == 0.06 && material(1).glowLayer.shadowRadius == 4,
   "Pearl must retain its soft shadow rather than celadon's colored halo")
  pearlRow.style = .marker
  pump(1)
  precondition(material(1).material == .marker && material(1).hasPresentedFrame,
   "Marker must present its own HDR frame after switching from pearl")
  precondition(material(1).glowLayer.isHidden, "Marker must not inherit pearl shadow or celadon halo")
  let selectedCell = table.view(atColumn:0,row:1,makeIfNecessary:false)! as! CandidateCellView
  precondition(selectedCell.textField!.textColor == .white)
  precondition(selectedCell.subtitleField!.textColor == NSColor.white.withAlphaComponent(0.72))
  table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);pump(0.3)
  precondition(selectedCell.textField!.textColor == .labelColor, "Deselecting blue must restore the normal text palette")
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);pump(0.5)
  precondition(selectedCell.textField!.textColor == .white)
  pearlRow.style = .graphite; pump(0.2)
  precondition(!material(1).active && selectedCell.textField!.textColor == .white,
   "Graphite must keep white title text without requesting HDR")
  precondition(selectedCell.subtitleField!.textColor == SelectionPaint.inverseSubtitleColor)
  table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);pump(0.2)
  precondition(selectedCell.textField!.textColor == .labelColor && selectedCell.subtitleField!.textColor == .secondaryLabelColor,
   "Deselecting graphite must restore both text colors")
  pearlRow.style = .marker
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);pump(0.5)
  let markerIdleCount = material(1).presentedFrameCount
  pump(0.3)
  precondition(material(1).presentedFrameCount == markerIdleCount, "Marker must not introduce idle rendering")
  window.orderOut(nil);pump(0.2)
  precondition(!material(1).hasPresentedFrame)
  window.makeKeyAndOrderFront(nil);pump(2)
  precondition(material(1).hasPresentedFrame,"Reopened search must restore selected material")
  let resumedCount=material(1).presentedFrameCount; pump(0.5)
  precondition(material(1).presentedFrameCount == resumedCount)
  window.orderOut(nil)
  print("PASS: native glass + table row presentation; selection switch; hide/reopen; zero idle frame submissions; stable HDR across status/cell refresh")
 }
}
