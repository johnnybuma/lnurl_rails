# frozen_string_literal: true

# Normalize watch-only material for Bitcoin Core import.
#
# Accepted formats (one item per line; # // comments ignored):
# - Compressed pubkey hex (66 chars, 02/03…) or uncompressed (130 chars, 04…)
# - Optional 0x prefix / separators on hex
# - Extended public keys: xpub / ypub / zpub / Ypub / Zpub / tpub / upub / vpub …
#   → expands to many derived pubkeys+addresses (receive + change gap)
# - Optional path: "zpub…/0/5" or "zpub… 0/5" for a single derivation
# - Bitcoin addresses: 1… / 3… / bc1… / tb1… / bcrt1… / m… n… (→ importaddress)
class PublicKeyNormalizer
  class Error < StandardError; end

  # import_method: :importpubkey | :importaddress | :both
  Result = Struct.new(
    :hex, :address, :compressed, :source_format, :line, :import_method, :path, :script,
    keyword_init: true
  )
  LineError = Struct.new(:line, :input_preview, :message, keyword_init: true)

  # BIP84 under account m/84'/coin'/0':
  #   receive PRIMARY m/84'/…/0/0 .. 0/19  (20)
  #   change          m/84'/…/1/0 .. 1/19  (20)
  DEFAULT_RECEIVE = 20
  DEFAULT_CHANGE = 20
  DEFAULT_BRANCHES = [0, 1].freeze
  MAX_DERIVE = 500

  class << self
    def normalize(input, receive_count: DEFAULT_RECEIVE, change_count: DEFAULT_CHANGE)
      raw = input.to_s.strip
      raise Error, "Public key is blank" if raw.empty?

      # Extended public key (may expand to many — use parse_many / expand_one)
      if extended_like?(raw)
        raise Error, "Use parse_many for xpub/zpub expansion"
      end

      if address_like?(raw)
        return Result.new(
          hex: nil,
          address: raw,
          compressed: nil,
          source_format: "address",
          import_method: :importaddress,
          path: nil,
          script: nil
        )
      end

      normalize_hex_pubkey(raw)
    end

    # @return [Hash] { results: [Result], errors: [LineError] }
    def parse_many(text, receive_count: DEFAULT_RECEIVE, change_count: DEFAULT_CHANGE)
      receive_count = receive_count.to_i.clamp(0, MAX_DERIVE)
      change_count = change_count.to_i.clamp(0, MAX_DERIVE)

      results = []
      errors = []
      text.to_s.each_line.with_index(1) do |line, idx|
        raw = line.strip
        next if raw.empty? || raw.start_with?("#", "//")

        begin
          expand_one(raw, line: idx, receive_count: receive_count, change_count: change_count).each do |r|
            results << r
          end
        rescue Error, ExtendedPublicKey::Error => e
          errors << LineError.new(
            line: idx,
            input_preview: preview(raw),
            message: e.message
          )
        end
      end
      { results: results, errors: errors }
    end

    def expand_one(raw, line:, receive_count:, change_count:)
      if extended_like?(raw)
        return expand_extended(raw, line: line, receive_count: receive_count, change_count: change_count)
      end

      if address_like?(raw)
        return [
          Result.new(
            hex: nil,
            address: raw.strip,
            compressed: nil,
            source_format: "address",
            line: line,
            import_method: :importaddress,
            path: nil,
            script: nil
          )
        ]
      end

      r = normalize_hex_pubkey(raw)
      r.line = line
      [r]
    end

    private

    def expand_extended(raw, line:, receive_count:, change_count:)
      parsed, embedded = ExtendedPublicKey.parse(raw)
      derived =
        if embedded && !embedded.to_s.empty?
          [ExtendedPublicKey.derive_path(parsed, embedded)]
        else
          # 3 paths × gap: 0/*, 1/*, 2/* → default 60 addresses
          ExtendedPublicKey.expand(
            raw,
            receive_count: receive_count,
            change_count: change_count,
            branches: DEFAULT_BRANCHES
          )
        end

      derived.map do |d|
        full = HdKeyExpander.bip84_full_path(d.path, network: parsed.network)
        Result.new(
          hex: d.pubkey_hex,
          address: d.address,
          compressed: true,
          source_format: "#{parsed.type_name}:#{full}",
          line: line,
          import_method: :both,
          path: full, # primary label: m/84'/0'/0'/0/0 etc.
          script: d.script
        )
      end
    end

    def normalize_hex_pubkey(input)
      cleaned = input.to_s.strip.delete_prefix("0x").delete_prefix("0X").gsub(/[\s:_-]/, "")
      unless cleaned.match?(/\A[0-9a-fA-F]+\z/)
        raise Error,
              "Unrecognized format. Use hex pubkey (02/03/04…), xpub/ypub/zpub…, or a Bitcoin address (1…/3…/bc1…)."
      end

      case cleaned.length
      when 66
        prefix = cleaned[0, 2].downcase
        raise Error, "Compressed pubkey must start with 02 or 03" unless %w[02 03].include?(prefix)

        Result.new(
          hex: cleaned.downcase,
          address: nil,
          compressed: true,
          source_format: "compressed_hex",
          import_method: :importpubkey,
          path: nil,
          script: nil
        )
      when 130
        prefix = cleaned[0, 2].downcase
        raise Error, "Uncompressed pubkey must start with 04" unless prefix == "04"

        Result.new(
          hex: cleaned.downcase,
          address: nil,
          compressed: false,
          source_format: "uncompressed_hex",
          import_method: :importpubkey,
          path: nil,
          script: nil
        )
      else
        raise Error,
              "Public key hex length must be 66 (compressed) or 130 (uncompressed); got #{cleaned.length}. " \
              "For xpub/zpub paste the full Base58 string (starts with zpub/xpub/…)."
      end
    end

    def extended_like?(str)
      s = str.to_s.strip
      # key may have path suffix
      key = s.split(%r{[\s:/]}).first.to_s
      ExtendedPublicKey.xpub_like?(key) || ExtendedPublicKey::PREFIXES.any? { |p| s.start_with?(p) }
    end

    def address_like?(str)
      s = str.to_s.strip
      return true if s.match?(/\A(bc1|tb1|bcrt1)[0-9a-z]{14,}\z/i)
      return true if s.match?(/\A[13][a-km-zA-HJ-NP-Z1-9]{25,34}\z/)
      return true if s.match?(/\A[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}\z/) # testnet

      false
    end

    def preview(raw)
      raw.length > 24 ? "#{raw[0, 12]}…" : raw
    end
  end
end
