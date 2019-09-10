"use strict";
exports.__esModule = true;
var $ = require("jquery");
var setupCarousel = function (previousButton, nextButton, elements) {
    // TODO: dynamically compute the number of pages
    // TODO: implement animations
    var numberOfElements = elements.length;
    var numberOfElementsPerPage = 3;
    var numberOfPages = Math.ceil(numberOfElements / numberOfElementsPerPage);
    var displayPage = function (pageNumber) {
        elements.hide();
        var indexOfFirstElement = pageNumber * numberOfElementsPerPage;
        for (var i = 0; i < numberOfElementsPerPage; ++i) {
            var indexOfCurrentElement = indexOfFirstElement + i;
            if (indexOfCurrentElement < numberOfElements) {
                $(elements[indexOfCurrentElement]).show();
            }
        }
    };
    displayPage(0);
    var currentPage = 0;
    previousButton.click(function () {
        currentPage += numberOfPages;
        currentPage -= 1;
        currentPage %= numberOfPages;
        displayPage(currentPage);
    });
    nextButton.click(function () {
        currentPage += 1;
        currentPage %= numberOfPages;
        displayPage(currentPage);
    });
};
$(document).ready(function () {
    setupCarousel($(".courses .previous"), $(".courses .next"), $(".courses .course"));
    setupCarousel($(".decks .previous"), $(".decks .next"), $(".decks .deck"));
});
