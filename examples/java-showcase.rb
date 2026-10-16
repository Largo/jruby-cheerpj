# Java showcase for the JRuby-on-CheerpJ REPL.
# Paste one block at a time into http://localhost:8017/ (each was verified in the page, CheerpJ 4.3 / Java 17).
# GUI examples: swing.rb (JFrame) and processing.rb (Processing sketches).

# ---- What JVM am I on? ----
java_import java.lang.System
puts "JVM:  #{System.getProperty('java.vm.name')} #{System.getProperty('java.version')}"
puts "OS:   #{System.getProperty('os.name')} #{System.getProperty('os.arch')}"
puts "CPUs: #{java.lang.Runtime.getRuntime.availableProcessors}"
puts "Heap: #{java.lang.Runtime.getRuntime.maxMemory / 1024 / 1024} MB max"

# ---- Java Streams with Ruby blocks as lambdas ----
list = java.util.ArrayList.new((1..20).to_a)
result = list.stream
  .filter { |n| n.even? }
  .map { |n| n * n }
  .collect(java.util.stream.Collectors.toList)
p result.to_a
puts list.stream.mapToInt { |n| n }.summaryStatistics

# ---- BigInteger / BigDecimal ----
big = (1..100).reduce(:*).to_java(java.math.BigInteger)
puts "100! = #{big.bitLength} bits, probable prime? #{big.isProbablePrime(20)}"
mersenne = (2**127 - 1).to_java(java.math.BigInteger)
puts "2^127-1 prime? #{mersenne.isProbablePrime(50)}"
puts java.math.BigDecimal.new('1').divide(java.math.BigDecimal.new('7'), java.math.MathContext.new(60))

# ---- SHA-256, Base64, UUID from java.security / java.util ----
md = java.security.MessageDigest.getInstance('SHA-256')
h = md.digest('hello from the browser JVM'.to_java_bytes)
puts h.to_a.map { |b| '%02x' % (b & 0xff) }.join
puts java.util.Base64.getEncoder.encodeToString('JRuby on CheerpJ'.to_java_bytes)
puts java.util.UUID.randomUUID

# ---- java.time with real time zones ----
java_import java.time.ZonedDateTime
java_import java.time.ZoneId
java_import java.time.LocalDate
now = ZonedDateTime.now(ZoneId.of('Europe/Zurich'))
puts now.format(java.time.format.DateTimeFormatter.ofPattern('EEEE d MMMM yyyy, HH:mm z'))
%w[Asia/Tokyo America/New_York Australia/Sydney].each { |z| puts "#{z.ljust(18)} #{now.withZoneSameInstant(ZoneId.of(z)).toLocalTime}" }
puts "Days until 2027: #{java.time.temporal.ChronoUnit::DAYS.between(LocalDate.now, LocalDate.of(2027, 1, 1))}"

# ---- Thread pool + atomics (Ruby lambdas as Callables) ----
pool = java.util.concurrent.Executors.newFixedThreadPool(4)
tasks = (1..8).map { |i| -> { (1..i * 1000).sum } }
futures = tasks.map { |t| pool.submit(t.to_java(java.util.concurrent.Callable)) }
p futures.map(&:get)
pool.shutdown
counter = java.util.concurrent.atomic.AtomicLong.new
4.times.map { Thread.new { 1000.times { counter.incrementAndGet } } }.each(&:join)
puts "atomic counter: #{counter.get}"

# ---- TreeMap, PriorityQueue, ConcurrentHashMap ----
tm = java.util.TreeMap.new
%w[pear apple fig banana].each { |w| tm.put(w, w.length) }
puts tm
puts tm.firstKey, tm.headMap('c')
pq = java.util.PriorityQueue.new([5, 1, 4, 2, 3])
puts 5.times.map { pq.poll }.inspect
chm = java.util.concurrent.ConcurrentHashMap.new
'the quick brown the lazy the'.split.each { |w| chm.merge(w, 1) { |a, b| a + b } }
puts chm

# ---- Ruby class implementing a Java interface ----
class Shouter
  include java.util.Comparator
  def compare(a, b) = b.length <=> a.length
end
l = java.util.ArrayList.new(%w[a ccc bb dddd])
java.util.Collections.sort(l, Shouter.new)
p l.to_a
r = java.lang.Runnable.impl { puts 'Ruby block running as a java.lang.Runnable' }
java.lang.Thread.new(r).tap(&:start).join

# ---- Ruby class extending a Java class ----
class Point < java.awt.Point
  def to_s = "(#{x}, #{y})"
end
p1 = Point.new(3, 4)
puts p1, p1.distance(0, 0), p1.java_class.superclass

# ---- Deflater + CRC32 from java.util.zip ----
data = ('JRuby in the browser! ' * 200).to_java_bytes
d = java.util.zip.Deflater.new(9)
d.setInput(data); d.finish
buf = Java::byte[data.length].new
n = d.deflate(buf)
puts "#{data.length} bytes -> #{n} bytes deflated"
crc = java.util.zip.CRC32.new; crc.update(data)
puts "crc32: %08x" % crc.getValue

# ---- java.util.regex named groups ----
m = java.util.regex.Pattern.compile('(?<user>\\w+)@(?<host>[\\w.]+)').matcher('mail ada@example.com or matz@example.org')
while m.find
  puts "#{m.group('user')} at #{m.group('host')}"
end

# ---- Reflection on Java classes ----
c = java.lang.String.java_class
puts c.name
puts java.lang.String.java_class.declared_instance_methods.map(&:name).uniq.sort.first(15).join(' ')
puts java.lang.Class.forName('java.util.HashMap').getInterfaces.map(&:getSimpleName).join(', ')

# ---- Java2D drawing + ImageIO PNG encoding (offscreen) ----
img = java.awt.image.BufferedImage.new(200, 100, java.awt.image.BufferedImage::TYPE_INT_RGB)
g = img.createGraphics
g.setColor(java.awt.Color::RED); g.fillOval(10, 10, 80, 80)
g.dispose
puts '%06x' % (img.getRGB(50, 50) & 0xffffff)
out = java.io.ByteArrayOutputStream.new
javax.imageio.ImageIO.write(img, 'png', out)
puts "PNG: #{out.size} bytes"
