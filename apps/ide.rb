# A small Ruby IDE written in Ruby, built from Java libraries, running in the browser.
#
#   RSyntaxTextArea  - code editor with Ruby highlighting, folding, line numbers
#   FlatLaf          - modern light/dark Swing look-and-feel
#   Swing            - everything else
#
# Code runs in the same JRuby runtime as the page REPL, in TOPLEVEL_BINDING, so methods,
# classes and variables defined here are visible there and vice versa.
# Open with http://localhost:8017/?app=ide, or run `RubyIDE.open` in the REPL.

require 'stringio'

module RubyIDE
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JButton
  java_import javax.swing.JToggleButton
  java_import javax.swing.JComboBox
  java_import javax.swing.JLabel
  java_import javax.swing.JSplitPane
  java_import javax.swing.JScrollPane
  java_import javax.swing.JTextPane
  java_import javax.swing.JToolBar
  java_import javax.swing.KeyStroke
  java_import javax.swing.SwingUtilities
  java_import javax.swing.BorderFactory
  java_import javax.swing.text.StyleConstants
  java_import java.awt.BorderLayout
  java_import java.awt.Color
  java_import java.awt.Font
  java_import java.awt.Toolkit
  java_import org.fife.ui.rsyntaxtextarea.RSyntaxTextArea
  java_import org.fife.ui.rsyntaxtextarea.SyntaxConstants
  java_import org.fife.ui.rsyntaxtextarea.Theme
  java_import org.fife.ui.rtextarea.RTextScrollPane

  EXAMPLES = {
    'Hello, Ruby' => <<~'RUBY',
      # Ctrl+Enter (or the Run button) runs the whole editor.
      name = 'JRuby'
      puts "Hello from #{name} #{JRUBY_VERSION}, Ruby #{RUBY_VERSION}!"
      puts "Running on #{java.lang.System.getProperty('java.vm.name')} inside your browser."

      3.times { |i| puts "#{i + 1}. #{'Ruby ' * (i + 1)}" }
    RUBY
    'Classes and blocks' => <<~'RUBY',
      class Animal
        attr_reader :name
        def initialize(name) = @name = name
        def to_s = "#{self.class.name.downcase} #{name}"
        def <=>(other) = name <=> other.name
        include Comparable
      end

      class Dog < Animal
        def speak = "#{name} says Woof"
      end

      pets = [Dog.new('Rex'), Dog.new('Bello'), Animal.new('Nemo')]
      puts pets.sort.map(&:to_s)
      puts pets.grep(Dog).map(&:speak)
      p pets.group_by(&:class).transform_values(&:size)
      pets.max
    RUBY
    'Java collections from Ruby' => <<~'RUBY',
      words = java.util.TreeMap.new
      'the quick brown fox jumps over the lazy dog the end'.split.each do |w|
        words.put(w, (words.get(w) || 0) + 1)
      end
      puts words                        # a Java TreeMap, sorted by key
      puts words.max_by { |_, n| n }.inspect  # ...used with Ruby's Enumerable

      list = java.util.ArrayList.new((1..10).to_a)
      evens = list.stream.filter { |n| n.even? }.map { |n| n * n }.toArray
      p evens.to_a
    RUBY
    'Open a Swing window' => <<~'RUBY',
      frame = javax.swing.JFrame.new('Made in the IDE')
      clicks = 0
      button = javax.swing.JButton.new('Click me')
      button.add_action_listener { clicks += 1; button.text = "Clicked #{clicks}x" }
      frame.add(button)
      frame.set_size(260, 120)
      frame.set_location(120, 120)
      frame.visible = true
      'look for the new window'
    RUBY
    'Processing sketch' => <<~'RUBY',
      java_import 'processing.core.PApplet'

      class Spiral < PApplet
        def settings = size(360, 300)
        def setup = background(20)
        def draw
          t = frameCount * 0.08
          r = (frameCount % 200)
          fill(frameCount % 255, 140, 230, 160)
          no_stroke
          ellipse(180 + r * Math.cos(t), 150 + r * 0.7 * Math.sin(t), 10, 10)
        end
      end
      PApplet.run_sketch(['Spiral'].to_java(:string), Spiral.new)
    RUBY
    'Exceptions are shown with the line' => <<~'RUBY',
      def divide(a, b)
        a / b
      end

      puts divide(10, 2)
      puts divide(1, 0)   # the failing line and its caller are highlighted
    RUBY
  }.freeze

  # Swing must only be touched from the event dispatch thread.
  def self.ui(&blk) = SwingUtilities.invoke_later(blk)

  class IDE
    attr_reader :frame, :editor

    def initialize
      @dark = false
      com.formdev.flatlaf.FlatLightLaf.setup
      build
    end

    def build
      @editor = RSyntaxTextArea.new(20, 80)
      @editor.syntax_editing_style = SyntaxConstants::SYNTAX_STYLE_RUBY
      @editor.code_folding_enabled = true
      @editor.anti_aliasing_enabled = true
      @editor.tab_size = 2
      @editor.text = EXAMPLES.values.first
      bind_key('control ENTER') { run }
      bind_key('meta ENTER') { run }
      editor_pane = RTextScrollPane.new(@editor)

      @output = JTextPane.new
      @output.editable = false
      @styles = {}
      @segments = []   # [text, kind], so a theme switch can recolour old output
      output_pane = JScrollPane.new(@output)

      split = JSplitPane.new(JSplitPane::VERTICAL_SPLIT, editor_pane, output_pane)
      split.resize_weight = 0.62
      split.border = nil

      @status = JLabel.new('Ready. Ctrl+Enter runs the editor.')
      @status.border = BorderFactory.createEmptyBorder(4, 8, 4, 8)

      @frame = JFrame.new('Ruby IDE - JRuby in your browser')
      @frame.content_pane.add(toolbar, BorderLayout::NORTH)
      @frame.content_pane.add(split, BorderLayout::CENTER)
      @frame.content_pane.add(@status, BorderLayout::SOUTH)
      screen = Toolkit.default_toolkit.screen_size
      @frame.set_size([screen.width, 1100].min, [screen.height, 760].min)
      @frame.set_location(0, 0)
      apply_theme
      @frame.visible = true
      RubyIDE.ui { split.divider_location = 0.6 }
      @editor.request_focus_in_window
    end

    def toolbar
      bar = JToolBar.new
      bar.floatable = false
      @run_button = JButton.new('▶ Run')
      @run_button.tool_tip_text = 'Run the editor (Ctrl+Enter)'
      @run_button.add_action_listener { run }
      bar.add(@run_button)
      clear = JButton.new('Clear output')
      clear.add_action_listener { @segments.clear; @output.text = '' }
      bar.add(clear)
      bar.add_separator
      bar.add(JLabel.new('Example: '))
      examples = JComboBox.new(EXAMPLES.keys.to_java(:string))
      examples.maximum_size = examples.preferred_size
      examples.add_action_listener do
        @editor.text = EXAMPLES.fetch(examples.selected_item.to_s)
        @editor.caret_position = 0
        @editor.remove_all_line_highlights
      end
      bar.add(examples)
      bar.add_separator
      theme = JToggleButton.new('Dark mode')
      theme.add_action_listener { @dark = theme.selected?; apply_theme }
      bar.add(theme)
      bar
    end

    def bind_key(stroke, &blk)
      @editor.input_map.put(KeyStroke.get_key_stroke(stroke), stroke)
      @editor.action_map.put(stroke, Class.new(javax.swing.AbstractAction) {
        define_method(:actionPerformed) { |_e| blk.call }
      }.new)
    end

    def apply_theme
      if @dark
        com.formdev.flatlaf.FlatDarkLaf.setup
      else
        com.formdev.flatlaf.FlatLightLaf.setup
      end
      com.formdev.flatlaf.FlatLaf.updateUI
      xml = @dark ? 'dark.xml' : 'idea.xml'
      Theme.load(Theme.java_class.get_resource_as_stream("/org/fife/ui/rsyntaxtextarea/themes/#{xml}")).apply(@editor)
      @editor.font = Font.new(Font::MONOSPACED, Font::PLAIN, 14)
      @output.font = Font.new(Font::MONOSPACED, Font::PLAIN, 13)
      define_styles
      redraw_output
    end

    def define_styles
      colors = @dark ?
        { out: Color.new(220, 220, 220), err: Color.new(255, 120, 110), result: Color.new(130, 210, 140), info: Color.new(140, 140, 140) } :
        { out: Color.new(30, 30, 30), err: Color.new(190, 30, 30), result: Color.new(30, 120, 50), info: Color.new(120, 120, 120) }
      colors.each do |name, color|
        style = @output.add_style(name.to_s, nil)
        StyleConstants.set_foreground(style, color)
        @styles[name] = style
      end
    end

    def append(text, kind, record: true)
      return if text.nil? || text.empty?
      @segments << [text, kind] if record
      doc = @output.styled_document
      doc.insert_string(doc.length, text, @styles[kind])
      @output.caret_position = doc.length
    end

    def redraw_output
      @output.text = ''
      @segments.each { |text, kind| append(text, kind, record: false) }
    end

    # Runs the editor contents in a Ruby thread so the window stays responsive. Output is
    # collected in StringIO buffers and streamed into the output pane by a Swing timer.
    def run
      return if @running
      @running = true
      code = @editor.text
      @editor.remove_all_line_highlights
      @editor.highlight_current_line = true
      @run_button.enabled = false
      @status.text = 'Running...'
      append("── run #{Time.now.strftime('%H:%M:%S')} ──\n", :info)
      out, err = StringIO.new, StringIO.new
      sent = { out: 0, err: 0 }
      flush = lambda do
        { out: out, err: err }.each do |kind, io|
          s = io.string
          next if s.length == sent[kind]
          append(s[sent[kind]..], kind)
          sent[kind] = s.length
        end
      end
      timer = javax.swing.Timer.new(100) { flush.call }
      timer.start
      Thread.new do
        started = Time.now
        old_out, old_err = $stdout, $stderr
        $stdout, $stderr = out, err
        begin
          value = TOPLEVEL_BINDING.eval(code, '(editor)', 1)
          ok = true
        rescue Exception => e
          ok = false
          error = e
        ensure
          $stdout, $stderr = old_out, old_err
        end
        ms = ((Time.now - started) * 1000).round
        RubyIDE.ui do
          timer.stop
          flush.call
          if ok
            append("=> #{value.inspect}\n", :result)
            @status.text = "Ran in #{ms} ms"
          else
            show_error(error)
            @status.text = "#{error.class} after #{ms} ms"
          end
          @run_button.enabled = true
          @running = false
          @editor.request_focus_in_window
        end
      end
    end

    def show_error(e)
      # The editor's top level runs inside IDE#run, so relabel those frames as <main>.
      lines = (e.backtrace || []).select { |l| l.start_with?('(editor):') }
                                 .map { |l| l.sub(/:in `(block in )?run'\z/, ':in <main>') }
      append("#{e.class}: #{e.message}\n", :err)
      lines.first(5).each { |l| append("  from #{l}\n", :err) }
      nums = lines.map { |l| l[/\A\(editor\):(\d+)/, 1].to_i }.uniq
      return if nums.empty?
      @editor.highlight_current_line = false   # it would paint over the error highlight
      nums.each_with_index do |n, i|
        @editor.add_line_highlight(n - 1, i.zero? ? Color.new(255, 90, 90, 110) : Color.new(255, 170, 60, 70))
      end
      @editor.caret_position = @editor.get_line_start_offset(nums.first - 1)
    end
  end

  def self.open
    @ide = IDE.new
  end

  def self.ide = @ide
end

RubyIDE.open
