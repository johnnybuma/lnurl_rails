# frozen_string_literal: true

require "openssl"
require "digest"

# BIP32 / SLIP-0132 extended public keys → child compressed pubkeys + script addresses.
#
# Accepts: xpub ypub zpub Ypub Zpub tpub upub vpub Vpub Upub (and raw version-agnostic payloads).
class ExtendedPublicKey
  class Error < StandardError; end

  BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".freeze
  SECP256K1_ORDER = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_BAAEDCE6_AF48A03B_BFD25E8C_D0364141
  HARDENED = 0x80000000

  # SLIP-0132 version → { network:, script: }
  # script: :p2pkh | :p2sh_p2wpkh | :p2wpkh | :p2wsh | :p2sh_p2wsh | :unknown
  VERSION_MAP = {
    0x0488_B21E => { network: "main", script: :p2pkh, name: "xpub" },       # also used loosely for multi
    0x049D_7CB2 => { network: "main", script: :p2sh_p2wpkh, name: "ypub" },
    0x04B2_4746 => { network: "main", script: :p2wpkh, name: "zpub" },
    0x0295_B43F => { network: "main", script: :p2sh_p2wsh, name: "Ypub" },
    0x02AA_7ED3 => { network: "main", script: :p2wsh, name: "Zpub" },
    0x0435_87CF => { network: "test", script: :p2pkh, name: "tpub" },
    0x044A_5262 => { network: "test", script: :p2sh_p2wpkh, name: "upub" },
    0x045F_1CF6 => { network: "test", script: :p2wpkh, name: "vpub" },
    0x0242_89EF => { network: "test", script: :p2sh_p2wsh, name: "Upub" },
    0x0257_54CD => { network: "test", script: :p2wsh, name: "Vpub" }
  }.freeze

  PREFIXES = %w[xpub ypub zpub Ypub Zpub tpub upub vpub Upub Vpub].freeze

  Parsed = Struct.new(
    :version, :depth, :fingerprint, :child_number, :chain_code, :pubkey,
    :network, :script, :type_name, :raw_b58, keyword_init: true
  )

  Derived = Struct.new(:path, :pubkey_hex, :address, :script, :network, keyword_init: true)

  class << self
    def xpub_like?(str)
      s = str.to_s.strip
      return false if s.empty?

      PREFIXES.any? { |p| s.start_with?(p) } && s.match?(/\A[1-9A-HJ-NP-Za-km-z]{100,120}\z/)
    end

    def parse(b58)
      raw = b58.to_s.strip
      # optional path suffix: "zpub.../0/0" or "zpub... 0/0"
      key_part, path_part = split_key_and_path(raw)
      bytes = base58check_decode(key_part)
      raise Error, "Invalid extended key length (#{bytes.bytesize})" unless bytes.bytesize == 78

      version = bytes.byteslice(0, 4).unpack1("N")
      meta = VERSION_MAP[version] || { network: "main", script: :unknown, name: "xpub?" }
      depth = bytes.getbyte(4)
      fingerprint = bytes.byteslice(5, 4)
      child_number = bytes.byteslice(9, 4).unpack1("N")
      chain_code = bytes.byteslice(13, 32)
      pubkey = bytes.byteslice(45, 33)
      raise Error, "Extended key must contain a compressed public key" unless [2, 3].include?(pubkey.getbyte(0))

      parsed = Parsed.new(
        version: version,
        depth: depth,
        fingerprint: fingerprint,
        child_number: child_number,
        chain_code: chain_code,
        pubkey: pubkey,
        network: meta[:network],
        script: meta[:script],
        type_name: meta[:name],
        raw_b58: key_part
      )
      [parsed, path_part]
    end

    # Expand account-level zpub/xpub into BIP84-style children.
    # Primary receive: 0/0  → full path m/84'/coin'/0'/0/0
    # Receive: 0/0..0/(n-1)  Change: 1/0..1/(m-1)
    def expand(b58, receive_count: 20, change_count: 20, paths: nil, branches: [0, 1])
      parsed, embedded_path = parse(b58)
      list = []

      explicit_paths = paths.nil? || (paths.respond_to?(:empty?) && paths.empty?) ? nil : paths
      if explicit_paths || (embedded_path && !embedded_path.to_s.empty?)
        path_list = Array(explicit_paths || embedded_path)
        path_list.each do |p|
          list << derive_path(parsed, p)
        end
      else
        # BIP84: only external (0) + change (1) — primary is 0/0
        gap0 = receive_count.to_i.clamp(0, 500)
        gap1 = change_count.to_i.clamp(0, 500)
        gap0.times { |i| list << derive_path(parsed, "0/#{i}") }
        gap1.times { |i| list << derive_path(parsed, "1/#{i}") }
      end

      list
    end

    def derive_path(parsed, path_str)
      indices = parse_path(path_str)
      node_pub = parsed.pubkey
      node_cc = parsed.chain_code
      indices.each do |i|
        raise Error, "Hardened derivation is not possible from a public key (index #{i})" if i >= HARDENED

        node_pub, node_cc = ckd_pub(node_pub, node_cc, i)
      end
      hex = node_pub.unpack1("H*")
      addr = address_for(hex, script: parsed.script, network: parsed.network)
      Derived.new(
        path: path_str.to_s.sub(%r{\A/*}, ""),
        pubkey_hex: hex,
        address: addr,
        script: parsed.script,
        network: parsed.network
      )
    end

    def address_for(pubkey_hex, script:, network: "main")
      pub = [pubkey_hex].pack("H*")
      h160 = hash160(pub)
      case script
      when :p2pkh
        base58check_encode(network == "main" ? "\x00" : "\x6f", h160)
      when :p2sh_p2wpkh
        redeem = "\x00\x14".b + h160
        base58check_encode(network == "main" ? "\x05" : "\xc4", hash160(redeem))
      when :p2wpkh
        encode_bech32(network, 0, h160.bytes)
      when :p2wsh, :p2sh_p2wsh
        # Without a script we can only watch the key as P2WPKH-style pubkey import;
        # still expose a p2wpkh address so funds to single-key wrapped forms are useful.
        encode_bech32(network, 0, h160.bytes)
      else
        # Unknown version: prefer native segwit address as best-effort watch target
        encode_bech32(network == "test" ? "test" : "main", 0, h160.bytes)
      end
    end

    private

    def split_key_and_path(raw)
      if (m = raw.match(%r{\A([1-9A-HJ-NP-Za-km-z]{100,120})(?:[\s:]+|/)(\d[\d'/hH/]*)\z}))
        return [m[1], m[2].tr("hH", "''")]
      end
      [raw, nil]
    end

    def parse_path(path_str)
      s = path_str.to_s.strip.sub(%r{\Am(/)?}i, "").sub(%r{\A/*}, "")
      return [] if s.empty?

      s.split("/").map do |part|
        hardened = part.end_with?("'", "h", "H")
        n = part.delete("'hH").to_i
        raise Error, "Invalid path component #{part.inspect}" if n.negative?

        hardened ? (n + HARDENED) : n
      end
    end

    def ckd_pub(parent_pub, parent_cc, index)
      data = parent_pub + [index].pack("N")
      i = OpenSSL::HMAC.digest("SHA512", parent_cc, data)
      il = i.byteslice(0, 32)
      ir = i.byteslice(32, 32)
      il_int = il.unpack1("H*").to_i(16)
      raise Error, "Derived IL out of range" if il_int >= SECP256K1_ORDER || il_int.zero?

      group = OpenSSL::PKey::EC::Group.new("secp256k1")
      parent_point = OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(parent_pub.unpack1("H*"), 16))
      child_point = group.generator.mul(OpenSSL::BN.new(il_int)).add(parent_point)
      raise Error, "Derived point at infinity" if child_point.infinity?

      [child_point.to_octet_string(:compressed), ir]
    end

    def hash160(data)
      Digest::RMD160.digest(Digest::SHA256.digest(data))
    end

    def encode_bech32(network, ver, prog_bytes)
      require "bech32"
      require "bech32/segwit_addr"
      hrp =
        case network.to_s
        when "main", "mainnet" then Bech32::SegwitAddr::HRP_MAINNET
        when "regtest" then Bech32::SegwitAddr::HRP_REGTEST
        else Bech32::SegwitAddr::HRP_TESTNET
        end
      addr = Bech32::SegwitAddr.new
      addr.hrp = hrp
      addr.ver = ver
      addr.prog = prog_bytes
      addr.addr
    end

    def base58check_decode(str)
      num = 0
      str.each_char do |ch|
        idx = BASE58_ALPHABET.index(ch)
        raise Error, "Invalid Base58 character in extended key" unless idx

        num = num * 58 + idx
      end
      hex = num.to_s(16)
      hex = "0#{hex}" if hex.length.odd?
      raw = [hex].pack("H*")
      leading = 0
      str.each_char { |c| c == "1" ? leading += 1 : break }
      bytes = ("\x00" * leading).b + raw
      raise Error, "Extended key too short" if bytes.bytesize < 5

      payload = bytes[0...-4]
      checksum = bytes[-4..]
      unless Digest::SHA256.digest(Digest::SHA256.digest(payload))[0, 4] == checksum
        raise Error, "Invalid extended key checksum (typo?)"
      end

      payload
    end

    def base58check_encode(version_byte, payload)
      data = version_byte.b + payload.b
      checksum = Digest::SHA256.digest(Digest::SHA256.digest(data))[0, 4]
      bytes = data + checksum
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
  end
end
