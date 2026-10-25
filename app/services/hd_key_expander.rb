# frozen_string_literal: true

require "openssl"
require "digest"

# Expand one private key (as BIP32 seed) into multi-standard HD addresses.
#
# PRIMARY first: BIP84  m/84'/coin'/0'/0/0 .. /0/19   (native segwit bc1) × 20
#                BIP49  m/49'/coin'/0'/0/0 .. /0/19   (nested p2sh-p2wpkh) × 20
#                BIP44  m/44'/coin'/0'/0/0 .. /0/19   (legacy 1…)          × 20
# Total: 60 addresses + 60 pubkeys per imported private key.
#
# Optional change chain (1/*) can be requested separately; default is receive-only 60.
class HdKeyExpander
  class Error < StandardError; end

  SECP256K1_ORDER = PrivateKeyConverter::SECP256K1_ORDER
  HARDENED = 0x8000_0000
  ACCOUNT = 0
  GAP_PER_PATH = 20

  # PRIMARY listed first
  STANDARDS = [
    { purpose: 84, script: :p2wpkh, name: "bip84" },
    { purpose: 49, script: :p2sh_p2wpkh, name: "bip49" },
    { purpose: 44, script: :p2pkh, name: "bip44" }
  ].freeze

  TOTAL_RECEIVE = STANDARDS.size * GAP_PER_PATH # 60

  Child = Struct.new(
    :path,           # m/84'/0'/0'/0/0
    :relative_path,  # 0/0
    :purpose,
    :standard,       # bip84 / bip49 / bip44
    :script,
    :change,
    :index,
    :wif,
    :pubkey_hex,
    :address,
    keyword_init: true
  )

  class << self
    def expand_wif(wif, network: "main", gap: GAP_PER_PATH, include_change: false)
      priv = PrivateKeyConverter.wif_to_priv_bytes(wif)
      expand_priv(priv, network: network, gap: gap, include_change: include_change)
    end

    def expand_priv(priv_bytes, network: "main", gap: GAP_PER_PATH, include_change: false)
      raise Error, "Private key must be 32 bytes" unless priv_bytes.bytesize == 32

      coin = coin_type(network)
      master_key, chain_code = master_from_seed(priv_bytes)
      gap = gap.to_i.clamp(1, 200)
      changes = include_change ? [0, 1] : [0]
      children = []

      STANDARDS.each do |std|
        account_key, account_cc = derive_path_priv(
          master_key,
          chain_code,
          [
            std[:purpose] + HARDENED,
            coin + HARDENED,
            ACCOUNT + HARDENED
          ]
        )

        changes.each do |change|
          gap.times do |i|
            child_key, = derive_path_priv(account_key, account_cc, [change, i])
            wif = PrivateKeyConverter.encode_wif(child_key, network: network, compressed: true)
            pub = pubkey_hex_from_priv(child_key)
            addr = ExtendedPublicKey.address_for(pub, script: std[:script], network: network)
            full = "m/#{std[:purpose]}'/#{coin}'/0'/#{change}/#{i}"
            children << Child.new(
              path: full,
              relative_path: "#{change}/#{i}",
              purpose: std[:purpose],
              standard: std[:name],
              script: std[:script],
              change: change,
              index: i,
              wif: wif,
              pubkey_hex: pub,
              address: addr
            )
          end
        end
      end

      children
    end

    def bip84_full_path(relative_path, network: "main")
      coin = coin_type(network)
      "m/84'/#{coin}'/0'/#{relative_path}"
    end

    def coin_type(network)
      case network.to_s
      when "main", "mainnet" then 0
      else 1
      end
    end

    private

    def master_from_seed(seed)
      i = OpenSSL::HMAC.digest("SHA512", "Bitcoin seed", seed)
      key = i.byteslice(0, 32)
      cc = i.byteslice(32, 32)
      n = key.unpack1("H*").to_i(16)
      raise Error, "Invalid master key" if n.zero? || n >= SECP256K1_ORDER

      [key, cc]
    end

    def derive_path_priv(key, chain_code, indices)
      indices.each { |idx| key, chain_code = ckd_priv(key, chain_code, idx) }
      [key, chain_code]
    end

    def ckd_priv(parent_key, parent_cc, index)
      data =
        if index >= HARDENED
          "\x00".b + parent_key + [index].pack("N")
        else
          pubkey_bytes_from_priv(parent_key) + [index].pack("N")
        end
      i = OpenSSL::HMAC.digest("SHA512", parent_cc, data)
      il = i.byteslice(0, 32)
      ir = i.byteslice(32, 32)
      il_int = il.unpack1("H*").to_i(16)
      raise Error, "IL out of range" if il_int >= SECP256K1_ORDER

      parent_int = parent_key.unpack1("H*").to_i(16)
      child_int = (il_int + parent_int) % SECP256K1_ORDER
      raise Error, "Derived zero key" if child_int.zero?

      [[child_int.to_s(16).rjust(64, "0")].pack("H*"), ir]
    end

    def pubkey_hex_from_priv(priv_bytes)
      pubkey_bytes_from_priv(priv_bytes).unpack1("H*")
    end

    def pubkey_bytes_from_priv(priv_bytes)
      group = OpenSSL::PKey::EC::Group.new("secp256k1")
      point = group.generator.mul(OpenSSL::BN.new(priv_bytes.unpack1("H*"), 16))
      raise Error, "Point at infinity" if point.infinity?

      point.to_octet_string(:compressed)
    end
  end
end
