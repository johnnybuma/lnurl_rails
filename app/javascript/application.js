// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import './add_jquery'

import * as bootstrap from "bootstrap"

let popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'))
let popoverList = popoverTriggerList.map(function (popoverTriggerEl) {
    return new bootstrap.Popover(popoverTriggerEl)
});
import "./channels"


document.addEventListener('turbo:frame-load', function () {

    const form = document.getElementById('message-form');
    console.log(form);
    if (form) {
        form.addEventListener('submit', function handleSubmit(event) {
            event.preventDefault();
            // 👇️ Send data to server here
            form.submit();
            // 👇️ Reset form here
            form.reset();
            console.log("form was reset!");
        });
    }

    function drag(ev) {
        ev.dataTransfer.setData("text", ev.target.id);
    }

    function drop(ev) {
        ev.preventDefault();
        var data = ev.dataTransfer.getData("text");
        ev.target.appendChild(document.getElementById(data));
    }

});
