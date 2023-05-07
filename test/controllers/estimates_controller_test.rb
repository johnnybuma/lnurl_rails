require "test_helper"

class EstimatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @estimate = estimates(:one)
  end

  test "should get index" do
    get estimates_url
    assert_response :success
  end

  test "should get new" do
    get new_estimate_url
    assert_response :success
  end

  test "should create estimate" do
    assert_difference("Estimate.count") do
      post estimates_url, params: { estimate: { approved: @estimate.approved, architect: @estimate.architect, cdb_rate: @estimate.cdb_rate, contact_id: @estimate.contact_id, controls_package: @estimate.controls_package, date_submitted: @estimate.date_submitted, engineer: @estimate.engineer, estimate_description: @estimate.estimate_description, estimate_type: @estimate.estimate_type, fixture_package: @estimate.fixture_package, gear_package: @estimate.gear_package, generate: @estimate.generate, labor_lost_time: @estimate.labor_lost_time, labor_overhead: @estimate.labor_overhead, labor_overhead_total: @estimate.labor_overhead_total, labor_rate: @estimate.labor_rate, labor_total: @estimate.labor_total, lost_time_total: @estimate.lost_time_total, markup_rate: @estimate.markup_rate, material_labor_cdb: @estimate.material_labor_cdb, material_labor_cdb_total: @estimate.material_labor_cdb_total, material_labor_total: @estimate.material_labor_total, material_markup_total: @estimate.material_markup_total, material_tax_total: @estimate.material_tax_total, material_total: @estimate.material_total, project_id: @estimate.project_id, raw_labor_total: @estimate.raw_labor_total, raw_material_total: @estimate.raw_material_total, reference_date: @estimate.reference_date, sqft: @estimate.sqft, sqft_cost: @estimate.sqft_cost, tax_rate: @estimate.tax_rate, title: @estimate.title, total_hours: @estimate.total_hours, user_id: @estimate.user_id } }
    end

    assert_redirected_to estimate_url(Estimate.last)
  end

  test "should show estimate" do
    get estimate_url(@estimate)
    assert_response :success
  end

  test "should get edit" do
    get edit_estimate_url(@estimate)
    assert_response :success
  end

  test "should update estimate" do
    patch estimate_url(@estimate), params: { estimate: { approved: @estimate.approved, architect: @estimate.architect, cdb_rate: @estimate.cdb_rate, contact_id: @estimate.contact_id, controls_package: @estimate.controls_package, date_submitted: @estimate.date_submitted, engineer: @estimate.engineer, estimate_description: @estimate.estimate_description, estimate_type: @estimate.estimate_type, fixture_package: @estimate.fixture_package, gear_package: @estimate.gear_package, generate: @estimate.generate, labor_lost_time: @estimate.labor_lost_time, labor_overhead: @estimate.labor_overhead, labor_overhead_total: @estimate.labor_overhead_total, labor_rate: @estimate.labor_rate, labor_total: @estimate.labor_total, lost_time_total: @estimate.lost_time_total, markup_rate: @estimate.markup_rate, material_labor_cdb: @estimate.material_labor_cdb, material_labor_cdb_total: @estimate.material_labor_cdb_total, material_labor_total: @estimate.material_labor_total, material_markup_total: @estimate.material_markup_total, material_tax_total: @estimate.material_tax_total, material_total: @estimate.material_total, project_id: @estimate.project_id, raw_labor_total: @estimate.raw_labor_total, raw_material_total: @estimate.raw_material_total, reference_date: @estimate.reference_date, sqft: @estimate.sqft, sqft_cost: @estimate.sqft_cost, tax_rate: @estimate.tax_rate, title: @estimate.title, total_hours: @estimate.total_hours, user_id: @estimate.user_id } }
    assert_redirected_to estimate_url(@estimate)
  end

  test "should destroy estimate" do
    assert_difference("Estimate.count", -1) do
      delete estimate_url(@estimate)
    end

    assert_redirected_to estimates_url
  end
end
