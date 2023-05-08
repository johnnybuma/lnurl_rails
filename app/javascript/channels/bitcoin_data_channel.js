import { Turbo } from "@hotwired/turbo-rails"
import consumer from "./consumer"

consumer.subscriptions.create("BitcoinDataChannel", {
    received(data) {
        Turbo.renderStreamMessage(data)
    }
})