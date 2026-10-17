# Run `spin test` on every release in the index against one Spinel build and
# record the outcome as [[probe]] entries, which spin reads when it selects a
# release: a fail recorded against the user's compiler build is a strong
# warning, and a release whose newest probe is a fail still warns.
#
# Every release is probed, not only the newest: selection is MVS, so a
# constraint like "~> 0.1" picks the LOWEST matching release, and an old
# release that no longer builds is exactly what a user gets.
#
# A probe is appended only when it says something new for that release (no
# probe yet, or the result or failing tests changed), so the files grow on
# changes, not on every run.
#
# Usage: ruby tools/probe.rb [--spin PATH] [--only NAME,...] [--summary FILE]
#                            [--regressions FILE]

require "tmpdir"
require "timeout"
require_relative "index"

spin = "spin"
only = nil
summary = nil
regressions = nil
args = ARGV.dup
until args.empty?
  case (a = args.shift)
  when "--spin" then spin = File.expand_path(args.shift)
  when "--only" then only = args.shift.split(",")
  when "--summary" then summary = args.shift
  when "--regressions" then regressions = args.shift
  else abort "unknown argument #{a}"
  end
end

# spin matches a probe to the running compiler by the third field of
# `spinel --version`, the build revision in parentheses.
spinel = File.join(File.dirname(IO.popen(["sh", "-c", "command -v #{spin}"], &:read).strip), "spinel")
ver = IO.popen([spinel, "--version"], &:read).to_s.split(" ")
rev = ver[2].to_s.delete_prefix("(").delete_suffix(")")
abort "cannot read the Spinel revision from #{spinel} --version" if rev.empty? || rev == "unknown"
date = Time.now.utc.strftime("%Y-%m-%d")

def run(cmd, dir, limit)
  out = +""
  ok = false
  IO.popen(cmd, chdir: dir, err: [:child, :out], pgroup: true) do |io|
    begin
      Timeout.timeout(limit) { out = io.read }
      io.close
      ok = $?.success?
    rescue Timeout::Error
      Process.kill("-KILL", io.pid) rescue nil
      out << "\n(timed out after #{limit} s)"
    end
  end
  [ok, out]
end

rows = []
regressed = []
Dir.mktmpdir do |tmp|
  Index.entries(".").each do |e|
    next if only && !only.include?(e.name)
    e.releases.each do |r|
      v = r["version"]
      dir = File.join(tmp, "#{e.name}-#{v}")
      fetched = system("git", "init", "-q", dir) &&
                system("git", "-C", dir, "fetch", "-q", "--depth", "1", e.repo, r["ref"]) &&
                system("git", "-C", dir, "checkout", "-q", "FETCH_HEAD")
      ok, out = fetched ? run([spin, "test"], dir, 1800) : [false, "cannot fetch #{r["ref"]}"]
      result = ok ? "pass" : "fail"
      failed = out.scan(/^FAIL\s+(\S+)/).flatten
      detail = if ok then nil
               elsif failed.any? then "spin test: #{failed.join(", ")}"
               else (out.lines.map(&:strip).reject(&:empty?).last || "spin test failed")[0, 200]
               end
      tally = out[/^(\d+\/\d+) passed/, 1]
      prev = Index.latest_probe(e, v)
      fresh = prev.nil? || prev["result"] != result || prev["detail"].to_s != detail.to_s
      if fresh
        Index.append_probe(e.path, version: v, spinel: rev, result: result, date: date, detail: detail)
        e.probes << { "version" => v, "result" => result, "detail" => detail.to_s }
        regressed << "#{e.name} #{v}: #{detail}" if result == "fail" && prev&.fetch("result") == "pass"
      end
      rows << [e.name, v, result, tally || "-", detail.to_s, fresh ? "recorded" : "unchanged"]
      puts "#{result.ljust(4)} #{e.name} #{v} #{tally}#{detail ? " (#{detail})" : ""}#{fresh ? " [recorded]" : ""}"
      unless ok
        # the output of a failing run, folded in the Actions log
        puts "::group::#{e.name} #{v}: spin test output (last 80 lines)" if ENV["GITHUB_ACTIONS"]
        puts out.lines.last(80).join
        puts "::endgroup::" if ENV["GITHUB_ACTIONS"]
      end
      $stdout.flush
    end
  end
end

table = +"Spinel #{rev} (#{date})\n\n| package | release | result | tests | detail | probe |\n|---|---|---|---|---|---|\n"
rows.each { |r| table << "| #{r.map { |c| c.to_s.gsub("|", "\\|") }.join(" | ")} |\n" }
File.write(summary, table) if summary
File.write(regressions, regressed.map { |l| "- #{l}\n" }.join) if regressions && regressed.any?
puts "#{rows.count { |r| r[2] == "pass" }}/#{rows.length} releases pass on Spinel #{rev}"
