#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# save_all_blocks_fast.rb
#
# Standalone full-block backfill (does NOT replace save_all_blocks.rb).
# - No Rails boot
# - Same full getblock verbosity=1 payload (all txs) as the original script
# - Persistent HTTP + JSON-RPC batching + concurrent workers + DB batch upsert
# - OVERWRITES existing rows for the same block_number
# - Default resume: end of contiguous 0..N (re-do last height), then fill gaps
#
# Usage:
#   bundle exec ruby save_all_blocks_fast.rb
#   bundle exec ruby save_all_blocks_fast.rb 36542
#   bundle exec ruby save_all_blocks_fast.rb 36542 500000
#
# ENV:
#   BACKFILL_WORKERS=8       # threads (default 8)
#   BACKFILL_RPC_BATCH=40    # heights per JSON-RPC batch per worker (default 40)
#   BACKFILL_DB_BATCH=100    # rows per DB transaction (default 100)
#   BACKFILL_LOG_EVERY=500   # log every N blocks written (default 500)
#   BACKFILL_RPC_TIMEOUT=120
#   BITCOIN_RPC_*  DATABASE_URL / PG*
# =============================================================================

require "bundler/setup"
require "json"
require "time"
require "thread"
require "net/http"
require "uri"
require "pg"

WORKERS     = Integer(ENV.fetch("BACKFILL_WORKERS", "8"))
RPC_BATCH   = Integer(ENV.fetch("BACKFILL_RPC_BATCH", "40"))
DB_BATCH    = Integer(ENV.fetch("BACKFILL_DB_BATCH", "100"))
LOG_EVERY   = Integer(ENV.fetch("BACKFILL_LOG_EVERY", "500"))
RPC_TIMEOUT = Integer(ENV.fetch("BACKFILL_RPC_TIMEOUT", "120"))

RPC_URL  = ENV.fetch("BITCOIN_RPC_URL")
RPC_USER = ENV.fetch("BITCOIN_RPC_USERNAME")
RPC_PASS = ENV.fetch("BITCOIN_RPC_PASSWORD")

abort "BACKFILL_WORKERS must be >= 1" if WORKERS < 1
abort "BACKFILL_RPC_BATCH must be >= 1" if RPC_BATCH < 1
abort "BACKFILL_DB_BATCH must be >= 1" if DB_BATCH < 1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def format_duration(seconds)
  seconds = seconds.to_f
  return "…" if seconds.infinite? || seconds.nan?
  return "<1s" if seconds < 1

  h = (seconds / 3600).floor
  m = ((seconds % 3600) / 60).floor
  s = (seconds % 60).floor
  if h.positive?
    format("%dh %02dm %02ds", h, m, s)
  elsif m.positive?
    format("%dm %02ds", m, s)
  else
    format("%ds", s)
  end
end

def database_config
  if (url = ENV["DATABASE_URL"]).to_s.strip != ""
    return { connection_string: url }
  end

  {
    dbname: ENV.fetch("PGDATABASE", "lnurl_rails_development"),
    user: ENV["PGUSER"],
    password: ENV["PGPASSWORD"],
    host: ENV["PGHOST"],
    port: ENV["PGPORT"]
  }.compact
end

def connect_db
  PG.connect(database_config)
end

def parse_height_arg(value, label)
  return nil if value.nil? || value.to_s.strip.empty?

  Integer(value)
rescue ArgumentError
  abort "[fast] Invalid #{label}: #{value.inspect}"
end

def max_block_number(conn)
  row = conn.exec("SELECT MAX(block_number) AS m FROM block_histories").first
  row && row["m"] ? Integer(row["m"]) : nil
end

def contiguous_from_zero_end(conn)
  res = conn.exec(<<~SQL)
    SELECT block_number
    FROM block_histories
    GROUP BY block_number
    ORDER BY block_number ASC
  SQL
  return nil if res.ntuples.zero?

  heights = res.map { |r| Integer(r["block_number"]) }
  return nil if heights.first > 0

  expect = 0
  heights.each do |h|
    next if h < expect
    return expect - 1 if h > expect && expect.positive?
    return nil if h > expect && expect.zero?

    expect = h + 1
  end
  expect - 1
