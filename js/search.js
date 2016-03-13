jQuery(function() {
  // Initalize lunr with the fields it will be searching on. I've given title
  // a boost of 10 to indicate matches on this field are more important.
  window.idx = lunr(function () {
    this.field('id');
    this.field('title');
    this.field('content', { boost: 10 });
    this.field('url');
  });

  // Download the data from the JSON file we generated
  window.data = $.getJSON('/search_data.json');

  // Wait for the data to load and add it to lunr
  window.data.then(function(loaded_data){
    $.each(loaded_data, function(index, value){
      window.idx.add(
        $.extend({ "id": index }, value)
      );
    });
  });

  // Event when the form is submitted
  $("#site_search").submit(function(){
      event.preventDefault();
      var query = $("#search_box").val(); // Get the value for the text field
      var results = window.idx.search(query); // Get lunr to perform a search
      display_search_results(results); // Hand the results off to be displayed
  });

  function display_search_results(results) {
    var $container = $("#container");

    // Wait for data to load
    window.data.then(function(loaded_data) {
      $container.empty();
      $container.addClass( "search_results" );
      var query = $("#search_box").val();

      // Are there any results?
      if (results.length) {
        // Clear any old results
        
        $container.append("<h2>There are " + results.length + " results for '" + query + "':</h2>");
        // Iterate over the results
        results.forEach(function(result) {
          var item = loaded_data[result.ref];

          // Build a snippet of HTML for this result
          var appendString = '<p><a href="' + item.url + '">' + item.title + '</a></p>';

          // Add it to the results
          $container.append(appendString);
        });
      } else {
        $container.html("<h2>No results found for '" + query + "'.</h2>");
      }
    });
  }
});