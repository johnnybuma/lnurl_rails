// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import './add_jquery'
import './tx_details'

import Highcharts from './highcharts'
window.Highcharts = Highcharts

import * as bootstrap from "bootstrap"

window.bootstrap = bootstrap



let popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'))
let popoverList = popoverTriggerList.map(function (popoverTriggerEl) {
    return new bootstrap.Popover(popoverTriggerEl)
});
import "./channels"


