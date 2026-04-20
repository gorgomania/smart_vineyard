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
    moveLabel($(this), 1);
  });

  // Прыжок label при blur
  $(document).on("blur.auth", ".auth_input", function() {
    if (!this.value) {
      moveLabel($(this), 0);
    }
  });

  // Событие change - при изменении значения
  $(document).on("change.auth", ".auth_input", function() {
    if (!this.value) {
      moveLabel($(this), 0);
    }
    else {
      moveLabel($(this), 1);
    }
  });

  // Событие input - при вводе (мгновенная реакция)
  $(document).on("input.auth", ".auth_input", function() {
    if (!this.value) {
      moveLabel($(this), 0);
    }
    else {
      moveLabel($(this), 1);
    }
  });

  //Обработка выбора файлов через проводник
  $('#fileInput').on('change', function(event) {
      event.preventDefault();
      event.stopPropagation();
      const errorContainer = $("#error-container")
      errorContainer.empty()
      $("#preview-container").empty()
      const dataTransfer = new DataTransfer();
      const fileInput = document.getElementById("fileInput");
      // Проверяем добавленные файлы на тип данных
      const existingFiles = fileInput.files;
      const filesToPreview = []
      for (let i = 0; i < existingFiles.length; i++) {
        //Файл подходящего размера <= 500МБ
        if (existingFiles[i].size <= 524288000) {
          //Файл подходящего типа
          if (existingFiles[i].type.startsWith('image/') || existingFiles[i].type.startsWith('video/')) {
            dataTransfer.items.add(existingFiles[i]);
            filesToPreview.push(existingFiles[i]);
          }
          else {
            const erorrWrapper = $("<div>", {
              class: "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center", 
              html: "Недопустимый тип файла " + existingFiles[i].name + "."
            })
            errorContainer.append(erorrWrapper)
          }
        }
        else {
          const erorrWrapper = $("<div>", {
              class: "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center", 
              html: "Недопустимый размер файла " + existingFiles[i].name + "."
          })
          errorContainer.append(erorrWrapper)
        }
      }
      fileInput.files = dataTransfer.files;
      showPreview(filesToPreview)
  });

  //Объект вошёл в зону броска
  $("#dropZone").on('dragenter dragover', function (event) {
    event.preventDefault();
    event.stopPropagation();
    $(this).addClass("border-purple-500 bg-purple-100")
  });

  //Объект вышёл из зоны броска
  $("#dropZone").on('dragleave', function () {
    $(this).removeClass("border-purple-500 bg-purple-100")
  });

  //Объект бросили в зону
  $("#dropZone").on('drop', function (event) {
    $("#error-container").empty()
    event.preventDefault();
    event.stopPropagation();
    $(this).removeClass("border-purple-500 bg-purple-100")
    const newFiles = event.originalEvent.dataTransfer.files;
    addFilesWithCheckDuplicates(newFiles)
  });

  //Инициализация навигационного меню
  initializeNavigation();

  //Замена меню при ресайзе
  $(window).on('resize', function() {
    handleMenuVisibility();
  });

  //Замена меню при рендере
  handleMenuVisibility()

  //Обработка кликов на иконку бургер-меню -> открытие/закрытие меню
  $('#burgerMenu').on('click', function () {
    const $dropMenu = $("#dropMenu");
    const $overlay = $("#overlay");
    if ($dropMenu.hasClass("hidden")) {
      $dropMenu.removeClass("hidden");
      $overlay.removeClass("hidden").removeClass('opacity-0 invisible pointer-events-none').addClass('opacity-50 visible pointer-events-auto');
    }
    else {
      $dropMenu.addClass("hidden").slideUp(300);
      $overlay.addClass("hidden").addClass('opacity-0 invisible pointer-events-none').removeClass('opacity-50 visible pointer-events-auto');
    }
  });
  
  //Закрытие бургер-меню при клике на оверлей
  $('#overlay').on('click', function () {
    const $dropMenu = $("#dropMenu");
    const $overlay = $("#overlay");
    $dropMenu.addClass("hidden").slideUp(300);
    $overlay.addClass("hidden").addClass('opacity-0 invisible pointer-events-none').removeClass('opacity-50 visible pointer-events-auto');
  });

  //Анимация исчезновения флеша
  setTimeout(function() {
    $('.flash').fadeOut(500, function() {
      $(this).remove();
    });
  }, 3000);
});

function moveLabel($input, move) {
    let $label;
    if ($input.parent().hasClass("field")) {
      $label = $input.prev();
    } else if ($input.parent().prev().hasClass("auth_label")) {
      $label = $input.parent().prev();
    } else {
      $label = $input.parent().prev().children();
    }

    if (!move) {
      $label.animate({ "top": "42px" }, 150).css("font-size", "16px");
    }
    else {
      $label.animate({ "top": "22px" }, 150).css("font-size", "13px");
    }
  }

function handleMenuVisibility() {
    const windowWidth = window.innerWidth;
    if (windowWidth < 1000) {
      $('#desktopMenu').addClass("hidden");
      $('#burgerMenu').removeClass("hidden");
    } else {
      $("#dropMenu").addClass("hidden");
      $("#overlay").addClass("hidden");
      $('#burgerMenu').addClass("hidden");
      $('#desktopMenu').removeClass("hidden");
    }
  }

