$(document).on('ready load turbo:frame-load',function() {
    $(document).on('click', '.view-transaction-link', function(event) {

        event.preventDefault();
        event.stopPropagation(); // Add this line to stop event propagation


        var txId = $(this).data('txId');
        var url = `/block_histories/transactions/${txId}`; // Updated URL

        // Fetch and display the transaction details
        $.ajax({
            url: url,
            type: 'GET',
            success: function(response) {
                var content = $(response).find('#raw_transaction_details_wrapper').html();
                $('#testTxDetails').html(content);
            },
            error: function(error) {
                console.error('Error:', error);
            }
        });
    });
});