end

def default_start_height(conn)
  cont_end = contiguous_from_zero_end(conn)
  cont_end.nil? ? 0 : cont_end
end

def existing_heights(conn, heights)
  return {} if heights.empty?

  placeholders = heights.each_index.map { |i| "$#{i + 1}" }.join(", ")
  res = conn.exec_params(
    "SELECT block_number FROM block_histories WHERE block_number IN (#{placeholders})",
    heights
  )
  res.each_with_object({}) { |r, h| h[Integer(r["block_number"])] = true }
end

# Returns [written, overwritten]
def upsert_batch!(conn, rows)
  return [0, 0] if rows.empty?

  by_height = {}
  rows.each { |r| by_height[r[:height]] = r }
  rows = by_height.values.sort_by { |r| r[:height] }

  heights = rows.map { |r| r[:height] }
  already = existing_heights(conn, heights)
  overwritten = already.size
  written = rows.size
  now = Time.now.utc

  conn.transaction do
    unless already.empty?
      ph = already.keys.each_index.map { |i| "$#{i + 1}" }.join(", ")
      conn.exec_params(
        "DELETE FROM block_histories WHERE block_number IN (#{ph})",
        already.keys
      )
    end

    values_sql = []
    binds = []
    rows.each_with_index do |row, i|
      base = i * 5
      values_sql << "($#{base + 1}, $#{base + 2}, $#{base + 3}, $#{base + 4}, $#{base + 5})"
      binds.push(row[:height], row[:hash], row[:data], now, now)
    end

    conn.exec_params(
      "INSERT INTO block_histories (block_number, block_hash, data, created_at, updated_at) VALUES #{values_sql.join(', ')}",
      binds
    )
  end

  [written, overwritten]
end

# ---------------------------------------------------------------------------
# Persistent HTTP + JSON-RPC (single + batch)
# ---------------------------------------------------------------------------

