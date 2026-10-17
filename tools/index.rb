# Read and write packages/<name>.toml: the subset of TOML the index uses
# (top-level `key = "string"` pairs, then [[release]] and [[probe]] tables
# of the same), the shape spin's own reader accepts.

module Index
  Entry = Struct.new(:path, :name, :repo, :releases, :probes)

  def self.parse(path)
    top = {}
    tables = []          # [kind, {key => value}] in file order
    cur = top
    File.readlines(path, chomp: true).each_with_index do |line, i|
      s = line.sub(/\s+#.*\z/, "").strip
      next if s.empty? || s.start_with?("#")
      if (m = s.match(/\A\[\[(release|probe)\]\]\z/))
        cur = {}
        tables << [m[1], cur]
      elsif (m = s.match(/\A([a-z_]+)\s*=\s*"((?:[^"\\]|\\.)*)"\z/))
        raise "#{path}:#{i + 1}: duplicate key #{m[1]}" if cur.key?(m[1])
        cur[m[1]] = m[2]
      else
        raise "#{path}:#{i + 1}: not index TOML: #{line}"
      end
    end
    Entry.new(path, top["name"], top["repo"],
              tables.select { |k, _| k == "release" }.map(&:last),
              tables.select { |k, _| k == "probe" }.map(&:last))
  end

  def self.entries(dir)
    Dir.glob(File.join(dir, "packages", "*.toml")).sort.map { |p| parse(p) }
  end

  # spin's vcmp: numeric components, missing parts are 0
  def self.vcmp(a, b)
    pa = a.split(".").map(&:to_i)
    pb = b.split(".").map(&:to_i)
    n = [pa.length, pb.length].max
    n.times do |i|
      c = (pa[i] || 0) <=> (pb[i] || 0)
      return c unless c == 0
    end
    0
  end

  # The probe spin treats as newest for a version: the last one in the file.
  def self.latest_probe(entry, version)
    entry.probes.select { |p| p["version"] == version }.last
  end

  def self.append_probe(path, version:, spinel:, result:, date:, detail: nil)
    s = File.read(path).sub(/\n*\z/, "\n")
    s << "\n[[probe]]\nversion = \"#{version}\"\nspinel = \"#{spinel}\"\nresult = \"#{result}\"\n"
    s << "detail = \"#{detail.gsub(/["\\]/) { |c| "\\" + c }}\"\n" if detail && !detail.empty?
    s << "date = \"#{date}\"\n"
    File.write(path, s)
  end
end
