# frozen_string_literal: true

require "digest"
require "strscan"

# Normalize private keys from common formats into mainnet/testnet WIF for
# Bitcoin Core `importprivkey`.
#
# Supported inputs:
# - WIF (Base58Check) — mainnet 5/K/L, testnet 9/c — passed through after validation
# - Raw hex (32 bytes / 64 hex chars), optional 0x prefix, spaces/newlines ignored
# - Hex with trailing compression marker already applied is NOT expected; use +compressed+
# - Raw binary as Base64 of exactly 32 bytes
#
# Not supported (clear error): BIP38, mnemonic/seed phrases, xprv (use descriptor tools).
class PrivateKeyConverter
  class Error < StandardError; end

  BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".freeze

  # secp256k1 curve order (keys must be in 1..n-1)
  SECP256K1_ORDER = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_BAAEDCE6_AF48A03B_BFD25E8C_D0364141

  NETWORK_PREFIX = {
    "main" => 0x80,
    "mainnet" => 0x80,
    "test" => 0xEF,
    "testnet" => 0xEF,
    "regtest" => 0xEF,
    "signet" => 0xEF
  }.freeze

  Result = Struct.new(:wif, :source_format, :compressed, :network, :line, keyword_init: true)
  LineError = Struct.new(:line, :input_preview, :message, keyword_init: true)

  class << self
    # Parse many keys separated by newlines (or blanks). Continues on errors.
    # @return [Hash] { results: [Result], errors: [LineError] }
    def parse_many(text, network: "main", compressed: true)
      results = []
      errors = []
      text.to_s.each_line.with_index(1) do |line, idx|
        raw = line.strip
        next if raw.empty? || raw.start_with?("#", "//")

        begin
          r = to_wif(raw, network: network, compressed: compressed)
          r.line = idx
          results << r
        rescue Error => e
          errors << LineError.new(
            line: idx,
            input_preview: raw.length > 16 ? "#{raw[0, 8]}…#{raw[-4, 4]}" : raw,
            message: e.message
          )
        end
      end
      { results: results, errors: errors }
    end

    # @param input [String]
    # @param network [String] main|test|regtest|signet (default main)
    # @param compressed [Boolean] for hex/raw keys (default true)
    # @return [Result]
    def to_wif(input, network: "main", compressed: true)
      raw = input.to_s.strip
      raise Error, "Private key is blank" if raw.empty?

      network = normalize_network(network)
      compressed = !!compressed

      if wif_like?(raw)
        validate_wif!(raw, network: network)
        return Result.new(wif: raw, source_format: "wif", compressed: wif_compressed?(raw), network: network)
      end

      if (bytes = parse_hex32(raw))
        wif = encode_wif(bytes, network: network, compressed: compressed)
        return Result.new(wif: wif, source_format: "hex", compressed: compressed, network: network)
      end

      if (bytes = parse_base64_32(raw))
        wif = encode_wif(bytes, network: network, compressed: compressed)
        return Result.new(wif: wif, source_format: "base64", compressed: compressed, network: network)
      end

      if looks_like_mnemonic?(raw)
        raise Error, "Seed phrases / mnemonics are not supported here. Derive a hex or WIF private key first."
      end

      if looks_like_xprv?(raw)
        raise Error, "Extended keys (xprv/tprv) are not supported for importprivkey. Export a single WIF/hex key or use descriptors."
      end

      if looks_like_bip38?(raw)
        raise Error, "BIP38 encrypted keys are not supported. Decrypt to WIF/hex first."
      end

      raise Error,
            "Unrecognized private key format. Paste WIF (5…/K…/L…), 64-char hex, or base64 of 32 raw bytes."
    end

    def encode_wif(priv_bytes, network: "main", compressed: true)
      raise Error, "Private key must be exactly 32 bytes" unless priv_bytes.bytesize == 32

      validate_scalar!(priv_bytes)

      prefix = NETWORK_PREFIX.fetch(normalize_network(network))
      payload = +"".b
      payload << prefix
      payload << priv_bytes
      payload << 0x01 if compressed

      checksum = double_sha256(payload)[0, 4]
      base58_encode(payload + checksum)
    end

    def hex_to_wif(hex, network: "main", compressed: true)
      bytes = parse_hex32(hex)
      raise Error, "Expected 64 hex characters (32 bytes)" unless bytes

      encode_wif(bytes, network: network, compressed: compressed)
    end

    # WIF → 32-byte private key
    def wif_to_priv_bytes(wif)
      bytes = base58_decode(wif.to_s.strip)
      raise Error, "Invalid WIF" if bytes.nil? || bytes.bytesize < 5

      payload = bytes[0...-4]
      checksum = bytes[-4..]
      raise Error, "Invalid WIF checksum" unless double_sha256(payload)[0, 4] == checksum

      priv = payload.byteslice(1, 32)
      raise Error, "Invalid WIF payload" unless priv&.bytesize == 32

      priv
    end

    # Compressed secp256k1 public key hex (66 chars) from WIF
    def pubkey_hex_from_wif(wif)
      require "openssl"
      priv = wif_to_priv_bytes(wif)
      group = OpenSSL::PKey::EC::Group.new("secp256k1")
      point = group.generator.mul(OpenSSL::BN.new(priv.unpack1("H*"), 16))
      raise Error, "Invalid public point" if point.infinity?

      point.to_octet_string(:compressed).unpack1("H*")
    end

    private

    def normalize_network(network)
      key = network.to_s.strip.downcase
      return key if NETWORK_PREFIX.key?(key)

      "main"
    end

    def wif_like?(str)
      # Mainnet uncompressed 5…, compressed K/L…; testnet 9… / c…
      str.match?(/\A[5KL9c][1-9A-HJ-NP-Za-km-z]{50,51}\z/)
    end

    def wif_compressed?(wif)
      # Compressed WIF decodes to 34 payload bytes before checksum path; length 52
      wif.length == 52
    end

    def validate_wif!(wif, network:)
      bytes = base58_decode(wif)
      raise Error, "Invalid WIF (decode failed)" if bytes.nil? || bytes.bytesize < 5

      payload = bytes[0...-4]
      checksum = bytes[-4..]
      raise Error, "Invalid WIF checksum" unless double_sha256(payload)[0, 4] == checksum

      version = payload.getbyte(0)
      expected = NETWORK_PREFIX.fetch(normalize_network(network))
      # Allow importing mainnet WIF only on main, testnet WIF on test nets
      if version != expected
        raise Error,
              "WIF network byte 0x#{version.to_s(16)} does not match node network “#{network}” " \
              "(expected 0x#{expected.to_s(16)}). Wrong network key?"
      end

      # payload: version + 32-byte key [+ 0x01]
      key_len = payload.bytesize - 1
      key_len -= 1 if payload.bytesize == 34 && payload.getbyte(-1) == 0x01
      raise Error, "Invalid WIF payload length" unless key_len == 32

      priv = payload.byteslice(1, 32)
      validate_scalar!(priv)
      true
    end

    def parse_hex32(str)
      cleaned = str.to_s.strip
      cleaned = cleaned.delete_prefix("0x").delete_prefix("0X")
      cleaned = cleaned.gsub(/[\s:_-]/, "")
      return nil unless cleaned.match?(/\A[0-9a-fA-F]{64}\z/)

      [cleaned].pack("H*")
    end

    def parse_base64_32(str)
      cleaned = str.to_s.strip.gsub(/\s+/, "")
      return nil unless cleaned.match?(/\A[A-Za-z0-9+\/=]{40,64}\z/)

      begin
        raw = cleaned.unpack1("m0") # strict base64
      rescue ArgumentError
        return nil
      end
      return nil unless raw && raw.bytesize == 32

      raw
    end

    def looks_like_mnemonic?(str)
      words = str.downcase.split
      words.size >= 12 && words.all? { |w| w.match?(/\A[a-z]+\z/) }
    end

    def looks_like_xprv?(str)
      str.start_with?("xprv", "tprv", "yprv", "zprv", "vprv")
    end

    def looks_like_bip38?(str)
      str.start_with?("6P")
    end

    def validate_scalar!(priv_bytes)
      n = priv_bytes.unpack1("H*").to_i(16)
      raise Error, "Private key is out of valid secp256k1 range" if n <= 0 || n >= SECP256K1_ORDER
    end

    def double_sha256(data)
      Digest::SHA256.digest(Digest::SHA256.digest(data))
    end

    def base58_encode(bytes)
      # Count leading zero bytes → leading '1's
      zeros = 0
      bytes.each_byte { |b| b.zero? ? zeros += 1 : break }

      num = bytes.unpack1("H*").to_i(16)
      encoded = +""
      while num.positive?
        num, rem = num.divmod(58)
        encoded.prepend(BASE58_ALPHABET[rem])
      end
      ("1" * zeros) + encoded
    end

    def base58_decode(str)
      num = 0
      str.each_char do |ch|
        idx = BASE58_ALPHABET.index(ch)
        return nil unless idx

        num = num * 58 + idx
      end

      hex = num.to_s(16)
      hex = "0#{hex}" if hex.length.odd?
      raw = [hex].pack("H*")

      # restore leading zeros
      leading = 0
      str.each_char { |ch| ch == "1" ? leading += 1 : break }
      ("\x00" * leading).b + raw
    rescue StandardError
      nil
    end
  end
end
