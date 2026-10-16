# Law of Large Numbers: roll two dice with Ruby, chart the sums with JFreeChart (Java).
# Open with ?app=dice. The bars drift towards the expected triangle as you roll more.
#
# Ruby ideas on show: Array.new with a block, tally, Hash#transform_values, Rational for exact
# probabilities, a Swing Timer driven by a block.

module Dice
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JButton
  java_import javax.swing.JToggleButton
  java_import javax.swing.JLabel
  java_import javax.swing.BorderFactory
  java_import java.awt.BorderLayout
  java_import java.awt.FlowLayout
  java_import java.awt.Color
  java_import java.awt.BasicStroke
  java_import java.awt.Font
  java_import org.jfree.chart.ChartFactory
  java_import org.jfree.chart.ChartPanel
  java_import org.jfree.chart.plot.PlotOrientation
  java_import org.jfree.chart.renderer.category.LineAndShapeRenderer
  java_import org.jfree.chart.renderer.category.BarRenderer
  java_import org.jfree.chart.renderer.category.StandardBarPainter
  java_import org.jfree.data.category.DefaultCategoryDataset

  SUMS = (2..12).to_a.freeze
  # P(sum) for two fair dice, exactly: 1/36, 2/36, ... 6/36 ... 1/36
  EXPECTED = SUMS.to_h { |s| [s, Rational(6 - (s - 7).abs, 36)] }.freeze

  class Roller
    attr_reader :frame, :counts

    def initialize
      begin
        com.formdev.flatlaf.FlatLightLaf.setup
      rescue NameError
        nil
      end
      @counts = SUMS.to_h { |s| [s, 0] }
      @observed = DefaultCategoryDataset.new
      @expected = DefaultCategoryDataset.new

      chart = ChartFactory.create_bar_chart('Sum of two dice', 'sum', 'share of rolls (%)',
                                            @observed, PlotOrientation::VERTICAL, true, true, false)
      plot = chart.category_plot
      plot.background_paint = Color::WHITE
      plot.range_gridline_paint = Color.new(210, 210, 210)
      bars = plot.renderer
      bars.bar_painter = StandardBarPainter.new
      bars.shadow_visible = false
      bars.set_series_paint(0, Color.new(178, 34, 34))
      plot.set_dataset(1, @expected)
      line = LineAndShapeRenderer.new(true, true)
      line.set_series_paint(0, Color.new(30, 30, 30))
      line.set_series_stroke(0, BasicStroke.new(2.5))
      plot.set_renderer(1, line)
      plot.dataset_rendering_order = org.jfree.chart.plot.DatasetRenderingOrder::FORWARD   # line on top of the bars
      plot.range_axis.upper_bound = 20
      @chart = chart

      @status = JLabel.new
      @status.font = Font.new(Font::MONOSPACED, Font::PLAIN, 13)
      buttons = JPanel.new(FlowLayout.new(FlowLayout::LEFT))
      [1, 10, 100, 1000].each do |n|
        b = JButton.new("Roll #{n}")
        b.add_action_listener { roll(n) }
        buttons.add(b)
      end
      auto = JToggleButton.new('Auto-roll')
      @timer = javax.swing.Timer.new(120) { roll(25) }
      auto.add_action_listener { auto.selected? ? @timer.start : @timer.stop }
      buttons.add(auto)
      reset = JButton.new('Reset')
      reset.add_action_listener { @counts.transform_values! { 0 }; redraw }
      buttons.add(reset)

      south = JPanel.new(BorderLayout.new)
      south.add(buttons, BorderLayout::NORTH)
      south.add(@status, BorderLayout::SOUTH)
      south.border = BorderFactory.createEmptyBorder(4, 8, 8, 8)

      @frame = JFrame.new('Law of Large Numbers - JFreeChart from Ruby')
      @frame.add(ChartPanel.new(chart), BorderLayout::CENTER)
      @frame.add(south, BorderLayout::SOUTH)
      @frame.set_size(820, 600)
      @frame.set_location(20, 10)
      redraw
      @frame.visible = true
    end

    def roll(n)
      Array.new(n) { rand(1..6) + rand(1..6) }.tally.each { |sum, k| @counts[sum] += k }
      redraw
    end

    def total = @counts.values.sum

    def redraw
      n = total
      @observed.notify = false
      SUMS.each do |s|
        share = n.zero? ? 0 : 100.0 * @counts[s] / n
        @observed.set_value(share, 'your rolls', s.to_s)
        @expected.set_value(EXPECTED[s] * 100.0, 'expected (exact)', s.to_s)
      end
      @observed.notify = true
      return @status.text = "Roll the dice! The black line is the exact probability, P(7) = #{EXPECTED[7]}." if n.zero?
      worst = SUMS.map { |s| ((n.zero? ? 0 : @counts[s].fdiv(n)) - EXPECTED[s]).abs }.max * 100
      @status.text = format('%d rolls   biggest gap to the exact probability: %.2f percentage points   P(7) = %s',
                            n, worst, EXPECTED[7])
    end
  end

  def self.open = @roller = Roller.new
  def self.roller = @roller
end

Dice.open
