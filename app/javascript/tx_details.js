// Full-page navigation for transaction detail links (no turbo_frames).

document.addEventListener("click", function (event) {
  var link = event.target.closest("a.view-transaction-link");
  if (!link) return;

  var txId = link.dataset.txId || link.getAttribute("data-tx-id");
  if (!txId) return;

  // Prefer the href when present; otherwise build lookup URL.
  if (link.getAttribute("href") && link.getAttribute("href") !== "#") {
    return; // allow normal / Turbo Drive navigation
  }

  event.preventDefault();
  window.location.href = "/explorer/raw_transaction?tx_id=" + encodeURIComponent(txId);
});
