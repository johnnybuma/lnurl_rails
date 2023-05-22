require "application_system_test_case"

class ChainDataTest < ApplicationSystemTestCase
  setup do
    @chain_datum = chain_data(:one)
  end

  test "visiting the index" do
    visit chain_data_url
    assert_selector "h1", text: "Chain data"
  end

  test "should create chain datum" do
    visit chain_data_url
    click_on "New chain datum"

    click_on "Create Chain datum"

    assert_text "Chain datum was successfully created"
    click_on "Back"
  end

  test "should update Chain datum" do
    visit chain_datum_url(@chain_datum)
    click_on "Edit this chain datum", match: :first

    click_on "Update Chain datum"

    assert_text "Chain datum was successfully updated"
    click_on "Back"
  end

  test "should destroy Chain datum" do
    visit chain_datum_url(@chain_datum)
    click_on "Destroy this chain datum", match: :first

    assert_text "Chain datum was successfully destroyed"
  end
end