function addFilesWithCheckDuplicates(newFiles) {
    const dataTransfer = new DataTransfer();
    const fileInput = document.getElementById("fileInput");
    // Получаем текущие файлы
    const existingFiles = fileInput.files;
    // Создаем Map для быстрой проверки дубликатов по имени и размеру
    const existingFilesMap = new Map();
    if (existingFiles) {
      for (let i = 0; i < existingFiles.length; i++) {
          const key = `${existingFiles[i].name}_${existingFiles[i].size}`;
          existingFilesMap.set(key, existingFiles[i]);
      }
    }
    //Добавляем уже существующие файлы из инпут
    if (existingFiles) {
      for (let i = 0; i < existingFiles.length; i++) {
          dataTransfer.items.add(existingFiles[i]);
      }
    }
    // 2. Добавляем только НОВЫЕ файлы (без дубликатов) с проверкой, что файл видео или фото
    const filesToPreview = [];
    for (let i = 0; i < newFiles.length; i++) {
      const key = `${newFiles[i].name}_${newFiles[i].size}`;
      //Файл подходящего размера <= 500МБ
      if (newFiles[i].size <= 524288000) {
         //Файл подходящего типа
        if ((newFiles[i].type.startsWith('image/') || newFiles[i].type.startsWith('video/'))) {
          // Это новый файл, добавляем
          if (!existingFilesMap.has(key)) {
            dataTransfer.items.add(newFiles[i]);
            filesToPreview.push(newFiles[i]);
          }
        }
        else {
          const erorrWrapper = $("<div>", {
            class: "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center", 
            html: "Недопустимый тип файла " + newFiles[i].name
          })
          $("#error-container").append(erorrWrapper)
        }  
      }
      else {
        const erorrWrapper = $("<div>", {
          class: "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center", 
          html: "Недопустимый размер файла " + newFiles[i].name
        })
        $("#error-container").append(erorrWrapper)
      }
    }
    fileInput.files = dataTransfer.files;
    //Показывает preview
    showPreview(filesToPreview);
}

function showPreview(files) {
  Array.from(files).forEach((file) => {
    const isVideo = file.type.startsWith('video/');
    if (isVideo) {
      createVideoPreview(file)
    }
    else {
      createImagePreview(file)
    }
  });
}

function createImagePreview(file) {
  const reader = new FileReader();
  reader.onload = function(e) {
    createPreviewWrapper(e.target.result, file);
  };
  reader.readAsDataURL(file);
}

function createVideoPreview(file) {
  const video = document.createElement('video');
  video.src = URL.createObjectURL(file);
  video.muted = true;
  video.crossOrigin = 'anonymous';
  // Когда видео загрузит метаданные
  video.onloadedmetadata = function() {

    video.currentTime =video.duration * 0.1;
  };
  // Когда видео готово к отрисовке кадра
  video.onseeked = function() {
    // Создаем canvas для извлечения кадра
    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth || 640;
    canvas.height = video.videoHeight || 480;
    
    const ctx = canvas.getContext('2d');
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    
    // Получаем Data URL из canvas
    const url = canvas.toDataURL('image/jpeg');
    // Создаем превью с миниатюрой
    createPreviewWrapper(url, file);
    
    // Очищаем video элемент
    URL.revokeObjectURL(video.src);
    video.src = '';
    video.remove();
  };
}

function createPreviewWrapper(url, file) {
    // Создаём контейнер элемента Preview
    const previewContainer = $("#preview-container")
    const previewWrapper = document.createElement('div');
    previewWrapper.style.position = 'relative';
    // Создаем объект изображения
    const img = new Image();
    img.src = url;
    // Создаем объект кнопки удаления изображения
    const removeBtn = document.createElement('button');
    removeBtn.className = 'absolute -top-3 -right-3 z-10 w-6 h-6 bg-[#8a579f] rounded-full text-white';
    removeBtn.innerHTML = '&times;'; // крестик
    //Обработчик нажатия на кнопку удаления
    removeBtn.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      previewWrapper.remove();
      const fileInput = document.getElementById("fileInput");
      // Получаем текущие файлы
      const existingFiles = fileInput.files;
      const dataTransfer = new DataTransfer();
      if (existingFiles) {
        for (let i = 0; i < existingFiles.length; i++) {
          if (existingFiles[i].name != file.name) {
            dataTransfer.items.add(existingFiles[i]);
          }
        }
      }
      fileInput.files = dataTransfer.files;
      if (previewContainer.children().length == 0) {
        previewContainer.removeClass("mt-3")
      }
    });
    // Добавляем изображение и кнопку в один контейнер
    previewWrapper.appendChild(img);
    previewWrapper.appendChild(removeBtn);
    if (file.type.startsWith('video/')) {
      const video_play_icon = new Image()
      video_play_icon.src = "/video_play_violet.png";
      video_play_icon.className = "w-3 h-3 absolute top-[14.5px] left-[35.5px]"
      previewWrapper.appendChild(video_play_icon);
    }
    // Добавляем обработчики
    img.onload = function() {
      // Добавляем в контейнер для Preview
      if (previewContainer.css("margin-top") == "0px") {
        previewContainer.addClass("mt-3") 
      }
      previewContainer.append(previewWrapper);
    };
};

window.addEventListener('popstate', function(event) {
  initializeNavigation();
});

function initializeNavigation () {
  //Если можно перейти назад по истории
  if (window.navigation.canGoBack) {
    $("#back-button").show()
  }
  else {
    $("#back-button").hide()
  }

  //Если можно перейти вперёд по истории
  if (window.navigation.canGoForward) {
    $("#forward-button").show()
  }
  else {
    $("#forward-button").hide()
  }
}import "controllers"
