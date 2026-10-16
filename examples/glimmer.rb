# Glimmer DSL for Swing (github.com/AndyObtiva/glimmer-dsl-swing) in the browser.
# Same Glimmer DSL as Glimmer DSL for SWT, rendered by Swing (SWT needs native GTK libraries,
# which a browser JVM cannot load). Paste the first block, then any of the others.
# Keywords are the Swing class names in snake_case: JTextField -> j_text_field (jbutton, jlabel
# and jframe also work in the short form).

# ---- Setup: load Glimmer (about 5-8 s the first time) ----
require 'glimmer-cheerpj'
include Glimmer

# ---- 1. Hello, World! ----
jframe('Hello, World!') {
  location 10, 10
  jlabel('Hello, World!')
}.show

# ---- 2. Data binding: the button observes a plain Ruby model ----
class Counter
  attr_accessor :count
  def initialize = self.count = 0
end

@counter = Counter.new
observe(@counter, :count) { |n| @button.text = "Click To Increment: #{n}" }
jframe('Hello, Button!') {
  location 10, 160
  @button = jbutton('Click To Increment: 0') {
    on_action_performed { @counter.count += 1 }
  }
}.show

# ---- 3. Temperature converter: layout, text field, key events ----
jframe('Celsius to Fahrenheit') {
  location 10, 310
  j_panel {
    layout java.awt.GridLayout.new(2, 2, 8, 8)
    jlabel('Celsius:')
    @celsius = j_text_field('20') {
      on_key_released do
        c = Float(@celsius.text, exception: false)
        @fahrenheit.text = c ? format('%.1f °F', c * 9 / 5 + 32) : '?'
      end
    }
    jlabel('Fahrenheit:')
    @fahrenheit = jlabel('68.0 °F')
  }
}.show

# ---- 4. Shapes: declarative Java2D ----
jframe('Hello, Shapes!') {
  minimum_size 400, 400
  location 380, 10
  arc(40, 40, 90, 90, 30, 230, 2) { fill_paint 255, 0, 0; draw_paint 0, 128, 255; stroke 3 }
  rectangle(140, 40, 180, 90) { fill_paint 255, 255, 0; draw_paint 255, 0, 0; stroke 3 }
  round_rectangle(140, 140, 180, 90, 60, 40) { fill_paint 255, 255, 0; draw_paint 255, 0, 0; stroke 3 }
  ellipse(140, 240, 180, 90) { fill_paint 255, 255, 0; draw_paint 255, 0, 0; stroke 3 }
  line(180, 60, 280, 110) { draw_paint 255, 0, 0; stroke 3 }
  cubic_curve(190, 60, 240, 40, 220, 80, 260, 70) { draw_paint 0, 0, 255; stroke 3 }
  path {
    move_to 40, 300
    curve_to 70, 260, 80, 280, 90, 270
    curve_to 100, 280, 110, 300, 120, 290
    fill_paint 0, 255, 0; draw_paint 0, 0, 255; stroke 3
  }
}.show
