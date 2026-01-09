// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "jquery"

window.jQuery = window.$ = $

document.addEventListener("turbo:load", function() {
  var input_focus = 1, input_hover = 1;
  // Эффект focus для поля поиска
  $(document).on("focus.search", ".search_input", function() {
    $(this).css({
      "background": "white",
      "box-shadow": "0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014"
    });
    input_focus = 0;
  });

  // Эффект blur для поля поиска
  $(document).on("blur.search", ".search_input", function() {
    input_focus = 1;
    if (input_hover) {
      $(this).css({
        "background": "#f2f2f2",
        "box-shadow": "none"
      });
    }
  });

  // Эффект mouseenter для поля поиска
  $(document).on("mouseenter.search", ".search_input", function() {
    $(this).css({
      "background": "white", 
      "box-shadow": "0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014"
    });
    input_hover = 0;
  });

  // Эффект mouseleave для поля поиска
  $(document).on("mouseleave.search", ".search_input", function() {
    input_hover = 1;
    if (input_focus) {
      $(this).css({
        "background": "#f2f2f2",
        "box-shadow": "none"
      });
    }
  });

  // Эффект mouseenter для иконки поиска
  $(document).on("mouseenter.searchimg", ".search_img", function() {
    $(".search_input").css({
      "background": "white",
      "box-shadow": "0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014"
    });
  });

  // Прыжок label при focus
  $(document).on("focus.auth", ".auth_input", function() {
    let $label;
    
    if ($(this).parent().hasClass("field")) {
      $label = $(this).prev();
    } else if ($(this).parent().prev().hasClass("auth_label")) {
      $label = $(this).parent().prev();
    } else {
      $label = $(this).parent().prev().children();
    }
    
    $label.animate({ "top": "22px" }, 250).css("font-size", "13px");
  });

  // Прыжок label при blur
  $(document).on("blur.auth", ".auth_input", function() {
    if (!this.value) {
      let $label;
      
      if ($(this).parent().hasClass("field")) {
        $label = $(this).prev();
      } else if ($(this).parent().prev().hasClass("auth_label")) {
        $label = $(this).parent().prev();
      } else {
        $label = $(this).parent().prev().children();
      }
      
      $label.animate({ "top": "42px" }, 250).css("font-size", "16px");
    }
  });

  fixFooterPosition();

  // При ресайзе окна
  $(window).off("resize.footer").on("resize.footer", fixFooterPosition);
});

function fixFooterPosition() {
  if ($("body").height() + $("header").height() < $(window).height() - 30) {
    $("footer").addClass("fix_footer");
    $("header").css("padding-right", "91.5px");
  } else {
    $("footer").removeClass("fix_footer");
    $("header").css("padding-right", "");
  }
}