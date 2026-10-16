# QR Code Studio: type text, get a live QR code from ZXing (Java), then let ZXing read it back.
# Open with ?app=qr. Scan the screen with your phone to check it.
#
# Ruby ideas on show: blocks as Java listeners, a Ruby class implementing a Java interface,
# Hashes turned into Java maps, Java enums as Ruby constants.

module QRStudio
  java_import javax.swing.JFrame
  java_import javax.swing.JPanel
  java_import javax.swing.JLabel
  java_import javax.swing.JTextField
  java_import javax.swing.JComboBox
  java_import javax.swing.JSlider
  java_import javax.swing.ImageIcon
  java_import javax.swing.BorderFactory
  java_import javax.swing.SwingConstants
  java_import java.awt.BorderLayout
  java_import java.awt.GridBagLayout
  java_import java.awt.GridBagConstraints
  java_import java.awt.Insets
  java_import java.awt.Font
  java_import com.google.zxing.BarcodeFormat
  java_import com.google.zxing.EncodeHintType
  java_import com.google.zxing.MultiFormatReader
  java_import com.google.zxing.BinaryBitmap
  java_import com.google.zxing.qrcode.QRCodeWriter
  java_import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
  java_import com.google.zxing.common.HybridBinarizer
  java_import com.google.zxing.client.j2se.MatrixToImageWriter
  java_import com.google.zxing.client.j2se.MatrixToImageConfig
  java_import com.google.zxing.client.j2se.BufferedImageLuminanceSource

  # name => [dark, light] as RGB
  COLORS = {
    'Classic black' => [0x000000, 0xFFFFFF],
    'Ruby red'      => [0xA4161A, 0xFFF5F5],
    'Ocean'         => [0x0B4F6C, 0xE8F6FA],
    'Forest'        => [0x1B4332, 0xF1FAEE],
  }.freeze

  # Java ints are signed 32-bit, so an opaque ARGB colour like 0xFF000000 must wrap negative.
  def self.argb(rgb) = (0xFF000000 | rgb) - 2**32

  # Calls the block whenever the text field changes: a Ruby class implementing a Java interface.
  class OnChange
    include javax.swing.event.DocumentListener
    def initialize(&blk) = @blk = blk
    def insertUpdate(_e) = @blk.call
    def removeUpdate(_e) = @blk.call
    def changedUpdate(_e) = @blk.call
  end

  class Studio
    attr_reader :frame, :input

    def initialize
      begin
        com.formdev.flatlaf.FlatLightLaf.setup
      rescue NameError
        nil   # FlatLaf not on the classpath: keep the default look
      end
      @input = JTextField.new('https://www.jruby.org', 32)
      @input.font = Font.new(Font::SANS_SERIF, Font::PLAIN, 18)
      @level = JComboBox.new(%w[L M Q H].to_java(:string))
      @level.selected_item = 'M'
      @colors = JComboBox.new(COLORS.keys.to_java(:string))
      @size = JSlider.new(160, 460, 320)
      @image = JLabel.new
      @image.horizontal_alignment = SwingConstants::CENTER
      @info = JLabel.new(' ')
      @decoded = JLabel.new(' ')
      [@info, @decoded].each { |l| l.font = Font.new(Font::MONOSPACED, Font::PLAIN, 13) }

      @input.document.add_document_listener(OnChange.new { render })
      [@level, @colors].each { |c| c.add_action_listener { render } }
      @size.add_change_listener { render unless @size.value_is_adjusting }

      controls = JPanel.new(GridBagLayout.new)
      add_row(controls, 0, 'Text:', @input)
      add_row(controls, 1, 'Error correction (L 7% ... H 30%):', @level)
      add_row(controls, 2, 'Colours:', @colors)
      add_row(controls, 3, 'Size:', @size)
      controls.border = BorderFactory.createEmptyBorder(12, 12, 6, 12)

      footer = JPanel.new(BorderLayout.new)
      footer.add(@info, BorderLayout::NORTH)
      footer.add(@decoded, BorderLayout::SOUTH)
      footer.border = BorderFactory.createEmptyBorder(6, 12, 12, 12)

      @frame = JFrame.new('QR Code Studio - ZXing from Ruby')
      @frame.add(controls, BorderLayout::NORTH)
      @frame.add(@image, BorderLayout::CENTER)
      @frame.add(footer, BorderLayout::SOUTH)
      @frame.set_size(640, 700)
      @frame.set_location(20, 10)
      render
      @frame.visible = true
    end

    def add_row(panel, y, label, field)
      c = GridBagConstraints.new
      c.gridy = y
      c.insets = Insets.new(4, 4, 4, 8)
      c.anchor = GridBagConstraints::WEST
      panel.add(JLabel.new(label), c)
      c.gridx = 1
      c.weightx = 1.0
      c.fill = GridBagConstraints::HORIZONTAL
      panel.add(field, c)
    end

    def render
      text = @input.text
      if text.empty?
        @image.icon = nil
        @info.text = 'Type something above.'
        @decoded.text = ' '
        return
      end
      started = Time.now
      hints = java.util.HashMap.new(EncodeHintType::ERROR_CORRECTION => ErrorCorrectionLevel.value_of(@level.selected_item.to_s),
                                    EncodeHintType::MARGIN => 2,
                                    EncodeHintType::CHARACTER_SET => 'UTF-8')
      px = @size.value
      bits = QRCodeWriter.new.encode(text, BarcodeFormat::QR_CODE, px, px, hints)
      dark, light = COLORS.fetch(@colors.selected_item.to_s)
      image = MatrixToImageWriter.to_buffered_image(bits, MatrixToImageConfig.new(QRStudio.argb(dark), QRStudio.argb(light)))
      @image.icon = ImageIcon.new(image)
      ms = ((Time.now - started) * 1000).round
      @info.text = "#{text.bytesize} bytes -> #{bits.width}x#{bits.height} px, level #{@level.selected_item}, encoded in #{ms} ms"
      @decoded.text = "ZXing reads it back as: #{decode(image).inspect}"
    rescue Java::ComGoogleZxing::WriterException => e
      @image.icon = nil
      @info.text = "Too much text for this level: #{e.message}"
    end

    def decode(image)
      bitmap = BinaryBitmap.new(HybridBinarizer.new(BufferedImageLuminanceSource.new(image)))
      MultiFormatReader.new.decode(bitmap).text
    rescue Java::ComGoogleZxing::NotFoundException
      '(could not read it back)'
    end
  end

  def self.open = @studio = Studio.new
  def self.studio = @studio
end

QRStudio.open
