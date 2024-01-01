// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import './add_jquery'
import './tx_details'

import Highcharts from './highcharts'
window.Highcharts = Highcharts

import * as d3 from "d3";
window.d3 = d3

import c3 from 'c3'
window.c3 = c3

import * as bootstrap from "bootstrap"

window.bootstrap = bootstrap



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


