import consumer from "./consumer"

consumer.subscriptions.create("ChainDataChannel", {
    received(data) {
        // Update chain text
        var chain = $('#chain');
        chain.text(data.chain);

        // Update headers text
        var headers = $('#headers');
        headers.text(data.headers);

        // Update bestBlockHash text
        var bestBlockHash = $('#bestblockhash');
        bestBlockHash.text(data.bestblockhash);

        // Update blocks text
        var blocks = $('#blocks');
        blocks.text(data.blocks);

        // Update difficulty text
        var difficulty = $('#difficulty');
        difficulty.text(data.difficulty);

        // Update time text
        var time = $('#time');
        time.text(data.time);

        // Update medianTime text
        var medianTime = $('#mediantime');
        medianTime.text(data.mediantime);

        // Update verificationprogress text and progress bar
        var progressBar = $('#verificationprogress_bar');
        var progressPercent = (data.verificationprogress * 100).toFixed(2);
        progressBar.html('<span>' + progressPercent + '%</span>'); // Set HTML content


        // Update the progress bar's width and aria-valuenow attribute
        var progressBar = $('#verificationprogress_bar');
        if (progressBar.length) {
            progressBar.css('width', progressPercent + '%');
            progressBar.attr('aria-valuenow', progressPercent);
            progressBar.attr('')
        }

        // Flash background effect for verification progress (optional)
        verification_progress.parent().addClass('flash-bg');
        setTimeout(function () {
            verification_progress.parent().removeClass('flash-bg');
        }, 5000);

        // Update initialBlockDownload text
        var initialBlockDownload = $('#initialblockdownload');
        initialBlockDownload.text(data.initialblockdownload);

        // Update chainwork text
        var chainwork = $('#chainwork');
        chainwork.text(data.chainwork);

        // Update sizeOnDisk text
        var sizeOnDisk = $('#size_on_disk');
        sizeOnDisk.text(data.size_on_disk);

        // Update pruned text
        var pruned = $('#pruned');
        pruned.text(data.pruned);

        // Update warnings text
        var warnings = $('#warnings');
        warnings.text(data.warnings);
    }
});
