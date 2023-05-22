require "test_helper"

class ChainDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chain_datum = chain_data(:one)
  end

  test "should get index" do
    get chain_data_url
    assert_response :success
  end

  test "should get new" do
    get new_chain_datum_url
    assert_response :success
  end

  test "should create chain_datum" do
    assert_difference("ChainDatum.count") do
      post chain_data_url, params: { chain_datum: {  } }
    end

    assert_redirected_to chain_datum_url(ChainDatum.last)
  end

  test "should show chain_datum" do
    get chain_datum_url(@chain_datum)
    assert_response :success
  end

  test "should get edit" do
    get edit_chain_datum_url(@chain_datum)
    assert_response :success
  end

  test "should update chain_datum" do
    patch chain_datum_url(@chain_datum), params: { chain_datum: {  } }
    assert_redirected_to chain_datum_url(@chain_datum)
  end

  test "should destroy chain_datum" do
    assert_difference("ChainDatum.count", -1) do
      delete chain_datum_url(@chain_datum)
    end

    assert_redirected_to chain_data_url
  end
end
