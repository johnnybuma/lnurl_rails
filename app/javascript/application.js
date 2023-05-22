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



document.addEventListener("turbo:load", (event) => {

    const targetElement = document.getElementById(event.target.id);
    if (targetElement) {
        targetElement.classList.add("flash-bg");
        console.log('the script is working');

        setTimeout(() => {
            targetElement.classList.remove("flash-bg");
        }, 1000);
    }
});


