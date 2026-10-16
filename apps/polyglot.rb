# Polyglot: JavaScript (Mozilla Rhino, a JS engine written in Java) and Ruby in one JVM, in one
# browser tab, calling each other. Open with ?app=polyglot.
#
#   JS -> Ruby: the JS side gets print(...) and ruby("any Ruby code"), which returns the value.
#   Ruby -> JS: the Ruby side gets `js`, so js.fib(20) calls a function the JS code defined.
#
# Ruby ideas on show: subclassing a Java class (Rhino's BaseFunction) to make Ruby blocks callable
# from JS, method_missing for a dynamic bridge, recursive data conversion with case/when.

module Polyglot
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JButton
  java_import javax.swing.JLabel
  java_import javax.swing.JSplitPane
  java_import javax.swing.JScrollPane
  java_import javax.swing.JTextArea
  java_import javax.swing.BorderFactory
  java_import java.awt.BorderLayout
  java_import java.awt.Font
  java_import org.mozilla.javascript.Context
  java_import org.mozilla.javascript.ScriptableObject
  java_import org.mozilla.javascript.Scriptable
  java_import org.mozilla.javascript.NativeArray
  java_import org.mozilla.javascript.NativeObject
  java_import org.mozilla.javascript.Undefined

  JS_EXAMPLE = <<~'JS'
    // JavaScript, run by Rhino (a JS engine written in Java) inside the browser's JVM.
    function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
    function shout(s) { return s.toUpperCase() + '!'; }

    print('JS computes fib(15) = ' + fib(15));

    // Hand work to Ruby: ruby(code) evaluates Ruby and converts the result back to JS.
    var primes = ruby('(2..).lazy.select { |n| (2..Integer.sqrt(n)).none? { n % _1 == 0 } }.first(10)');
    print('Ruby gave JS an array: ' + JSON.stringify(primes) + ' (length ' + primes.length + ')');

    var stats = ruby('{ ruby: RUBY_VERSION, engine: RUBY_ENGINE, words: %w[a bb ccc].map(&:size) }');
    print('...and an object: ' + JSON.stringify(stats));

    // JS functions can take Ruby lambdas' results and keep going.
    var total = primes.reduce(function (a, b) { return a + b; }, 0);
    print('JS sums the Ruby primes: ' + total);
  JS

  RUBY_EXAMPLE = <<~'RUBY'
    # Ruby calls the functions the JS side defined (run the JS first).
    puts "js.fib(20)     => #{js.fib(20)}"
    puts "js.shout('ruby') => #{js.shout('ruby')}"
    puts "JS's Math.max  => #{js.eval('Math.max(3, 9, 4)')}"
    js.eval('[1, 2, 3].map(function (x) { return x * 10; })').sum
  RUBY

  # A Ruby block that JavaScript can call like a function.
  class RubyFunction < org.mozilla.javascript.BaseFunction
    def initialize(bridge, &blk)
      super()
      @bridge, @blk = bridge, blk
    end

    def call(cx, scope, _this, args)
      @bridge.to_js(@blk.call(*args.map { |a| @bridge.from_js(a) }))
    end
  end

  class Bridge
    attr_reader :scope

    def initialize(&printer)
      @printer = printer
      with_context do |cx|
        @scope = cx.init_standard_objects
        ScriptableObject.put_property(@scope, 'print', RubyFunction.new(self) { |*a| @printer.call(a.join(' ')); nil })
        ScriptableObject.put_property(@scope, 'ruby', RubyFunction.new(self) { |code| TOPLEVEL_BINDING.eval(code.to_s, '(from JS)', 1) })
      end
    end

    # Rhino needs a Context bound to the current thread. Interpreted mode: no bytecode generation.
    def with_context
      cx = Context.enter
      cx.optimization_level = -1
      yield cx
    ensure
      Context.exit
    end

    def eval(source, name = '(js)')
      with_context { |cx| from_js(cx.evaluate_string(@scope, source, name, 1, nil)) }
    end

    def call(name, *args)
      with_context do |cx|
        fn = ScriptableObject.get_property(@scope, name.to_s)
        raise NoMethodError, "no JS function #{name}() (run the JS first?)" unless fn.is_a?(org.mozilla.javascript.Function)
        from_js(fn.call(cx, @scope, @scope, args.map { |a| to_js(a) }.to_java))
      end
    end

    def from_js(v)
      case v
      when nil, Undefined then nil
      when NativeArray then v.to_a.map { |x| from_js(x) }
      when NativeObject then v.ids.to_a.to_h { |k| [k.to_s, from_js(v.get(k.to_s, v))] }
      when Float, Java::JavaLang::Double then v.to_f == v.to_f.floor && v.to_f.abs < 2**53 ? v.to_i : v.to_f
      when Numeric then v
      when true, false then v
      else v.to_s   # JS strings (String or ConsString)
      end
    end

    def to_js(v)
      cx = Context.current_context
      case v
      when nil then nil
      when Array then cx.new_array(@scope, v.map { |x| to_js(x) }.to_java)
      when Hash
        obj = cx.new_object(@scope)
        v.each { |k, x| ScriptableObject.put_property(obj, k.to_s, to_js(x)) }
        obj
      when Integer, Float then v.to_f
      when true, false then v
      else v.to_s
      end
    end
  end

  # `js` on the Ruby side: js.fib(20) calls the JS function fib; js.eval('...') runs JS.
  class JS
    def initialize(bridge) = @bridge = bridge
    def eval(src) = @bridge.eval(src)
    def method_missing(name, *args) = @bridge.call(name, *args)
    def respond_to_missing?(*) = true
  end

  class App
    attr_reader :frame, :bridge

    def initialize
      begin
        com.formdev.flatlaf.FlatLightLaf.setup
      rescue NameError
        nil
      end
      @output = JTextArea.new
      @output.editable = false
      @output.font = Font.new(Font::MONOSPACED, Font::PLAIN, 13)
      @bridge = Bridge.new { |line| say(line) }
      Object.const_set(:POLYGLOT_JS, JS.new(@bridge)) unless defined?(::POLYGLOT_JS)
      Object.send(:define_method, :js) { ::POLYGLOT_JS } unless Object.private_method_defined?(:js) || Object.method_defined?(:js)

      @js_editor = editor('text/javascript', JS_EXAMPLE)
      @rb_editor = editor('text/ruby', RUBY_EXAMPLE)
      run_js = JButton.new('▶ Run JavaScript')
      run_js.add_action_listener { run(:js) }
      run_rb = JButton.new('▶ Run Ruby')
      run_rb.add_action_listener { run(:ruby) }

      left = panel('JavaScript (Rhino)', @js_editor, run_js)
      right = panel('Ruby (JRuby)', @rb_editor, run_rb)
      editors = JSplitPane.new(JSplitPane::HORIZONTAL_SPLIT, left, right)
      editors.resize_weight = 0.55
      out = JScrollPane.new(@output)
      out.border = BorderFactory.createTitledBorder('Output')
      main = JSplitPane.new(JSplitPane::VERTICAL_SPLIT, editors, out)
      main.resize_weight = 0.65

      @frame = JFrame.new('Polyglot - JavaScript and Ruby calling each other')
      @frame.add(main)
      @frame.set_size(1100, 720)
      @frame.set_location(0, 0)
      @frame.visible = true
    end

    # RSyntaxTextArea on the classpath? (`defined?` can't tell: JRuby resolves Java classes lazily.)
    def rsyntax?
      return @rsyntax unless @rsyntax.nil?
      @rsyntax = begin
        Java::OrgFifeUiRsyntaxtextarea::RSyntaxTextArea
        true
      rescue NameError
        false
      end
    end

    def editor(style, text)
      if rsyntax?
        ed = Java::OrgFifeUiRsyntaxtextarea::RSyntaxTextArea.new(14, 50)
        ed.syntax_editing_style = style
        ed.code_folding_enabled = true
      else
        ed = JTextArea.new(14, 50)
      end
      ed.font = Font.new(Font::MONOSPACED, Font::PLAIN, 13)
      ed.text = text
      ed.caret_position = 0
      ed
    end

    def panel(title, ed, button)
      p = JPanel.new(BorderLayout.new)
      pane = rsyntax? ? Java::OrgFifeUiRtextarea::RTextScrollPane.new(ed) : JScrollPane.new(ed)
      p.add(JLabel.new("  #{title}"), BorderLayout::NORTH)
      p.add(pane, BorderLayout::CENTER)
      p.add(button, BorderLayout::SOUTH)
      p
    end

    def say(line)
      @output.append("#{line}\n")
      @output.caret_position = @output.document.length
    end

    def run(lang)
      if lang == :js
        say('── JavaScript ──')
        value = @bridge.eval(@js_editor.text, '(editor.js)')
      else
        say('── Ruby ──')
        out = StringIO.new
        old, $stdout = $stdout, out
        begin
          value = TOPLEVEL_BINDING.eval(@rb_editor.text, '(editor.rb)', 1)
        ensure
          $stdout = old
        end
        out.string.each_line { |l| say(l.chomp) }
      end
      say("=> #{value.inspect}") unless value.nil?
    rescue Exception => e
      say("#{e.class}: #{e.message}")
    end
  end

  def self.open = @app = App.new
  def self.app = @app
end

require 'stringio'
Polyglot.open
