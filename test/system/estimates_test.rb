require "application_system_test_case"

class EstimatesTest < ApplicationSystemTestCase
  setup do
    @estimate = estimates(:one)
  end

  test "visiting the index" do
    visit estimates_url
    assert_selector "h1", text: "Estimates"
  end

  test "should create estimate" do
    visit estimates_url
    click_on "New estimate"

    check "Approved" if @estimate.approved
    fill_in "Architect", with: @estimate.architect
    fill_in "Cdb rate", with: @estimate.cdb_rate
    fill_in "Contact", with: @estimate.contact_id
    fill_in "Controls package", with: @estimate.controls_package
    fill_in "Date submitted", with: @estimate.date_submitted
    fill_in "Engineer", with: @estimate.engineer
    fill_in "Estimate description", with: @estimate.estimate_description
    fill_in "Estimate type", with: @estimate.estimate_type
    fill_in "Fixture package", with: @estimate.fixture_package
    fill_in "Gear package", with: @estimate.gear_package
    check "Generate" if @estimate.generate
    fill_in "Labor lost time", with: @estimate.labor_lost_time
    fill_in "Labor overhead", with: @estimate.labor_overhead
    fill_in "Labor overhead total", with: @estimate.labor_overhead_total
    fill_in "Labor rate", with: @estimate.labor_rate
    fill_in "Labor total", with: @estimate.labor_total
    fill_in "Lost time total", with: @estimate.lost_time_total
    fill_in "Markup rate", with: @estimate.markup_rate
    fill_in "Material labor cdb", with: @estimate.material_labor_cdb
    fill_in "Material labor cdb total", with: @estimate.material_labor_cdb_total
    fill_in "Material labor total", with: @estimate.material_labor_total
    fill_in "Material markup total", with: @estimate.material_markup_total
    fill_in "Material tax total", with: @estimate.material_tax_total
    fill_in "Material total", with: @estimate.material_total
    fill_in "Project", with: @estimate.project_id
    fill_in "Raw labor total", with: @estimate.raw_labor_total
    fill_in "Raw material total", with: @estimate.raw_material_total
    fill_in "Reference date", with: @estimate.reference_date
    fill_in "Sqft", with: @estimate.sqft
    fill_in "Sqft cost", with: @estimate.sqft_cost
    fill_in "Tax rate", with: @estimate.tax_rate
    fill_in "Title", with: @estimate.title
    fill_in "Total hours", with: @estimate.total_hours
    fill_in "User", with: @estimate.user_id
    click_on "Create Estimate"

    assert_text "Estimate was successfully created"
    click_on "Back"
  end

  test "should update Estimate" do
    visit estimate_url(@estimate)
    click_on "Edit this estimate", match: :first

    check "Approved" if @estimate.approved
    fill_in "Architect", with: @estimate.architect
    fill_in "Cdb rate", with: @estimate.cdb_rate
    fill_in "Contact", with: @estimate.contact_id
    fill_in "Controls package", with: @estimate.controls_package
    fill_in "Date submitted", with: @estimate.date_submitted
    fill_in "Engineer", with: @estimate.engineer
    fill_in "Estimate description", with: @estimate.estimate_description
    fill_in "Estimate type", with: @estimate.estimate_type
    fill_in "Fixture package", with: @estimate.fixture_package
    fill_in "Gear package", with: @estimate.gear_package
    check "Generate" if @estimate.generate
    fill_in "Labor lost time", with: @estimate.labor_lost_time
    fill_in "Labor overhead", with: @estimate.labor_overhead
    fill_in "Labor overhead total", with: @estimate.labor_overhead_total
    fill_in "Labor rate", with: @estimate.labor_rate
    fill_in "Labor total", with: @estimate.labor_total
    fill_in "Lost time total", with: @estimate.lost_time_total
    fill_in "Markup rate", with: @estimate.markup_rate
    fill_in "Material labor cdb", with: @estimate.material_labor_cdb
    fill_in "Material labor cdb total", with: @estimate.material_labor_cdb_total
    fill_in "Material labor total", with: @estimate.material_labor_total
    fill_in "Material markup total", with: @estimate.material_markup_total
    fill_in "Material tax total", with: @estimate.material_tax_total
    fill_in "Material total", with: @estimate.material_total
    fill_in "Project", with: @estimate.project_id
    fill_in "Raw labor total", with: @estimate.raw_labor_total
    fill_in "Raw material total", with: @estimate.raw_material_total
    fill_in "Reference date", with: @estimate.reference_date
    fill_in "Sqft", with: @estimate.sqft
    fill_in "Sqft cost", with: @estimate.sqft_cost
    fill_in "Tax rate", with: @estimate.tax_rate
    fill_in "Title", with: @estimate.title
    fill_in "Total hours", with: @estimate.total_hours
    fill_in "User", with: @estimate.user_id
    click_on "Update Estimate"

    assert_text "Estimate was successfully updated"
    click_on "Back"
  end

  test "should destroy Estimate" do
    visit estimate_url(@estimate)
    click_on "Destroy this estimate", match: :first

    assert_text "Estimate was successfully destroyed"
  end
end
