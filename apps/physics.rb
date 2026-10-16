# Physics Tower: dyn4j (a Java 2D physics engine) simulates, Ruby builds the world and draws it
# with Java2D. Open with ?app=physics. Click anywhere to fire a ball at that point.
#
# Ruby ideas on show: building a world from loops, a Ruby class extending a Java class
# (MouseAdapter, JPanel), case/when on Java classes, a Swing Timer as the game loop.

module Physics
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JButton
  java_import javax.swing.JLabel
  java_import javax.swing.JSlider
  java_import java.awt.BorderLayout
  java_import java.awt.FlowLayout
  java_import java.awt.Color
  java_import java.awt.RenderingHints
  java_import java.awt.BasicStroke
  java_import org.dyn4j.world.World
  java_import org.dyn4j.dynamics.Body
  java_import org.dyn4j.geometry.Geometry
  java_import org.dyn4j.geometry.MassType
  java_import org.dyn4j.geometry.Vector2
  java_import org.dyn4j.geometry.Rectangle
  java_import org.dyn4j.geometry.Circle

  SCALE = 32.0          # pixels per metre
  CANNON = [1.5, 1.5]   # metres

  class Sim
    attr_reader :world, :balls

    def initialize = reset

    def reset(gravity: 9.8)
      @world = World.new
      @world.set_gravity(0, -gravity)
      @balls = []
      add_box(15, -0.5, 40, 1, mass: :infinite, colour: Color.new(90, 90, 90))   # ground
      # A pyramid of crates: Ruby loops make the level.
      6.downto(1).each_with_index do |count, row|
        count.times do |i|
          add_box(17 + i * 1.05 + row * 0.52, 0.5 + row * 1.0, 1, 1, colour: Color.getHSBColor(row / 7.0, 0.55, 0.95))
        end
      end
    end

    def add_box(x, y, w, h, mass: :normal, colour: Color::GRAY)
      body = Body.new
      fixture = body.add_fixture(Geometry.create_rectangle(w, h))
      fixture.density = 1.0
      fixture.friction = 0.6
      body.set_mass(mass == :infinite ? MassType::INFINITE : MassType::NORMAL)
      body.translate(x, y)
      body.user_data = colour
      @world.add_body(body)
      body
    end

    def fire(tx, ty, speed:, bounce:)
      body = Body.new
      fixture = body.add_fixture(Geometry.create_circle(0.35))
      fixture.density = 4.0
      fixture.restitution = bounce
      body.set_mass(MassType::NORMAL)
      body.translate(*CANNON)
      dx, dy = tx - CANNON[0], ty - CANNON[1]
      len = Math.hypot(dx, dy).nonzero? || 1
      body.set_linear_velocity(Vector2.new(dx / len * speed, dy / len * speed))
      body.user_data = Color.new(30, 30, 30)
      @world.add_body(body)
      @balls << body
      @balls.shift.tap { |old| @world.remove_body(old) } if @balls.size > 12
    end

    # Advance by real elapsed time, so the simulation keeps real-time speed even when drawing
    # (Ruby, interpreted) runs at fewer frames per second. dyn4j takes fixed 1/60 s substeps.
    def step(seconds)
      @pending = (@pending || 0.0) + [seconds, 0.1].min
      n = (@pending * 60).floor
      return if n.zero?
      @pending -= n / 60.0
      @world.step(n)
    end
    def bodies = @world.bodies
  end

  # Draws the world (no antialiasing: Java2D's software antialiasing is slow under CheerpJ).
  # Paints the background itself: JRuby can't `super` into the protected
  # JPanel#paintComponent. Uses setColor/setStroke rather than color=/stroke=, which JRuby would
  # resolve to SunGraphics2D's public fields.
  class View < JPanel
    attr_accessor :sim, :aim

    def to_screen(x, y) = [x * SCALE + 20, height - 30 - y * SCALE]
    def to_world(px, py) = [(px - 20) / SCALE, (height - 30 - py) / SCALE]

    # Shape facts never change, so look them up once per body (Java calls are what cost time
    # in the interpreter). Returns [:box, w, h, colour] or [:ball, r, colour].
    def look(body)
      (@looks ||= {})[body] ||= begin
        shape = body.get_fixture(0).shape
        colour = body.user_data || Color::GRAY
        case shape
        when Rectangle then [:box, (shape.width * SCALE).round, (shape.height * SCALE).round, colour]
        when Circle then [:ball, (shape.radius * SCALE).round, colour]
        end
      end
    end

    def paintComponent(g)
      g.setColor(Color.new(235, 244, 252))
      g.fill_rect(0, 0, width, height)
      return unless sim
      base = g.getTransform   # not g.transform: that is Graphics2D#transform(AffineTransform)
      edge = Color.new(0, 0, 0, 60)
      sim.bodies.each do |body|
        t = body.transform
        px, py = to_screen(t.translation_x, t.translation_y)
        kind, a, b, colour = look(body)
        g.translate(px, py)
        g.rotate(-t.rotation_angle)
        if kind == :box
          g.setColor(colour)
          g.fill_rect(-a / 2, -b / 2, a, b)
          g.setColor(edge)
          g.draw_rect(-a / 2, -b / 2, a, b)
        else
          g.setColor(b)
          g.fill_oval(-a, -a, 2 * a, 2 * a)
        end
        g.setTransform(base)
      end
      cx, cy = to_screen(*CANNON).map(&:round)
      g.setColor(Color.new(178, 34, 34))
      g.fill_oval(cx - 12, cy - 12, 24, 24)
      if aim
        g.setStroke(BasicStroke.new(1.5, BasicStroke::CAP_ROUND, BasicStroke::JOIN_ROUND, 1, [6.0, 6.0].to_java(:float), 0))
        g.draw_line(cx, cy, *aim)
      end
    end
  end

  class Mouse < java.awt.event.MouseAdapter
    def initialize(game) = (super(); @game = game)
    def mousePressed(e) = @game.fire_at(e.x, e.y)
    def mouseMoved(e) = @game.aim_at(e.x, e.y)
  end

  class Game
    attr_reader :frame, :sim, :view, :fps

    def initialize
      begin
        com.formdev.flatlaf.FlatLightLaf.setup
      rescue NameError
        nil
      end
      @sim = Sim.new
      @view = View.new
      @view.sim = @sim
      mouse = Mouse.new(self)
      @view.add_mouse_listener(mouse)
      @view.add_mouse_motion_listener(mouse)

      @gravity = JSlider.new(0, 30, 10)
      @speed = JSlider.new(5, 40, 22)
      @bounce = JSlider.new(0, 100, 30)
      @gravity.add_change_listener { @sim.world.set_gravity(0, -@gravity.value * 0.98) }
      reset = JButton.new('Rebuild tower')
      reset.add_action_listener { @sim.reset(gravity: @gravity.value * 0.98) }
      @hud = JLabel.new
      controls = JPanel.new(FlowLayout.new(FlowLayout::LEFT))
      [JLabel.new('Gravity'), @gravity, JLabel.new('Speed'), @speed, JLabel.new('Bounce'), @bounce, reset, @hud].each { |c| controls.add(c) }

      @frame = JFrame.new('Physics Tower - dyn4j from Ruby (click to fire)')
      @frame.add(@view, BorderLayout::CENTER)
      @frame.add(controls, BorderLayout::SOUTH)
      @frame.set_size(1060, 640)
      @frame.set_location(0, 0)
      @frame.visible = true

      @frames, @since, @fps = 0, Time.now, 0
      @timer = javax.swing.Timer.new(16) { tick }
      @timer.start
    end

    def tick
      now = Time.now
      @sim.step(now - (@last_tick || now))
      @last_tick = now
      @view.repaint
      @frames += 1
      return unless Time.now - @since >= 1
      @fps = (@frames / (Time.now - @since)).round
      @frames, @since = 0, Time.now
      @hud.text = "  #{@fps} fps, #{@sim.bodies.size} bodies"
    end

    def fire_at(px, py)
      # The world is stepped and drawn on the Swing thread; change it there too.
      return javax.swing.SwingUtilities.invoke_later { fire_at(px, py) } unless javax.swing.SwingUtilities.event_dispatch_thread?
      tx, ty = @view.to_world(px, py)
      @sim.fire(tx, ty, speed: @speed.value, bounce: @bounce.value / 100.0)
    end

    def aim_at(px, py)
      @view.aim = [px, py]
    end

    def stop = @timer.stop
  end

  def self.open = @game = Game.new
  def self.game = @game
end

Physics.open
