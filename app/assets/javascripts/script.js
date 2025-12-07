//= require jquery

$(document).ready(function() {
    var input_focus = 1, input_hover = 1;
    //Эффект для поля поиска хедера
    $('#search_input').focus(function () {
        $('#search_input').css("background", 'white')
        $('#search_input').css("box-shadow", '0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014')
        input_focus = 0
    })
    //Эффект для поля поиска хедера
    $('#search_input').blur(function () {
        input_focus = 1
        if (input_hover) {
            $('#search_input').css("background", '#f2f2f2')
            $('#search_input').css("box-shadow", 'none')
        }
    })
    //Эффект для поля поиска хедера
    $('#search_input').mouseenter(function () {
        $('#search_input').css("background", 'white')
        $('#search_input').css("box-shadow", '0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014')
        input_hover = 0
    })
    //Эффект для поля поиска хедера
    $('#search_input').mouseleave(function () {
        input_hover = 1
        if (input_focus) {
            $('#search_input').css("background", '#f2f2f2')
            $('#search_input').css("box-shadow", 'none')
        }
    })
    //Эффект для поля поиска хедера
    $('.search_img').mouseenter(function () {
        $('#search_input').css("background", 'white')
        $('#search_input').css("box-shadow", '0 0 0 1px #0000000a,0 4px 4px #0000000a,0 20px 40px #00000014')
    })
    //Опускает футер вниз если страница меньше окна
    if ($("body").height() + $(".header").height() < $(window).height() - 30) {
        $("footer").addClass("fix_footer")
        $(".header").css("padding-right", "91.5px")
    }
})