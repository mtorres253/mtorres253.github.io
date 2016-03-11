jQuery(function() {
  // Initalize lunr with the fields it will be searching on. I've given title
  // a boost of 10 to indicate matches on this field are more important.
  window.idx = lunr(function () {
    this.field('id');
    this.field('title', { boost: 10 });
    this.field('description');
    this.field('content');
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

      // Are there any results?
      if (results.length) {
        // Clear any old results
        $container.append("<p>There are " + results.length + " results:</p>");
        // Iterate over the results
        results.forEach(function(result) {
          var item = loaded_data[result.ref];

          // Build a snippet of HTML for this result
          var appendString = '<p><a href="' + item.url + '">' + item.title + '</a></p>';

          // Add it to the results
          $container.append(appendString);
        });
      } else {
        $search_results.html('<p>No results found</p>');
      }
    });
  }
});