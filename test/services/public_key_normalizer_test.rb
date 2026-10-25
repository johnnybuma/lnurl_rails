# frozen_string_literal: true

require "test_helper"

class PublicKeyNormalizerTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.fixture_class_names = {}

  COMPRESSED = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  UNCOMPRESSED = "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
  # User-reported zpub (mainnet BIP84 account)
  ZPUB = "zpub6qNsLh48fePkPsv6MKYBoH2GGgghdt9LZJvz6tafbXYKKVRbezgizx7iMnDKECSvbg33MMjT5F6iV9gVkVVH7H2tRJ2jbrBTuFNwnCLVqZe"

  test "normalizes compressed hex" do
    r = PublicKeyNormalizer.normalize(COMPRESSED)
    assert r.compressed
    assert_equal "compressed_hex", r.source_format
    assert_equal COMPRESSED, r.hex
  end

  test "normalizes uncompressed hex" do
    r = PublicKeyNormalizer.normalize(UNCOMPRESSED)
    assert_not r.compressed
    assert_equal "uncompressed_hex", r.source_format
  end

  test "accepts 0x and separators" do
    r = PublicKeyNormalizer.normalize("0x#{COMPRESSED.upcase}")
    assert_equal COMPRESSED, r.hex
  end

  test "rejects wrong length hex" do
    assert_raises(PublicKeyNormalizer::Error) do
      PublicKeyNormalizer.normalize("02" + ("ab" * 20))
    end
  end

  test "zpub expands to receive and change addresses" do
    parsed = PublicKeyNormalizer.parse_many(ZPUB, receive_count: 3, change_count: 1)
    assert_empty parsed[:errors], parsed[:errors].inspect
    assert_equal 4, parsed[:results].size
    first = parsed[:results].first
    assert_equal "0/0", first.path
    assert first.address.start_with?("bc1"), first.address
    assert_equal 66, first.hex.length
    assert_equal :both, first.import_method
    assert_includes parsed[:results].map(&:path), "1/0"
  end

  test "zpub with explicit path" do
    parsed = PublicKeyNormalizer.parse_many("#{ZPUB}/0/0")
    assert_equal 1, parsed[:results].size
    assert_equal "0/0", parsed[:results].first.path
    assert_equal "bc1qujc4uzpjccj4all7937yaq2xfuwe73v559fxx6", parsed[:results].first.address
  end

  test "address line uses importaddress" do
    parsed = PublicKeyNormalizer.parse_many("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    assert_equal 1, parsed[:results].size
    assert_equal :importaddress, parsed[:results].first.import_method
  end

  test "parse_many with comments and mixed formats" do
    blob = <<~KEYS
      # comment
      #{COMPRESSED}
      deadbeef
      #{ZPUB}/0/1
    KEYS
    parsed = PublicKeyNormalizer.parse_many(blob)
    assert_equal 2, parsed[:results].size
    assert_equal 1, parsed[:errors].size
    assert parsed[:results].first.compressed
    assert_equal "0/1", parsed[:results].last.path
  end
end
