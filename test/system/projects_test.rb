require "application_system_test_case"

class ProjectsTest < ApplicationSystemTestCase
  setup do
    @project = projects(:one)
  end

  test "visiting the index" do
    visit projects_url
    assert_selector "h1", text: "Projects"
  end

  test "should create project" do
    visit projects_url
    click_on "New project"

    fill_in "Address", with: @project.address
    fill_in "Category", with: @project.category
    fill_in "City", with: @project.city
    fill_in "Contact", with: @project.contact_id
    fill_in "Customer", with: @project.customer_id
    fill_in "State", with: @project.state
    fill_in "Title", with: @project.title
    fill_in "Zip", with: @project.zip
    click_on "Create Project"

    assert_text "Project was successfully created"
    click_on "Back"
  end

  test "should update Project" do
    visit project_url(@project)
    click_on "Edit this project", match: :first

    fill_in "Address", with: @project.address
    fill_in "Category", with: @project.category
    fill_in "City", with: @project.city
    fill_in "Contact", with: @project.contact_id
    fill_in "Customer", with: @project.customer_id
    fill_in "State", with: @project.state
    fill_in "Title", with: @project.title
    fill_in "Zip", with: @project.zip
    click_on "Update Project"

    assert_text "Project was successfully updated"
    click_on "Back"
  end

  test "should destroy Project" do
    visit project_url(@project)
    click_on "Destroy this project", match: :first

    assert_text "Project was successfully destroyed"
  end
end
