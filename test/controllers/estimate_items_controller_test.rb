require "test_helper"

class EstimateItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @estimate_item = estimate_items(:one)
  end

  test "should get index" do
    get estimate_items_url
    assert_response :success
  end

  test "should get new" do
    get new_estimate_item_url
    assert_response :success
  end

  test "should create estimate_item" do
    assert_difference("EstimateItem.count") do
      post estimate_items_url, params: { estimate_item: { breakout: @estimate_item.breakout, category: @estimate_item.category, category_order_id: @estimate_item.category_order_id, cdb_rate: @estimate_item.cdb_rate, cdb_unit_total: @estimate_item.cdb_unit_total, checker: @estimate_item.checker, code: @estimate_item.code, duplicator: @estimate_item.duplicator, install_labor: @estimate_item.install_labor, install_material: @estimate_item.install_material, item_id: @estimate_item.item_id, item_order_key: @estimate_item.item_order_key, labor_rate: @estimate_item.labor_rate, labor_total: @estimate_item.labor_total, lost_time_rate: @estimate_item.lost_time_rate, markup_rate: @estimate_item.markup_rate, markup_total: @estimate_item.markup_total, material_labor_cdb_total: @estimate_item.material_labor_cdb_total, material_labor_total: @estimate_item.material_labor_total, material_total: @estimate_item.material_total, name: @estimate_item.name, order_id: @estimate_item.order_id, overhead_rate: @estimate_item.overhead_rate, pricing_category: @estimate_item.pricing_category, quantity: @estimate_item.quantity, raw_install_total: @estimate_item.raw_install_total, raw_labor_total: @estimate_item.raw_labor_total, raw_unit_total: @estimate_item.raw_unit_total, selected: @estimate_item.selected, tax_rate: @estimate_item.tax_rate, tax_total: @estimate_item.tax_total, total_labor_hours: @estimate_item.total_labor_hours, unit_price: @estimate_item.unit_price } }
    end

    assert_redirected_to estimate_item_url(EstimateItem.last)
  end

  test "should show estimate_item" do
    get estimate_item_url(@estimate_item)
    assert_response :success
  end

  test "should get edit" do
    get edit_estimate_item_url(@estimate_item)
    assert_response :success
  end

  test "should update estimate_item" do
    patch estimate_item_url(@estimate_item), params: { estimate_item: { breakout: @estimate_item.breakout, category: @estimate_item.category, category_order_id: @estimate_item.category_order_id, cdb_rate: @estimate_item.cdb_rate, cdb_unit_total: @estimate_item.cdb_unit_total, checker: @estimate_item.checker, code: @estimate_item.code, duplicator: @estimate_item.duplicator, install_labor: @estimate_item.install_labor, install_material: @estimate_item.install_material, item_id: @estimate_item.item_id, item_order_key: @estimate_item.item_order_key, labor_rate: @estimate_item.labor_rate, labor_total: @estimate_item.labor_total, lost_time_rate: @estimate_item.lost_time_rate, markup_rate: @estimate_item.markup_rate, markup_total: @estimate_item.markup_total, material_labor_cdb_total: @estimate_item.material_labor_cdb_total, material_labor_total: @estimate_item.material_labor_total, material_total: @estimate_item.material_total, name: @estimate_item.name, order_id: @estimate_item.order_id, overhead_rate: @estimate_item.overhead_rate, pricing_category: @estimate_item.pricing_category, quantity: @estimate_item.quantity, raw_install_total: @estimate_item.raw_install_total, raw_labor_total: @estimate_item.raw_labor_total, raw_unit_total: @estimate_item.raw_unit_total, selected: @estimate_item.selected, tax_rate: @estimate_item.tax_rate, tax_total: @estimate_item.tax_total, total_labor_hours: @estimate_item.total_labor_hours, unit_price: @estimate_item.unit_price } }
    assert_redirected_to estimate_item_url(@estimate_item)
  end

  test "should destroy estimate_item" do
    assert_difference("EstimateItem.count", -1) do
      delete estimate_item_url(@estimate_item)
    end

    assert_redirected_to estimate_items_url
  end
end
