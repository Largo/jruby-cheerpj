# SQL Playground: an H2 database (Java, in memory) queried with Sequel (Ruby) or plain SQL.
# Open with ?app=sql. The same DB constant is available in the page REPL.
#
# Ruby ideas on show: Sequel's dataset DSL (it shows you the SQL it generates), hashes as rows,
# Enumerable on query results, JDBC under the hood.

require 'sequel-cheerpj'

module SqlPlayground
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JButton
  java_import javax.swing.JRadioButton
  java_import javax.swing.ButtonGroup
  java_import javax.swing.JComboBox
  java_import javax.swing.JLabel
  java_import javax.swing.JTable
  java_import javax.swing.JScrollPane
  java_import javax.swing.JSplitPane
  java_import javax.swing.JTextArea
  java_import javax.swing.KeyStroke
  java_import javax.swing.BorderFactory
  java_import javax.swing.table.DefaultTableModel
  java_import java.awt.BorderLayout
  java_import java.awt.FlowLayout
  java_import java.awt.Font
  java_import java.awt.Color

  CITIES = [   # approximate 2023 figures
    ['Zürich', 'ZH', 427_000, 87.9], ['Genève', 'GE', 203_000, 15.9], ['Basel', 'BS', 173_000, 23.9],
    ['Lausanne', 'VD', 140_000, 41.4], ['Bern', 'BE', 134_000, 51.6], ['Winterthur', 'ZH', 117_000, 68.0],
    ['Luzern', 'LU', 82_000, 37.4], ['St. Gallen', 'SG', 76_000, 39.4], ['Lugano', 'TI', 63_000, 75.9],
    ['Biel/Bienne', 'BE', 55_000, 21.2], ['Neuchâtel', 'NE', 45_000, 30.0], ['Thun', 'BE', 44_000, 21.6],
    ['Fribourg', 'FR', 38_000, 9.3], ['Bellinzona', 'TI', 44_000, 164.9],
  ].freeze
  CANTONS = [
    %w[ZH Zürich German], %w[GE Genève French], %w[BS Basel-Stadt German], %w[VD Vaud French],
    %w[BE Bern German], %w[LU Luzern German], %w[SG St.\ Gallen German], %w[TI Ticino Italian],
    %w[NE Neuchâtel French], %w[FR Fribourg French], %w[GR Graubünden German],
  ].freeze

  EXAMPLES = {
    ruby: {
      'Biggest cities' => "DB[:cities].order(Sequel.desc(:population)).limit(5)",
      'Join with cantons' => <<~RUBY.chomp,
        DB[:cities]
          .join(:cantons, code: :canton)
          .select(Sequel[:cities][:name], Sequel[:cantons][:name].as(:canton_name), :language)
          .order(:language, Sequel[:cities][:name])
      RUBY
      'Group and count' => "DB[:cities].join(:cantons, code: :canton).group_and_count(:language).order(Sequel.desc(:count))",
      'Insert, then query' => <<~RUBY.chomp,
        DB[:cities].insert(name: 'Chur', canton: 'GR', population: 38_000, area_km2: 54.2) unless DB[:cities][name: 'Chur']
        DB[:cities].where(canton: %w[GR TI])
      RUBY
      'Ruby on the results' => <<~RUBY.chomp,
        # The database returns rows as Ruby hashes; Enumerable does the rest.
        DB[:cities].map { |c| { city: c[:name], people_per_km2: (c[:population] / c[:area_km2]).round } }
                   .sort_by { -_1[:people_per_km2] }
      RUBY
      'Aggregate in one line' => "{ cities: DB[:cities].count, people: DB[:cities].sum(:population), avg_km2: DB[:cities].avg(:area_km2).round(1) }",
    },
    sql: {
      'All cities' => 'SELECT * FROM cities ORDER BY population DESC',
      'People per language' => <<~SQL.chomp,
        SELECT c.language, COUNT(*) AS cities, SUM(population) AS people
        FROM cities JOIN cantons c ON c.code = cities.canton
        GROUP BY c.language
        ORDER BY people DESC
      SQL
      'Density' => 'SELECT name, ROUND(population / area_km2) AS density FROM cities ORDER BY density DESC',
      'Window function' => <<~SQL.chomp,
        SELECT name, canton, population,
               RANK() OVER (PARTITION BY canton ORDER BY population DESC) AS rank_in_canton
        FROM cities ORDER BY canton, rank_in_canton
      SQL
    },
  }.freeze

  def self.connect
    db = Sequel.connect('jdbc:h2:mem:playground', driver: Java::OrgH2::Driver)
    db.create_table?(:cantons) { String :code, primary_key: true; String :name; String :language }
    db.create_table?(:cities) do
      primary_key :id
      String :name
      String :canton
      Integer :population
      Float :area_km2
    end
    if db[:cities].empty?
      db[:cantons].import(%i[code name language], CANTONS)
      db[:cities].import(%i[name canton population area_km2], CITIES)
    end
    db
  end

  class Playground
    attr_reader :frame, :editor, :table

    def initialize(db)
      @db = db
      begin
        com.formdev.flatlaf.FlatLightLaf.setup
      rescue NameError
        nil
      end
      @mode = :ruby
      @editor = make_editor
      ruby_btn = JRadioButton.new('Sequel (Ruby)', true)
      sql_btn = JRadioButton.new('SQL')
      ButtonGroup.new.tap { |g| g.add(ruby_btn); g.add(sql_btn) }
      @examples = JComboBox.new
      ruby_btn.add_action_listener { switch(:ruby) }
      sql_btn.add_action_listener { switch(:sql) }
      @examples.add_action_listener { load_example }
      run = JButton.new('▶ Run')
      run.add_action_listener { self.run }

      top = JPanel.new(FlowLayout.new(FlowLayout::LEFT))
      [ruby_btn, sql_btn, JLabel.new('   Example:'), @examples, run, JLabel.new('  (Ctrl+Enter)')].each { |c| top.add(c) }

      @table = JTable.new
      @table.auto_create_row_sorter = true
      @message = JTextArea.new(2, 80)
      @message.editable = false
      @message.line_wrap = true
      @message.font = Font.new(Font::MONOSPACED, Font::PLAIN, 12)
      @message.border = BorderFactory.createEmptyBorder(6, 8, 6, 8)

      results = JPanel.new(BorderLayout.new)
      results.add(@message, BorderLayout::NORTH)
      results.add(JScrollPane.new(@table), BorderLayout::CENTER)
      split = JSplitPane.new(JSplitPane::VERTICAL_SPLIT, editor_pane, results)
      split.resize_weight = 0.4

      @frame = JFrame.new('SQL Playground - H2 (Java) + Sequel (Ruby)')
      @frame.add(top, BorderLayout::NORTH)
      @frame.add(split, BorderLayout::CENTER)
      @frame.set_size(1000, 720)
      @frame.set_location(10, 10)
      switch(:ruby)
      @frame.visible = true
      javax.swing.SwingUtilities.invoke_later { split.divider_location = 0.38 }
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

    def make_editor
      if rsyntax?
        ed = Java::OrgFifeUiRsyntaxtextarea::RSyntaxTextArea.new(8, 80)
        ed.code_folding_enabled = true
        @editor_pane = Java::OrgFifeUiRtextarea::RTextScrollPane.new(ed)
      else
        ed = JTextArea.new(8, 80)
        @editor_pane = JScrollPane.new(ed)
      end
      ed.font = Font.new(Font::MONOSPACED, Font::PLAIN, 14)
      ed.input_map.put(KeyStroke.get_key_stroke('control ENTER'), 'run-query')
      owner = self
      ed.action_map.put('run-query', Class.new(javax.swing.AbstractAction) {
        define_method(:actionPerformed) { |_e| owner.run }
      }.new)
      ed
    end

    def editor_pane = @editor_pane

    def switch(mode)
      @mode = mode
      if @editor.respond_to?(:syntax_editing_style=)
        style = mode == :ruby ? 'text/ruby' : 'text/sql'
        @editor.syntax_editing_style = style
      end
      @examples.remove_all_items
      EXAMPLES.fetch(mode).each_key { |k| @examples.add_item(k) }
      load_example
    end

    def load_example
      name = @examples.selected_item or return
      @editor.text = EXAMPLES.fetch(@mode).fetch(name.to_s)
      @editor.caret_position = 0
    end

    def run
      # Swing models must change on the event thread (the REPL may call this from elsewhere).
      return javax.swing.SwingUtilities.invoke_and_wait { run } unless javax.swing.SwingUtilities.event_dispatch_thread?
      started = Time.now
      code = @editor.text
      value, sql = @mode == :ruby ? run_ruby(code) : run_sql(code)
      rows = rows_of(value)
      show(rows)
      ms = ((Time.now - started) * 1000).round
      note = sql ? "SQL: #{sql}" : (rows ? '' : "=> #{value.inspect}")
      @message.foreground = Color.new(40, 40, 40)
      @message.text = "#{rows ? rows.size : 0} row(s) in #{ms} ms   #{note}".strip
    rescue Exception => e
      show([])
      @message.foreground = Color.new(180, 30, 30)
      @message.text = "#{e.class}: #{e.message}"
    end

    def run_ruby(code)
      value = TOPLEVEL_BINDING.eval(code, '(query)', 1)
      value.is_a?(Sequel::Dataset) ? [value.all, value.sql] : [value, nil]
    end

    def run_sql(code)
      if code =~ /\A\s*(select|with|values|show|explain)\b/i
        [@db.fetch(code).all, nil]
      else
        @db.run(code)
        [[{ ok: 'statement executed' }], nil]
      end
    end

    def rows_of(value)
      case value
      when Array then value.all?(Hash) ? value : value.map { |v| { value: v } }
      when Hash then [value]
      end
    end

    def show(rows)
      model = DefaultTableModel.new
      cols = rows.flat_map(&:keys).uniq
      cols.each { |c| model.add_column(c.to_s) }
      rows.each { |r| model.add_row(cols.map { |c| cell(r[c]) }.to_java) }
      @table.model = model
    end

    def cell(v)
      case v
      when nil, String, Integer, Float, true, false then v
      when BigDecimal then v.to_f
      else v.to_s
      end
    end
  end

  def self.open
    Object.const_set(:DB, connect) unless defined?(::DB)
    @playground = Playground.new(::DB)
  end

  def self.playground = @playground
end

SqlPlayground.open
