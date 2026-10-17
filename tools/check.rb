# Check every entry the way spin will use it: the file parses, each release
# names a full commit SHA that the repo serves, and that commit's spin.toml
# carries the release's version. With --upstream, also list what
# matz/spin-index has that this index lacks (it is meant to be a superset).
#
# Usage: ruby tools/check.rb [--upstream]     (from the repo root)

require "tmpdir"
require_relative "index"

UPSTREAM = "https://github.com/matz/spin-index"

def sh(*cmd)
  out = IO.popen(cmd, err: File::NULL, &:read)
  [$?.success?, out]
end

errors = []
entries = Index.entries(".")
abort "no packages/*.toml" if entries.empty?

Dir.mktmpdir do |tmp|
  entries.each do |e|
    file = File.basename(e.path, ".toml")
    err = ->(msg) { errors << "#{file}: #{msg}" }
    err.("name #{e.name.inspect} is not the file name") unless e.name == file
    err.("repo must be an https:// URL") unless e.repo.to_s.start_with?("https://")
    err.("no [[release]]") if e.releases.empty?

    git = File.join(tmp, file)
    sh("git", "init", "-q", "--bare", git)
    seen = []
    e.releases.each do |r|
      v, ref = r["version"].to_s, r["ref"].to_s
      unless v.match?(/\A\d+\.\d+\.\d+\z/)
        err.("release #{v.inspect} is not x.y.z")
        next
      end
      dup = seen.find { |s| Index.vcmp(s, v) == 0 }
      err.("release #{v} is listed twice (as #{dup})") if dup
      seen << v
      unless ref.match?(/\A[0-9a-f]{40}\z/)
        err.("release #{v}: ref must be a full commit SHA")
        next
      end
      ok, = sh("git", "-C", git, "fetch", "-q", "--depth", "1", e.repo, ref)
      unless ok
        err.("release #{v}: #{e.repo} does not serve #{ref}")
        next
      end
      ok, toml = sh("git", "-C", git, "show", "#{ref}:spin.toml")
      got = ok && toml[/^version\s*=\s*"([^"]*)"/, 1]
      err.("release #{v}: spin.toml at #{ref[0, 12]} says version #{got.inspect}") unless got == v
    end
    e.probes.each do |p|
      err.("probe for #{p["version"]}, which is not a release") unless seen.include?(p["version"])
      err.("probe result #{p["result"].inspect} is not pass or fail") unless %w[pass fail].include?(p["result"])
    end
    puts "#{file}: #{seen.join(", ")}"
  end

  if ARGV.include?("--upstream")
    up = File.join(tmp, "upstream")
    ok, = sh("git", "clone", "-q", "--depth", "1", UPSTREAM, up)
    abort "cannot clone #{UPSTREAM}" unless ok
    ours = entries.to_h { |e| [e.name, e] }
    Index.entries(up).each do |u|
      mine = ours[u.name]
      if mine.nil?
        puts "upstream has #{u.name}, which this index lacks"
      elsif mine.repo != u.repo
        errors << "#{u.name}: repo #{mine.repo} differs from upstream's #{u.repo}"
      else
        u.releases.each do |r|
          m = mine.releases.find { |x| x["version"] == r["version"] }
          if m.nil?
            puts "upstream has #{u.name} #{r["version"]}, which this index lacks"
          elsif m["ref"] != r["ref"]
            errors << "#{u.name} #{r["version"]}: ref differs from upstream's"
          end
        end
      end
    end
  end
end

if errors.empty?
  puts "ok: #{entries.length} packages"
else
  errors.each { |m| warn "error: #{m}" }
  exit 1
end
