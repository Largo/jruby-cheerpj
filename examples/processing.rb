# Processing (processing.org) sketches written in Ruby. The page puts Processing 4.5.7 on the
# classpath. Paste one sketch at a time. Notes for Ruby programmers:
#   - Processing methods can be called in snake_case (background, no_stroke, stroke_weight...).
#   - Processing *fields* keep their Java names: mouseX, mouseY, pmouseX, frameCount, width, height.
#   - `mousePressed` the field is shadowed by the mousePressed() event method; use the event
#     methods (mousePressed / mouseDragged / keyPressed) instead.
#   - An exception inside draw stops the sketch; the trace goes to the "JVM console" section.
java_import 'processing.core.PApplet'

# ---- 1. Infinity loop: animation ----
class Infinity < PApplet
  def settings = size(400, 300)
  def setup
    background(30)
    no_stroke
  end
  def draw
    t = frameCount * 0.05
    fill((frameCount * 3) % 255, 120, 220, 180)
    ellipse(200 + 120 * Math.cos(t), 150 + 80 * Math.sin(2 * t), 24, 24)
  end
end
PApplet.run_sketch(["Infinity"].to_java(:string), Infinity.new)

# ---- 2. Paint: drag the mouse inside the window ----
class Paint < PApplet
  def settings = size(400, 300)
  def setup = background(255)
  def draw; end
  def mouseDragged(*)
    stroke((frameCount * 2) % 255, 90, 200)
    stroke_weight(6)
    line(pmouseX, pmouseY, mouseX, mouseY)
  end
  def keyPressed(*) = background(255)   # any key clears
end
PApplet.run_sketch(["Paint"].to_java(:string), Paint.new)

# ---- 3. Bouncing balls: plain Ruby objects, Processing just draws ----
Ball = Struct.new(:x, :y, :dx, :dy, :r) do
  def move(w, h)
    self.dx = -dx if x < r || x > w - r
    self.dy = -dy if y < r || y > h - r
    self.x += dx
    self.y += dy
  end
end

class Balls < PApplet
  def settings = size(400, 300)
  def setup
    @balls = Array.new(12) { Ball.new(random(20, 380), random(20, 280), random(-3, 3), random(-3, 3), random(8, 20)) }
  end
  def draw
    background(245)
    @balls.each do |b|
      b.move(width, height)
      fill(b.r * 12, 140, 255 - b.r * 8)
      ellipse(b.x, b.y, b.r * 2, b.r * 2)
    end
  end
  def mousePressed(*) = @balls << Ball.new(mouseX, mouseY, random(-3, 3), random(-3, 3), random(8, 20))
end
PApplet.run_sketch(["Balls"].to_java(:string), Balls.new)
