# frozen_string_literal: true

require "test_helper"

class PrivateKeyConverterTest < ActiveSupport::TestCase
  # Avoid loading broken global fixtures for pure service tests
  self.fixture_table_names = []
  self.fixture_class_names = {}

  HEX_ONE = "0000000000000000000000000000000000000000000000000000000000000001"

  test "hex converts to compressed mainnet WIF" do
    r = PrivateKeyConverter.to_wif(HEX_ONE, network: "main", compressed: true)
    assert_equal "hex", r.source_format
    assert r.compressed
    assert_equal "main", r.network
    assert r.wif.start_with?("K", "L")
    assert_equal 52, r.wif.length
  end

  test "hex converts to uncompressed mainnet WIF" do
    r = PrivateKeyConverter.to_wif(HEX_ONE, network: "main", compressed: false)
    assert r.wif.start_with?("5")
    assert_equal 51, r.wif.length
  end

  test "0x prefix and separators accepted" do
    r = PrivateKeyConverter.to_wif("0x#{HEX_ONE}", network: "main", compressed: true)
    assert_equal "hex", r.source_format
    spaced = HEX_ONE.chars.each_slice(2).map(&:join).join(":")
    r2 = PrivateKeyConverter.to_wif(spaced, network: "main")
    assert_equal r.wif, r2.wif
  end

  test "round-trip WIF validates" do
    r = PrivateKeyConverter.to_wif(HEX_ONE, network: "main", compressed: true)
    r2 = PrivateKeyConverter.to_wif(r.wif, network: "main")
    assert_equal "wif", r2.source_format
    assert_equal r.wif, r2.wif
  end

  test "parse_many handles bulk with comments and errors" do
    blob = <<~KEYS
      # header
      #{HEX_ONE}
      not-a-key
      // another comment

      #{HEX_ONE}
    KEYS
    parsed = PrivateKeyConverter.parse_many(blob, network: "main", compressed: true)
    assert_equal 2, parsed[:results].size
    assert_equal 1, parsed[:errors].size
    assert_equal 2, parsed[:results].first.line
    assert_equal 3, parsed[:errors].first.line
  end

  test "rejects zero scalar" do
    assert_raises(PrivateKeyConverter::Error) do
      PrivateKeyConverter.to_wif("0" * 64, network: "main")
    end
  end

  test "rejects mnemonic-like input" do
    words = (%w[abandon] * 12).join(" ")
    err = assert_raises(PrivateKeyConverter::Error) do
      PrivateKeyConverter.to_wif(words, network: "main")
    end
    assert_match(/mnemonic|Seed/i, err.message)
  end

  test "rejects xprv" do
    err = assert_raises(PrivateKeyConverter::Error) do
      PrivateKeyConverter.to_wif(
        "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",
        network: "main"
      )
    end
    assert_match(/Extended|xprv/i, err.message)
  end
end