class FastBitcoinRpc
  def initialize(url, user, password)
    @uri = URI(url.to_s.sub(%r{/*$}, "") + "/")
    @user = user
    @password = password
    @http = Net::HTTP.new(@uri.host, @uri.port)
    @http.use_ssl = (@uri.scheme == "https")
    @http.open_timeout = 15
    @http.read_timeout = RPC_TIMEOUT
    @http.keep_alive_timeout = 60
    @http.start
  end

  def close
    @http.finish if @http.started?
  rescue StandardError
    nil
  end

  def get_block_count
    call("getblockcount")["result"]
  end

  # One method, returns full RPC response hash (same shape original stored).
  def call(method, *params)
    body = post_json(
      { jsonrpc: "1.0", id: "1", method: method, params: params }
    )
    raise rpc_error_message(method, body["error"]) if body["error"]

    body
  end

  # requests: array of { id:, method:, params: }
  # returns Hash id => full response body
  def batch(requests)
    return {} if requests.empty?

    payload = requests.map do |r|
      { jsonrpc: "1.0", id: r[:id], method: r[:method], params: r[:params] || [] }
    end
    raw = post_json(payload)
    unless raw.is_a?(Array)
      raise "RPC batch expected array response, got #{raw.class}"
    end

    raw.each_with_object({}) do |item, acc|
      acc[item["id"]] = item
    end
  end

  private

  def post_json(obj)
    attempts = 0
    begin
      attempts += 1
      req = Net::HTTP::Post.new(@uri)
      req.basic_auth(@user, @password)
      req["Content-Type"] = "application/json"
      req["Connection"] = "keep-alive"
      req.body = JSON.generate(obj)

      res = @http.request(req)
      raise "HTTP #{res.code}: empty body" if res.body.nil? || res.body.empty?
      raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    rescue StandardError
      raise if attempts >= 5

      # reconnect and retry
      begin
        @http.finish if @http.started?
      rescue StandardError
        nil
      end
      @http.start
      sleep([attempts, 5].min)
      retry
    end
  end

  def rpc_error_message(method, err)
    "RPC #{method} error #{err["code"]}: #{err["message"]}"
  end
end

# ---------------------------------------------------------------------------
# Progress (honest — based on blocks written to DB only)
# ---------------------------------------------------------------------------

def print_progress(written, total, t0, overwritten, bytes_stored, errors, in_flight)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  rate = written.positive? && elapsed.positive? ? written / elapsed : 0.0
  remaining = [total - written, 0].max
  eta = rate.positive? ? remaining / rate : Float::INFINITY
  pct = total.positive? ? (written * 100.0 / total) : 100.0

  puts format(
    "[fast] %d / %d written (%.2f%%) | %.1f blk/s | elapsed %s | ETA %s | overwritten=%d errors=%d in_flight≈%d | %.1f MB",
    written,
    total,
    pct,
    rate,
    format_duration(elapsed),
    rate.positive? ? format_duration(eta) : "calculating…",
    overwritten,
    errors,
    in_flight,
    bytes_stored / 1024.0 / 1024.0
  )
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

bootstrap = FastBitcoinRpc.new(RPC_URL, RPC_USER, RPC_PASS)
tip = Integer(bootstrap.get_block_count)
bootstrap.close

conn0 = connect_db
db_max = max_block_number(conn0)
cont_end = contiguous_from_zero_end(conn0)
default_start = default_start_height(conn0)
conn0.close

cli_start = parse_height_arg(ARGV[0], "start height")
env_start = parse_height_arg(ENV["BACKFILL_START"], "BACKFILL_START")
cli_end   = parse_height_arg(ARGV[1], "end height")
env_end   = parse_height_arg(ENV["BACKFILL_END"], "BACKFILL_END")

start_source = nil
start_block =
  if !cli_start.nil?
    start_source = "cli"
    cli_start
  elsif !env_start.nil?
    start_source = "ENV BACKFILL_START"
    env_start
  else
    start_source = cont_end ? "contiguous 0..#{cont_end} (overwrite last, fill gap)" : "empty → 0"
    default_start
  end

end_source = nil
end_block =
  if !cli_end.nil?
    end_source = "cli"
    cli_end
  elsif !env_end.nil?
    end_source = "ENV BACKFILL_END"
    env_end
  else
    end_source = "tip"
    tip
  end

abort "[fast] start height must be >= 0" if start_block.negative?

if start_block > end_block
  puts "[fast] Nothing to do: start=#{start_block} end=#{end_block}"
  exit 0
end

total = end_block - start_block + 1

puts "[fast] Full-block backfill (no Rails) — honest progress uses DB writes only"
puts "[fast] RPC=#{RPC_URL}"
puts "[fast] workers=#{WORKERS} rpc_batch=#{RPC_BATCH} db_batch=#{DB_BATCH} log_every=#{LOG_EVERY}"
puts "[fast] DB MAX=#{db_max.inspect} contiguous_from_0_end=#{cont_end.inspect}"
puts "[fast] start=#{start_block} (#{start_source}) → end=#{end_block} (#{end_source}) | #{total} blocks | tip=#{tip}"
puts "[fast] stores complete getblock v=1 JSON (all txs); overwrites existing heights"
puts "[fast] ETA = remaining_writes / measured_write_rate (no fake speedup claims)"
puts ""

# Atomic height dispenser (no 900k-item Queue)
height_mutex = Mutex.new
next_height = start_block

claim_heights = lambda do |n|
  height_mutex.synchronize do
    return [] if next_height > end_block

    from = next_height
    to = [next_height + n - 1, end_block].min
    next_height = to + 1
    (from..to).to_a
  end
end

stats_mutex = Mutex.new
written = 0
overwritten = 0
bytes_stored = 0
errors = 0
in_flight = 0
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
last_log_at = 0

maybe_log = lambda do
  stats_mutex.synchronize do
    if written - last_log_at >= LOG_EVERY || written == total
      print_progress(written, total, t0, overwritten, bytes_stored, errors, in_flight)
      last_log_at = written
    end
  end
end

workers = WORKERS.times.map do |worker_id|
  Thread.new do
    Thread.current.abort_on_exception = true
    rpc = FastBitcoinRpc.new(RPC_URL, RPC_USER, RPC_PASS)
    db = connect_db
    pending = [] # unflushed rows

    flush = lambda do
      return if pending.empty?

      chunk = pending.shift(pending.size)
      begin
        # split into DB_BATCH sized transactions
        chunk.each_slice(DB_BATCH) do |slice|
          n_w, n_o = upsert_batch!(db, slice)
          size = slice.sum { |r| r[:data].bytesize }
          stats_mutex.synchronize do
            written += n_w
            overwritten += n_o
            bytes_stored += size
            in_flight = [in_flight - slice.size, 0].max
          end
          maybe_log.call
        end
      rescue StandardError => e
        warn "[fast] worker=#{worker_id} DB error: #{e.class}: #{e.message}"
        chunk.each do |row|
          begin
            n_w, n_o = upsert_batch!(db, [row])
            stats_mutex.synchronize do
              written += n_w
              overwritten += n_o
              bytes_stored += row[:data].bytesize
              in_flight = [in_flight - 1, 0].max
            end
          rescue StandardError => e2
            stats_mutex.synchronize do
              errors += 1
              in_flight = [in_flight - 1, 0].max
            end
            warn "[fast] worker=#{worker_id} height=#{row[:height]} failed: #{e2.message}"
          end
        end
        maybe_log.call
      end
    end

    loop do
      heights = claim_heights.call(RPC_BATCH)
      break if heights.empty?

      stats_mutex.synchronize { in_flight += heights.size }

      begin
        # 1) batch getblockhash for the whole chunk (1 HTTP RTT)
        hash_reqs = heights.map { |h| { id: "h#{h}", method: "getblockhash", params: [h] } }
        hash_res = rpc.batch(hash_reqs)

        hashes = {}
        heights.each do |h|
          item = hash_res["h#{h}"]
          raise "missing getblockhash for #{h}" unless item
          raise "getblockhash #{h}: #{item["error"]}" if item["error"]

          hashes[h] = item["result"].to_s
        end

        # 2) batch getblock verbosity=1 (1 HTTP RTT) — full txs
        block_reqs = heights.map { |h| { id: "b#{h}", method: "getblock", params: [hashes[h], 1] } }
        block_res = rpc.batch(block_reqs)

        heights.each do |h|
          item = block_res["b#{h}"]
          raise "missing getblock for #{h}" unless item
          raise "getblock #{h}: #{item["error"]}" if item["error"]

          # Store entire RPC response object (same as original script)
          data_json = item.to_json
          pending << { height: h, hash: hashes[h], data: data_json }
        end

        flush.call if pending.size >= DB_BATCH
      rescue StandardError => e
        stats_mutex.synchronize do
          errors += heights.size
          in_flight = [in_flight - heights.size, 0].max
        end
        warn "[fast] worker=#{worker_id} batch #{heights.first}..#{heights.last}: #{e.class}: #{e.message}"
      end
    end

    flush.call
    db.close
    rpc.close
  end
end

workers.each(&:join)

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
rate = written.positive? && elapsed.positive? ? written / elapsed : 0.0

puts ""
puts "[fast] DONE"
puts "[fast] written=#{written}/#{total} overwritten=#{overwritten} errors=#{errors}"
puts "[fast] data≈#{format('%.1f', bytes_stored / 1024.0 / 1024.0)} MB wall=#{format_duration(elapsed)} avg=#{format('%.1f', rate)} blk/s (DB writes)"
puts "[fast] exit"
