require "application_system_test_case"

class EstimateItemsTest < ApplicationSystemTestCase
  setup do
    @estimate_item = estimate_items(:one)
  end

  test "visiting the index" do
    visit estimate_items_url
    assert_selector "h1", text: "Estimate items"
  end

  test "should create estimate item" do
    visit estimate_items_url
    click_on "New estimate item"

    check "Breakout" if @estimate_item.breakout
    fill_in "Category", with: @estimate_item.category
    fill_in "Category order", with: @estimate_item.category_order_id
    fill_in "Cdb rate", with: @estimate_item.cdb_rate
    fill_in "Cdb unit total", with: @estimate_item.cdb_unit_total
    check "Checker" if @estimate_item.checker
    fill_in "Code", with: @estimate_item.code
    fill_in "Duplicator", with: @estimate_item.duplicator
    fill_in "Install labor", with: @estimate_item.install_labor
    fill_in "Install material", with: @estimate_item.install_material
    fill_in "Item", with: @estimate_item.item_id
    fill_in "Item order key", with: @estimate_item.item_order_key
    fill_in "Labor rate", with: @estimate_item.labor_rate
    fill_in "Labor total", with: @estimate_item.labor_total
    fill_in "Lost time rate", with: @estimate_item.lost_time_rate
    fill_in "Markup rate", with: @estimate_item.markup_rate
    fill_in "Markup total", with: @estimate_item.markup_total
    fill_in "Material labor cdb total", with: @estimate_item.material_labor_cdb_total
    fill_in "Material labor total", with: @estimate_item.material_labor_total
    fill_in "Material total", with: @estimate_item.material_total
    fill_in "Name", with: @estimate_item.name
    fill_in "Order", with: @estimate_item.order_id
    fill_in "Overhead rate", with: @estimate_item.overhead_rate
    fill_in "Pricing category", with: @estimate_item.pricing_category
    fill_in "Quantity", with: @estimate_item.quantity
    fill_in "Raw install total", with: @estimate_item.raw_install_total
    fill_in "Raw labor total", with: @estimate_item.raw_labor_total
    fill_in "Raw unit total", with: @estimate_item.raw_unit_total
    check "Selected" if @estimate_item.selected
    fill_in "Tax rate", with: @estimate_item.tax_rate
    fill_in "Tax total", with: @estimate_item.tax_total
    fill_in "Total labor hours", with: @estimate_item.total_labor_hours
    fill_in "Unit price", with: @estimate_item.unit_price
    click_on "Create Estimate item"

    assert_text "Estimate item was successfully created"
    click_on "Back"
  end

  test "should update Estimate item" do
    visit estimate_item_url(@estimate_item)
    click_on "Edit this estimate item", match: :first

    check "Breakout" if @estimate_item.breakout
    fill_in "Category", with: @estimate_item.category
    fill_in "Category order", with: @estimate_item.category_order_id
    fill_in "Cdb rate", with: @estimate_item.cdb_rate
    fill_in "Cdb unit total", with: @estimate_item.cdb_unit_total
    check "Checker" if @estimate_item.checker
    fill_in "Code", with: @estimate_item.code
    fill_in "Duplicator", with: @estimate_item.duplicator
    fill_in "Install labor", with: @estimate_item.install_labor
    fill_in "Install material", with: @estimate_item.install_material
    fill_in "Item", with: @estimate_item.item_id
    fill_in "Item order key", with: @estimate_item.item_order_key
    fill_in "Labor rate", with: @estimate_item.labor_rate
    fill_in "Labor total", with: @estimate_item.labor_total
    fill_in "Lost time rate", with: @estimate_item.lost_time_rate
    fill_in "Markup rate", with: @estimate_item.markup_rate
    fill_in "Markup total", with: @estimate_item.markup_total
    fill_in "Material labor cdb total", with: @estimate_item.material_labor_cdb_total
    fill_in "Material labor total", with: @estimate_item.material_labor_total
    fill_in "Material total", with: @estimate_item.material_total
    fill_in "Name", with: @estimate_item.name
    fill_in "Order", with: @estimate_item.order_id
    fill_in "Overhead rate", with: @estimate_item.overhead_rate
    fill_in "Pricing category", with: @estimate_item.pricing_category
    fill_in "Quantity", with: @estimate_item.quantity
    fill_in "Raw install total", with: @estimate_item.raw_install_total
    fill_in "Raw labor total", with: @estimate_item.raw_labor_total
    fill_in "Raw unit total", with: @estimate_item.raw_unit_total
    check "Selected" if @estimate_item.selected
    fill_in "Tax rate", with: @estimate_item.tax_rate
    fill_in "Tax total", with: @estimate_item.tax_total
    fill_in "Total labor hours", with: @estimate_item.total_labor_hours
    fill_in "Unit price", with: @estimate_item.unit_price
    click_on "Update Estimate item"

    assert_text "Estimate item was successfully updated"
    click_on "Back"
  end

  test "should destroy Estimate item" do
    visit estimate_item_url(@estimate_item)
    click_on "Destroy this estimate item", match: :first

    assert_text "Estimate item was successfully destroyed"
  end
end
