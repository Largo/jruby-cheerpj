# Java libraries tried in the page on 2026-10-16 (CheerpJ 4.3, Java 17). All of these work.
# The jars are on the page's default classpath (fetched by ./run.sh prepare).
# Did NOT work: javax.sound (MIDI and sampled audio: CheerpJ provides no output line), XSLT with xsl:sort (hangs the tab).

# ---- ZXing: make a QR code, show it, decode it again ----
bits = com.google.zxing.qrcode.QRCodeWriter.new.encode('Hello from JRuby in the browser!', com.google.zxing.BarcodeFormat::QR_CODE, 220, 220)
img = com.google.zxing.client.j2se.MatrixToImageWriter.toBufferedImage(bits)
f = javax.swing.JFrame.new('QR'); f.add(javax.swing.JLabel.new(javax.swing.ImageIcon.new(img))); f.pack; f.set_location(10, 10); f.visible = true
src = com.google.zxing.client.j2se.BufferedImageLuminanceSource.new(img)
com.google.zxing.MultiFormatReader.new.decode(com.google.zxing.BinaryBitmap.new(com.google.zxing.common.HybridBinarizer.new(src))).getText

# ---- RSyntaxTextArea + FlatLaf: a Ruby code editor ----
com.formdev.flatlaf.FlatDarkLaf.setup
ta = org.fife.ui.rsyntaxtextarea.RSyntaxTextArea.new(12, 40)
ta.syntax_editing_style = org.fife.ui.rsyntaxtextarea.SyntaxConstants::SYNTAX_STYLE_RUBY
ta.code_folding_enabled = true
ta.text = "class Greeter\n  def initialize(name) = @name = name\n  def hi = puts(\"Hello, \#{@name}!\")\nend\n\nGreeter.new('JRuby').hi  # runs in the browser\n"
f2 = javax.swing.JFrame.new('Ruby editor (RSyntaxTextArea + FlatLaf dark)')
f2.add(org.fife.ui.rtextarea.RTextScrollPane.new(ta)); f2.pack; f2.set_location(250, 10); f2.visible = true
ta.syntax_editing_style

# ---- JFreeChart: dice-roll histogram ----
rolls = Array.new(5000) { rand(1..6) + rand(1..6) }.tally.sort.to_h
ds = org.jfree.data.category.DefaultCategoryDataset.new
rolls.each { |sum, n| ds.addValue(n, 'rolls', sum.to_s) }
chart = org.jfree.chart.ChartFactory.createBarChart('5000 rolls of two dice', 'sum', 'count', ds)
f3 = javax.swing.JFrame.new('JFreeChart'); f3.add(org.jfree.chart.ChartPanel.new(chart)); f3.set_size(420, 300); f3.set_location(10, 260); f3.visible = true
rolls.size

# ---- H2: an in-memory SQL database over JDBC ----
c = org.h2.Driver.new.connect('jdbc:h2:mem:demo', java.util.Properties.new)
s = c.createStatement
s.execute("CREATE TABLE langs(name VARCHAR, born INT)")
[['Ruby', 1995], ['Java', 1995], ['JRuby', 2001], ['Crystal', 2014]].each { |n, y| s.execute("INSERT INTO langs VALUES('#{n}', #{y})") }
rs = s.executeQuery("SELECT born, LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) FROM langs GROUP BY born ORDER BY born")
out = []; out << "#{rs.getInt(1)}: #{rs.getString(2)}" while rs.next
out

# ---- dyn4j: 2D physics (a bouncing ball) ----
w = org.dyn4j.world.World.new
ground = org.dyn4j.dynamics.Body.new; ground.addFixture(org.dyn4j.geometry.Geometry.createRectangle(20, 1)); ground.setMass(org.dyn4j.geometry.MassType::INFINITE); w.addBody(ground)
ball = org.dyn4j.dynamics.Body.new; fx = ball.addFixture(org.dyn4j.geometry.Geometry.createCircle(0.5)); fx.setRestitution(0.8); ball.setMass(org.dyn4j.geometry.MassType::NORMAL); ball.translate(0, 10); w.addBody(ball)
ys = (1..180).map { w.step(1); ball.getTransform.getTranslationY.round(2) }
[ys.first, ys.min, ys.last]

# ---- Rhino: run JavaScript from Ruby ----
cx = org.mozilla.javascript.Context.enter
cx.setOptimizationLevel(-1)
scope = cx.initStandardObjects
org.mozilla.javascript.ScriptableObject.putProperty(scope, 'rubyUpcase', org.mozilla.javascript.Context.javaToJS(->(s) { s.to_s.upcase }, scope))
cx.evaluateString(scope, "['ruby', 'java', 'js'].map(function (x) { return x + '!'; }).join(' ')", 'demo', 1, nil)

# ---- JLaTeXMath: typeset a formula ----
icon = org.scilab.forge.jlatexmath.TeXFormula.new('x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}').createTeXIcon(org.scilab.forge.jlatexmath.TeXConstants::STYLE_DISPLAY, 28)
f4 = javax.swing.JFrame.new('JLaTeXMath'); f4.add(javax.swing.JLabel.new(icon)); f4.pack; f4.set_location(450, 300); f4.visible = true
[icon.getIconWidth, icon.getIconHeight]
