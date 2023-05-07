$(document).on('turbo:load', function () {


    edit_project = document.querySelector("#edit_project_js")
    edit_project.innerHTML = '<%= j render partial: "projects/edit" %>'
    console.log('Is this working now>?');
});