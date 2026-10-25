# frozen_string_literal: true

# Build scantxoutset descriptors from pasted material WITHOUT touching a wallet
# or Postgres. Supports private keys, hex pubkeys, xpub/ypub/zpub, and addresses.
class UtxoScanBuilder
  class Error < StandardError; end

  Item = Struct.new(
    :line, :kind, :descriptor, :display, :path, :source_format,
    keyword_init: true
  )

  # First 20 of each derivation path (receive 0/* + change 1/*)
  DEFAULT_RECEIVE = 20
  DEFAULT_CHANGE = 20

  class << self
    # @return [Hash] { descriptors: [String], items: [Item], errors: [...] }
    def build(
      text,
      network: "main",
      compressed: true,
      receive_count: DEFAULT_RECEIVE,
      change_count: DEFAULT_CHANGE,
      mode: :auto
    )
      mode = mode.to_sym
      items = []
      errors = []
      seen = {}

      text.to_s.each_line.with_index(1) do |line, idx|
        raw = line.strip
        next if raw.empty? || raw.start_with?("#", "//")

        begin
          expand_line(raw, line: idx, network: network, compressed: compressed,
                      receive_count: receive_count, change_count: change_count, mode: mode).each do |item|
            next if seen[item.descriptor]

            seen[item.descriptor] = true
            items << item
          end
        rescue PrivateKeyConverter::Error, PublicKeyNormalizer::Error, ExtendedPublicKey::Error, Error => e
          errors << { line: idx, preview: preview(raw), message: e.message }
        end
      end

      { descriptors: items.map(&:descriptor), items: items, errors: errors }
    end

    private

    def expand_line(raw, line:, network:, compressed:, receive_count:, change_count:, mode:)
      case mode
      when :private_keys
        return expand_private(raw, line: line, network: network, compressed: compressed)
      when :public_keys
        return expand_public(raw, line: line, receive_count: receive_count, change_count: change_count)
      end

      # :auto — try private first when it looks like a key, else public material
      if looks_private?(raw)
        expand_private(raw, line: line, network: network, compressed: compressed)
      else
        expand_public(raw, line: line, receive_count: receive_count, change_count: change_count)
      end
    rescue PrivateKeyConverter::Error
      # Fall through if auto misclassified
      raise if mode == :private_keys

      expand_public(raw, line: line, receive_count: receive_count, change_count: change_count)
    end

    def looks_private?(raw)
      s = raw.to_s.strip
      return true if s.match?(/\A[5KL9c][1-9A-HJ-NP-Za-km-z]{50,51}\z/)
      return true if s.delete_prefix("0x").delete_prefix("0X").gsub(/[\s:_-]/, "").match?(/\A[0-9a-fA-F]{64}\z/)
      return true if s.match?(/\A[A-Za-z0-9+\/=]{40,64}\z/) && s.bytesize >= 40 && !s.start_with?("xpub", "ypub", "zpub", "tpub", "vpub")
      return true if s.start_with?("xprv", "tprv", "6P") # will error with clear message

      false
    end

    def expand_private(raw, line:, network:, compressed:)
      r = PrivateKeyConverter.to_wif(raw, network: network, compressed: compressed)
      desc = "combo(#{r.wif})"
      [
        Item.new(
          line: line,
          kind: :private_key,
          descriptor: desc,
          display: "combo(#{redact_wif(r.wif)}) [#{r.source_format}]",
          path: nil,
          source_format: r.source_format
        )
      ]
    end

    def expand_public(raw, line:, receive_count:, change_count:)
      # Addresses
      if address_like?(raw)
        return [
          Item.new(
            line: line,
            kind: :address,
            descriptor: "addr(#{raw.strip})",
            display: raw.strip,
            path: nil,
            source_format: "address"
          )
        ]
      end

      # Extended keys → many children
      if ExtendedPublicKey.xpub_like?(raw.split(%r{[\s:/]}).first.to_s) ||
         ExtendedPublicKey::PREFIXES.any? { |p| raw.start_with?(p) }
        results = PublicKeyNormalizer.expand_one(
          raw,
          line: line,
          receive_count: receive_count,
          change_count: change_count
        )
        return results.flat_map { |r| public_result_items(r, line: line) }
      end

      # Hex pubkey
      r = PublicKeyNormalizer.normalize(raw)
      r.line = line
      public_result_items(r, line: line)
    end

    def public_result_items(result, line:)
      items = []
      if result.address.present?
        items << Item.new(
          line: line,
          kind: :watch_address,
          descriptor: "addr(#{result.address})",
          display: result.address,
          path: result.path,
          source_format: result.source_format
        )
      end
      if result.hex.present?
        pub = result.hex
        [
          "pkh(#{pub})",
          "wpkh(#{pub})",
          "sh(wpkh(#{pub}))"
        ].each do |desc|
          items << Item.new(
            line: line,
            kind: :watch_pubkey,
            descriptor: desc,
            display: "#{desc.split("(").first}(#{pub[0, 12]}…)#{result.path.present? ? " #{result.path}" : ""}",
            path: result.path,
            source_format: result.source_format
          )
        end
      end
      raise Error, "Could not build scan descriptors" if items.empty?

      items
    end

    def address_like?(str)
      s = str.to_s.strip
      s.match?(/\A(bc1|tb1|bcrt1)[0-9a-z]{14,}\z/i) ||
        s.match?(/\A[13][a-km-zA-HJ-NP-Z1-9]{25,34}\z/) ||
        s.match?(/\A[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}\z/)
    end

    def redact_wif(wif)
      return "…" if wif.blank?
      return "#{wif[0, 4]}…#{wif[-4, 4]}" if wif.length > 12

      "…"
    end

    def preview(raw)
      raw.length > 24 ? "#{raw[0, 12]}…" : raw
    end
  end
end
