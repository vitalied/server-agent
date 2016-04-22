require 'json'
require 'yaml'
require 'net/http'

# Show the percentage of CPU used
def uw_cpuused
  @proc0 = File.readlines('/proc/stat').grep(/^cpu /).first.split(" ")
  sleep 10
  @proc1 = File.readlines('/proc/stat').grep(/^cpu /).first.split(" ")

  @proc0usagesum = @proc0[1].to_i + @proc0[2].to_i + @proc0[3].to_i
  @proc1usagesum = @proc1[1].to_i + @proc1[2].to_i + @proc1[3].to_i
  @procusage = @proc1usagesum - @proc0usagesum

  @proc0total = 0
  (1..4).each do |i|
    @proc0total += @proc0[i].to_i
  end
  @proc1total = 0
  (1..4).each do |i|
    @proc1total += @proc1[i].to_i
  end
  @proctotal = (@proc1total - @proc0total)

  @cpuusage = (@procusage.to_f / @proctotal.to_f)
  @cpuusagepercentage = (100 * @cpuusage / 10).to_f.round(2)
end

# Show the percentage of Active Memory used
def self.uw_memused
  if File.exists?("/proc/meminfo")
    File.open("/proc/meminfo", "r") do |file|
      @result = file.read
    end
  end

  @memstat = @result.split("\n").collect{|x| x.strip}
  @memtotal = @memstat[0].gsub(/[^0-9]/, "").to_f
  @memfree = @memstat[1].gsub(/[^0-9]/, "").to_f
  @memused = (@memtotal - @memfree) * 100 / @memtotal
  @memusedpercentage = @memused.round
end

# Show the percentage of disk used.
def uw_diskused_perc
  df = `df --total`
  used=df.split(" ")
  unless used.last=="-"
    return used.last.to_f.round(2)
  else
    return used[-2].to_f.round(2)
  end
end

# Return hash of proccesses by cpu consumption
def uw_cpuprocesses
  ps = `ps --no-headers axo "%cpu,args" | sort -k1nr`

  res = []
  ps.each_line do |line|
    line = line.chomp.split(" ")
    process_cpu = line.first.to_f
    res << [line.drop(1).join(" "), process_cpu]
  end

  res
end


config = begin
  YAML.load_file(File.expand_path("../config/agent.yml", __FILE__))
rescue ArgumentError => e
  puts "Could not parse YAML: #{e.message}"
end

uri = URI(config["server_monitor_url"])

params = {
  token: config["token"],
  server: {
    cpu_usage: uw_cpuused,
    memory_usage: uw_memused,
    disk_usage: uw_diskused_perc,
    processes: uw_cpuprocesses
  }
}

http = Net::HTTP.new(uri.hostname, uri.port)

req = Net::HTTP::Patch.new(uri)
req["Accept"] = "application/json"
req["Content-type"] = "application/json"
req.body = JSON.generate(params)

res = http.start do |http|
  http.request(req)
end

res = JSON.parse(res.body)

puts res

if res["force_shutdown"]
  `sudo shutdown -h now`
end
