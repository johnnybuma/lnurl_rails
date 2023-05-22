import { Turbo } from "@hotwired/turbo-rails"
import consumer from "./consumer"

consumer.subscriptions.create("ChainDataChannel", {
    received(data) {
        //Turbo.renderStreamMessage(data)
        //console.log('client subscribed to chain data channel...');
        //console.log(data);


        var chain = $('#chain');
        chain.text(data.chain);
        var headers = $('#headers');
        headers.text(data.headers);
        var bestBlockHash = $('#bestblockhash');
        bestBlockHash.text(data.bestblockhash);
        var blocks = $('#blocks');
        blocks.text(data.blocks)
        var difficulty = $('#difficulty');
        difficulty.text(data.difficulty);
        var time = $('#time');
        time.text(data.time);
        var medianTime = $('#mediantime');
        medianTime.text(data.mediantime);
        var verification_progress = $("#verificationprogress");
        verification_progress.text(data.verificationprogress);
        verification_progress.parent().addClass('flash-bg');
        setTimeout(function () {
            verification_progress.parent().removeClass('flash-bg');
        }, 5000);
        var initialBlockDownload = $('#initialblockdownload');
        initialBlockDownload.text(data.initialblockdownload);
        var chainwork = $('#chainwork');
        chainwork.text(data.chainwork);
        var sizeOnDisk = $('#size_on_disk');
        sizeOnDisk.text(data.size_on_disk);
        var pruned = $('#pruned');
        pruned.text(data.pruned);
        var warnings = $('#warnings');
        warnings.text(data.warnings);



    }
})