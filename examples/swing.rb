# Swing in the browser, driven by Ruby. Paste blocks one at a time; windows appear in the
# "Java windows" area under the input box. Windows can be dragged, resized and closed.

# ---- 1. A click counter: a Ruby block is the ActionListener ----
java_import javax.swing.JFrame
java_import javax.swing.JButton
java_import javax.swing.JLabel
java_import java.awt.BorderLayout
java_import java.awt.Font

clicks = 0
frame  = JFrame.new("Hello from Ruby")
label  = JLabel.new("Clicks: 0", javax.swing.SwingConstants::CENTER)
label.font = Font.new("SansSerif", Font::BOLD, 28)
button = JButton.new("Click me")
button.add_action_listener { clicks += 1; label.text = "Clicks: #{clicks}" }
frame.content_pane.add(label, BorderLayout::CENTER)
frame.content_pane.add(button, BorderLayout::SOUTH)
frame.set_size(360, 220)
frame.set_location(20, 20)
frame.visible = true

# ---- 2. A form: text field + list, Ruby does the work ----
java_import javax.swing.JTextField
java_import javax.swing.JList
java_import javax.swing.DefaultListModel
java_import javax.swing.JScrollPane

words = DefaultListModel.new
input = JTextField.new(20)
input.add_action_listener do
  text = input.text.strip
  unless text.empty?
    words.add_element("#{text}  →  #{text.reverse}  (#{text.length} chars)")
    input.text = ""
  end
end
f2 = JFrame.new("Type and press Enter")
f2.content_pane.add(input, BorderLayout::NORTH)
f2.content_pane.add(JScrollPane.new(JList.new(words)), BorderLayout::CENTER)
f2.set_size(360, 240)
f2.set_location(400, 20)
f2.visible = true

# ---- 3. Custom painting: subclass JPanel in Ruby ----
java_import javax.swing.JPanel
java_import java.awt.Color
java_import java.awt.RenderingHints

class Rainbow < JPanel
  def paintComponent(g)
    # (JRuby can't `super` into the protected JPanel#paintComponent, so clear by hand)
    g.color = Color::WHITE
    g.fillRect(0, 0, width, height)
    g.setRenderingHint(RenderingHints::KEY_ANTIALIASING, RenderingHints::VALUE_ANTIALIAS_ON)
    12.times do |i|
      g.color = Color.getHSBColor(i / 12.0, 0.8, 0.95)
      g.fillOval(20 + i * 22, 40 + (Math.sin(i / 2.0) * 30).to_i, 60, 60)
    end
  end
end
f3 = JFrame.new("Painted by Ruby")
f3.content_pane.add(Rainbow.new)
f3.set_size(380, 200)
f3.set_location(20, 260)
f3.visible = true
