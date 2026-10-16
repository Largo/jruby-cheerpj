# Quadratic Solver: Ruby does the maths (exact Rationals, Complex roots), JLaTeXMath (Java)
# typesets it, Java2D plots the parabola. Open with ?app=formula.
#
# Ruby ideas on show: Rational and Complex numbers, Integer.sqrt, string building for LaTeX,
# a JPanel subclass that paints, spinners driven by blocks.

module Formula
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JLabel
  java_import javax.swing.JSpinner
  java_import javax.swing.SpinnerNumberModel
  java_import javax.swing.BorderFactory
  java_import javax.swing.BoxLayout
  java_import java.awt.BorderLayout
  java_import java.awt.FlowLayout
  java_import java.awt.Color
  java_import java.awt.BasicStroke
  java_import java.awt.Font
  java_import java.awt.RenderingHints
  java_import org.scilab.forge.jlatexmath.TeXFormula
  java_import org.scilab.forge.jlatexmath.TeXConstants

  # Solves a*x^2 + b*x + c = 0 for integer coefficients, exactly where possible.
  class Quadratic
    attr_reader :a, :b, :c

    def initialize(a, b, c) = (@a, @b, @c = a, b, c)
    def discriminant = b * b - 4 * a * c

    def roots
      return (c.zero? ? :all : :none) if a.zero? && b.zero?
      return [Rational(-c, b)] if a.zero?
      d = discriminant
      if d >= 0
        s = Integer.sqrt(d)
        root = s * s == d ? s : Math.sqrt(d)            # exact when d is a perfect square
        [(-b + root) / (2r * a), (-b - root) / (2r * a)].uniq
      else
        im = Math.sqrt(-d) / (2.0 * a)
        [Complex(Rational(-b, 2 * a), im), Complex(Rational(-b, 2 * a), -im)]
      end
    end

    def value_at(x) = a * x * x + b * x + c

    # --- LaTeX ---------------------------------------------------------------------------------
    def self.num(x)
      case x
      when Rational then x.denominator == 1 ? x.numerator.to_s : "#{'-' if x.negative?}\\frac{#{x.numerator.abs}}{#{x.denominator}}"
      when Float then format('%.4g', x)
      when Complex
        re, im = num(x.real), num(x.imaginary.abs)
        "#{re} #{x.imaginary.negative? ? '-' : '+'} #{im}\\,i"
      else x.to_s
      end
    end

    def paren(x) = x.negative? ? "(#{x})" : x.to_s   # parenthesise negatives when substituting

    # "x^2 - x - 6", not "1x^2 - 1x - 6": drop zero terms and coefficients of 1.
    def polynomial
      terms = [[a, 'x^2'], [b, 'x'], [c, '']].reject { |k, _| k.zero? }
      return '0' if terms.empty?
      terms.each_with_index.map do |(k, x), i|
        sign = k.negative? ? '-' : (i.zero? ? '' : '+')
        mag = k.abs == 1 && !x.empty? ? '' : k.abs.to_s
        "#{sign} #{mag}#{x}".strip
      end.join(' ')
    end

    def latex
      eq = "#{polynomial} = 0"
      return "\\text{Not quadratic: } #{eq}" if a.zero?
      sub = "x = \\frac{-#{paren(b)} \\pm \\sqrt{#{paren(b)}^2 - 4 \\cdot #{paren(a)} \\cdot #{paren(c)}}}{2 \\cdot #{paren(a)}}"
      d = discriminant
      rs = roots.each_with_index.map { |r, i| "x_{#{i + 1}} = #{Quadratic.num(r)}" }.join(',\\quad ')
      kind = d.positive? ? 'two real roots' : d.zero? ? 'one double root' : 'two complex roots'
      rows = [eq, 'x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}', sub, "\\Delta = #{d} \\Rightarrow \\text{#{kind}}", rs]
      "\\begin{array}{l} #{rows.join(' \\\\ \\vspace{8pt} \\\\ ')} \\end{array}"
    end
  end

  # Plots the parabola and marks the real roots. Paints itself: JRuby can't call `super` on the
  # protected JPanel#paintComponent, so it clears the background by hand.
  class Plot < JPanel
    attr_accessor :quadratic

    def paintComponent(g)
      w, h = width, height
      g.set_rendering_hint(RenderingHints::KEY_ANTIALIASING, RenderingHints::VALUE_ANTIALIAS_ON)
      g.color = Color::WHITE
      g.fill_rect(0, 0, w, h)
      return unless quadratic
      scale = 28.0
      ox, oy = w / 2, h / 2
      g.color = Color.new(225, 225, 225)
      (-12..12).each do |i|
        gx, gy = (ox + i * scale).to_i, (oy + i * scale).to_i
        g.draw_line(gx, 0, gx, h)
        g.draw_line(0, gy, w, gy)
      end
      g.color = Color.new(120, 120, 120)
      g.draw_line(0, oy, w, oy)
      g.draw_line(ox, 0, ox, h)
      g.color = Color.new(178, 34, 34)
      g.setStroke(BasicStroke.new(2.5))   # not g.stroke=: JRuby would pick SunGraphics2D's public field
      pts = (0..w).step(3).map { |px| x = (px - ox) / scale; [px, (oy - quadratic.value_at(x) * scale).clamp(-1000, 3000).to_i] }
      pts.each_cons(2) { |(x1, y1), (x2, y2)| g.draw_line(x1, y1, x2, y2) }
      g.color = Color.new(20, 90, 200)
      roots = quadratic.roots
      Array(roots).grep(Numeric).reject { |r| r.is_a?(Complex) }.each do |r|
        g.fill_oval((ox + r * scale - 6).to_i, oy - 6, 12, 12)
      end
    end
  end

  class Solver
    attr_reader :frame

    def initialize
      begin
        com.formdev.flatlaf.FlatLightLaf.setup
      rescue NameError
        nil
      end
      @spinners = { a: 1, b: -1, c: -6 }.to_h do |k, v|
        s = JSpinner.new(SpinnerNumberModel.new(v, -20, 20, 1))
        s.font = Font.new(Font::SANS_SERIF, Font::PLAIN, 18)
        s.add_change_listener { update }
        [k, s]
      end
      inputs = JPanel.new(FlowLayout.new(FlowLayout::LEFT, 10, 8))
      inputs.add(JLabel.new('Solve  a·x² + b·x + c = 0   with'))
      @spinners.each { |k, s| inputs.add(JLabel.new("#{k} =")); inputs.add(s) }

      @tex = JLabel.new
      @tex.border = BorderFactory.createEmptyBorder(10, 16, 10, 16)
      @plot = Plot.new
      @plot.preferred_size = java.awt.Dimension.new(360, 360)

      center = JPanel.new(BorderLayout.new)
      center.add(@tex, BorderLayout::CENTER)
      center.add(@plot, BorderLayout::EAST)

      @frame = JFrame.new('Quadratic Solver - JLaTeXMath from Ruby')
      @frame.add(inputs, BorderLayout::NORTH)
      @frame.add(center, BorderLayout::CENTER)
      @frame.set_size(1000, 520)
      @frame.set_location(10, 10)
      update
      @frame.visible = true
    end

    def coefficients = @spinners.transform_values { |s| s.value.to_i }

    def update
      q = Quadratic.new(*coefficients.values_at(:a, :b, :c))
      @tex.icon = TeXFormula.new(q.latex).createTeXIcon(TeXConstants::STYLE_DISPLAY, 22)
      @plot.quadratic = q
      @plot.repaint
      @quadratic = q
    end

    def quadratic = @quadratic
  end

  def self.open = @solver = Solver.new
  def self.solver = @solver
end

Formula.open
