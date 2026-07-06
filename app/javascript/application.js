// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { DirectUpload } from "@rails/activestorage"
import "jquery"

// Глобальный массив для хранения blob ID
let uploadedBlobs = []
let pendingUploads = 0
let totalFiles = 0

window.jQuery = window.$ = $

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

// Событие input - при вводе
$(document).on("input.auth", ".auth_input", function() {
  const hasFocus = $(this).is(":focus");

  if (!this.value && !hasFocus) {
    moveLabel($(this), 0);
  }
  else if (this.value) {
    moveLabel($(this), 1);
  }
});

document.addEventListener("turbo:load", function() {
  // Сбрасываем глобальные переменные при загрузке страницы
  uploadedBlobs = []
  pendingUploads = 0
  totalFiles = 0

  $(".auth_input").each(function() {
    if ($(this).val()) {
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

      uploadedBlobs = [] // Очищаем массив blob ID
      pendingUploads = 0
      totalFiles = 0
      $('#upload-progress-container').addClass('hidden')
      $('#upload-progress-bar').css('width', '0%')

      const dataTransfer = new DataTransfer();
      const fileInput = document.getElementById("fileInput");
      // Проверяем добавленные файлы на тип данных
      const existingFiles = fileInput.files;
      const filesToPreview = []
      for (let i = 0; i < existingFiles.length; i++) {
        const isZip = existingFiles[i].name.toLowerCase().endsWith('.zip');
        const isSizeValid = existingFiles[i].size <= 1073741824; // 1 ГБ

        if (isSizeValid) {
          const isValidType = isZip || existingFiles[i].type.startsWith('image/') || existingFiles[i].type.startsWith('video/');
          //Файл подходящего типа
          if (isValidType) {
            dataTransfer.items.add(existingFiles[i]);
            filesToPreview.push(existingFiles[i]);
          }
          else {
            showError("Недопустимый тип файла " + existingFiles[i].name)
          }
        }
        else {
          showError("Недопустимый размер файла " + existingFiles[i].name)
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

  const $mediaForm = $('#media-upload-form') // добавь id форме

  $mediaForm.on('submit', function(e) {
    if (uploadedBlobs.length === 0) {
      e.preventDefault()
      showError("Нет загруженных файлов")
      return
    }
  
    const blobInput = $('<input>', { 
      type: 'hidden', 
      name: 'signed_blob_ids', 
      value: uploadedBlobs.map(b => b.signed_id).join(',') 
    })
    $(this).append(blobInput)
  })

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

      const isZip = newFiles[i].name.toLowerCase().endsWith('.zip');
      const isSizeValid = newFiles[i].size <= 1073741824; // 1 ГБ

      //Файл подходящего размера <= 500МБ
      if (isSizeValid) {
        const isValidType = isZip || newFiles[i].type.startsWith('image/') || newFiles[i].type.startsWith('video/');
         //Файл подходящего типа
        if (isValidType) {
          // Это новый файл, добавляем
          if (!existingFilesMap.has(key)) {
            dataTransfer.items.add(newFiles[i]);
            filesToPreview.push(newFiles[i]);
          }
        }
        else {
          showError("Недопустимый тип файла " + newFiles[i].name)
        }  
      }
      else {
        showError("Недопустимый размер файла " + newFiles[i].name)
      }
    }
    fileInput.files = dataTransfer.files;
    //Показывает preview
    showPreview(filesToPreview);
}

function showPreview(files) {
  totalFiles += files.length  // ← увеличиваем общее количество
  // Показываем прогресс-бар
  $('#upload-progress-container').removeClass('hidden')
  updateProgress()
  Array.from(files).forEach((file) => {
    const isZip = file.name.toLowerCase().endsWith('.zip');
    const isVideo = file.type.startsWith('video/');
    if (isZip) {
      createZipPreview(file)
    }
    else if (isVideo) {
      createVideoPreview(file)
    }
    else {
      createImagePreview(file)
    }
  });
}

function createZipPreview(file) {
  const previewContainer = $("#preview-container")
  const previewWrapper = document.createElement('div');
  previewWrapper.style.position = 'relative';
  previewWrapper.className = 'preview-item'
  
  // Иконка ZIP
  const zipDiv = document.createElement('div');
  zipDiv.className = 'w-full aspect-square bg-purple-50 rounded-lg border-2 border-purple-300 flex flex-col items-center justify-center';
  zipDiv.innerHTML = `
    <span class="text-xs text-[#4e4e4e] mt-2">ZIP архив</span>
    <span class="text-xs text-slate-500">${(file.size / 1024 / 1024).toFixed(2)} МБ</span>
  `;
  
  const readyMark = document.createElement('div');
  readyMark.className = 'absolute top-0 left-0 w-4 h-4 bg-green-500 rounded-full text-white text-xs flex items-center justify-center';
  readyMark.innerHTML = '✓';

  // Кнопка удаления
  const removeBtn = document.createElement('button');
  removeBtn.className = 'absolute -top-3 -right-3 z-10 w-6 h-6 bg-[#8a579f] rounded-full text-white hover:bg-[#69377c]';
  removeBtn.innerHTML = '&times;';
  
  removeBtn.addEventListener('click', async function(e) {
    e.preventDefault();
    e.stopPropagation();
    
    // Удаляем из uploadedBlobs
    const index = uploadedBlobs.findIndex(item => item.filename === file.name);
    if (index !== -1) {
        uploadedBlobs.splice(index, 1);
    }
    previewWrapper.remove();
    
    const fileInput = document.getElementById("fileInput");
    const existingFiles = Array.from(fileInput.files);
    const dataTransfer = new DataTransfer();
    existingFiles.forEach(f => {
      if (f.name !== file.name) {
        dataTransfer.items.add(f);
      }
    });
    fileInput.files = dataTransfer.files;
    
    totalFiles--;
    updateProgress();
    
    if (previewContainer.children().length === 0) {
      previewContainer.removeClass("mt-3")
    }
  });
  
  previewWrapper.appendChild(zipDiv);
  previewWrapper.appendChild(removeBtn);
  previewWrapper.appendChild(readyMark);

  uploadedBlobs.push({
    signed_id: null,
    filename: file.name
  });
  
  if (previewContainer.css("margin-top") == "0px") {
    previewContainer.addClass("mt-3")
  }
  previewContainer.append(previewWrapper);

  updateProgress()
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
    video.currentTime = video.duration * 0.1;
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
    removeBtn.className = 'absolute -top-3 -right-3 z-10 w-6 h-6 bg-[#8a579f] rounded-full text-white hover:bg-[#69377c]';
    removeBtn.innerHTML = '&times;'; // крестик
    //Обработчик нажатия на кнопку удаления
    removeBtn.addEventListener('click', async function(e) {
      e.preventDefault();
      e.stopPropagation();

      // Удаляем blob из storage
      const blobData = uploadedBlobs.find(item => item.filename === file.name)
      if (blobData) {
        const csrfToken = document.querySelector('[name="csrf-token"]').content
      
        const response = await fetch(`/active_storage/blobs/${blobData.signed_id}`, { 
          method: 'DELETE',
          headers: {
            'X-CSRF-Token': csrfToken,
            'Content-Type': 'application/json'
          }
        })
        uploadedBlobs = uploadedBlobs.filter(item => item.filename !== file.name)
      } else if (pendingUploads > 0) {
        // Файл ещё не загрузился → просто уменьшаем счётчик
        pendingUploads--
      }

      totalFiles--
      updateProgress()

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
      startDirectUpload(file, previewWrapper)
    };
};

function startDirectUpload(file, previewWrapper) {
  pendingUploads++
  
  const $submitBtn = $('#submit-btn')
  $submitBtn.prop('disabled', true).val(`Загрузка (${uploadedBlobs.length}/${totalFiles})...`)
  
  const loadingIndicator = document.createElement('div');
  loadingIndicator.className = 'absolute inset-0 bg-black/50 rounded-lg flex items-center justify-center text-white text-xs';
  loadingIndicator.innerHTML = '⏳ Загрузка...';
  previewWrapper.appendChild(loadingIndicator);
  
  const upload = new DirectUpload(file, "/rails/active_storage/direct_uploads")
  
  upload.create((error, blob) => {
    loadingIndicator.remove()

    if (error) {
      showError(`Ошибка загрузки "${file.name}": ${error.message || error}`)
      const errorMark = document.createElement('div')
      errorMark.className = 'absolute top-0 left-0 w-4 h-4 bg-red-500 rounded-full text-white text-xs flex items-center justify-center'
      errorMark.innerHTML = '✗'
      previewWrapper.appendChild(errorMark)
    } else {
      uploadedBlobs.push({ signed_id: blob.signed_id, filename: file.name })
      const successMark = document.createElement('div')
      successMark.className = 'absolute top-0 left-0 w-4 h-4 bg-green-500 rounded-full text-white text-xs flex items-center justify-center'
      successMark.innerHTML = '✓'
      previewWrapper.appendChild(successMark)
    }
    pendingUploads--
    updateProgress()
  })
}

function updateProgress() {
  const completed = uploadedBlobs.length
  const percent = totalFiles === 0 ? 0 : Math.round((completed / totalFiles) * 100)
  
  $('#upload-progress-percent').text(`${percent}%`)
  $('#upload-progress-bar').css('width', `${percent}%`)
  $('#upload-progress-status').text(`Загружено ${completed} из ${totalFiles} файлов`)
  const $submitBtn = $('#newfile-submit-btn')
  if (pendingUploads > 0) {
    $submitBtn.prop('disabled', true).val(`Загрузка (${completed}/${totalFiles})...`)
  } else if (pendingUploads === 0 && totalFiles > 0) {
    $submitBtn.prop('disabled', false).val('Загрузить')
    const status = completed === totalFiles ? '✅ Все файлы загружены!' : `✅ Загружено ${completed} из ${totalFiles} (с ошибками)`
    $('#upload-progress-status').text(status)
  } else if (totalFiles === 0) {
    $submitBtn.prop('disabled', true).val('Загрузить')
    $('#upload-progress-container').addClass('hidden')
  }
}

function showError(message) {
  const errorContainer = $("#error-container")
  if (!errorContainer.length) {
    // Если контейнера нет, создаём временный
    const $temp = $('<div id="error-container"></div>')
    $('body').append($temp)
  }
  
  const errorWrapper = $("<div>", {
    class: "mt-5 px-3 h-16 w-70 border border-red-800 text-red-800 bg-red-200 rounded-lg flex items-center justify-center text-center",
    html: message
  })
  
  $("#error-container").append(errorWrapper)
}

window.addEventListener('popstate', function(event) {
  initializeNavigation();
});

function initializeNavigation () {
  if (!window.navigation) {
    $("#back-button, #forward-button").hide()
    return
  }

  if (window.navigation.canGoBack) {
    $("#back-button").show()
  } else {
    $("#back-button").hide()
  }

  if (window.navigation.canGoForward) {
    $("#forward-button").show()
  } else {
    $("#forward-button").hide()
  }
}
