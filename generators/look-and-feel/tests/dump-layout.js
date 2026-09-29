var out = [];
var ps = panels();
for (var i = 0; i < ps.length; i++) {
  var p = ps[i];
  out.push("panel " + p.id + " loc=" + p.location + " h=" + p.height + " len=" + p.lengthMode + " float=" + p.floating + " hide=" + p.hiding + " align=" + p.alignment);
  var ws = p.widgets();
  for (var j = 0; j < ws.length; j++) out.push("   " + ws[j].id + " " + ws[j].type);
}
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
  var d = ds[i];
  d.currentConfigGroup = [];
  out.push("desktop " + d.id + " " + d.type + " screen=" + d.screen + " wp=" + d.wallpaperPlugin);
  out.push("   geom " + d.readConfig("ItemGeometries-1440x900", ""));
  var ws = d.widgets();
  for (var j = 0; j < ws.length; j++) out.push("   " + ws[j].id + " " + ws[j].type + " bg=" + ws[j].userBackgroundHints);
}
print(out.join("\n") + "\n");
