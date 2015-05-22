$ ->
  $.widget "neofiles.image",
    options: {},

    _$transferInput: null,
    _$fileInput: null,
    _$removeButton: null,
    _$optionsButton: null,

    _savedNowmState: null,
    _savedDescription: null,

    _create: ->

      $form = @element

      @_$transferInput = $form.find(".neofiles-image-transfer-input")
      @_$fileInput = $form.find(".neofiles-image-compact-file")
      @_$removeButton = $form.find(".neofiles-image-compact-remove")
      @_$optionsButton = $form.find(".neofiles-image-compact-options")

      $form.fileupload
        dropZone: $form,
        pasteZone: $form,
        singleFileUploads: false,

        formData: ->
          $form.find("input, select").serializeArray()

        start: =>
          @loading()

        success: (response, textStatus, jqXhr)=>
          $form.replaceWith(response)
          @destroy()

        error: =>
          alert("Ошибка при загрузке файла, попробуйте обновить страницу.\nТакже, проверьте тип файла, загружать можно только картинки.")
          @notloading()
          false

      @_$removeButton.click (e)=>
        e.preventDefault()
        @remove()

      @_$optionsButton.popover().on "shown", =>
        @hideOtherActivePopovers()
        @restoreSavedNowmState()

      @_$optionsButton.click (e)=>
        e.preventDefault()

      $form.find(".neofiles-image-compact-upload-icon").click =>
        @_$fileInput.click()

      $form.on "change", ".neofiles-image-compact-nowm", (e)=>
        @saveNowmState($(e.target))

      $form.on "change", ".neofiles-image-compact-description", (e)=>
        @saveDescription($(e.target))

    imageId: ->
      @_$transferInput.val()

    loading: ->
      @element[0].className += " neofiles-image-compact-loading"

    notloading: ->
      @element[0].className = @element[0].className.replace(/(^|\s+)neofiles-image-compact-loading/, "")

    remove: ->
      @loading()

      data = {}
      @element.find("input[type!=file][name^=neofiles], select[name^=neofiles]").serializeArray().forEach (o)->
        data[o.name] = o.value

      removeUrl = if @_$removeButton.is("a") then @_$removeButton.attr("href") else @_$removeButton.data("url")
      $.ajax removeUrl,
        type: "POST",
        data: data,
        success: (response)=>
          @element.replaceWith(response)
          @destroy()

      @_$removeButton.trigger("neofiles.click.remove")

    hideOtherActivePopovers: ->
      self = @_$optionsButton[0]
      $(".neofiles-image-compact .neofiles-image-compact-options").each ->
        if @ != self
          $(@).popover("hide")

    restoreSavedNowmState: ->
      if @_savedNowmState != null
        @element.find(".neofiles-image-compact-nowm").prop("checked", @_savedNowmState)

    saveNowmState: ($checkbox)->
      $checkbox.prop("disabled", true)
      formData = @element.find("input, select").serializeArray()
      formData.push name: "neofiles[no_wm]", value: if $checkbox.is(":checked") then "1" else "0"

      $.ajax($checkbox.data("update-url"), type: "post", data: formData)
      .done =>
        @_savedNowmState = $checkbox.is(":checked")
      .fail ->
        $checkbox.prop("checked", !$checkbox.is(":checked"))
        alert("Ошибка при сохранении, попробуйте еще раз позднее")
      .always ->
        # ответ приходит быстро, бывает не успеваешь заметить моргание disabled/enabled
        setTimeout ->
          $checkbox.prop("disabled", false)
        , 300


    saveDescription: ($textarea)->
      $textarea.prop("disabled", true)
      formData = @element.find("input, select").serializeArray()
      formData.push name: "neofiles[description]", value: $textarea.val()

      $.ajax($textarea.data("update-url"), type: "post", data: formData)
      .done =>
        @_savedDescription = $textarea.is(":checked")
      .fail ->
        alert("Ошибка при сохранении, попробуйте еще раз позднее")
      .always ->
        # ответ приходит быстро, бывает не успеваешь заметить моргание disabled/enabled
        setTimeout ->
          $textarea.prop("disabled", false)
        , 300



  $.widget "neofiles.album",
    options: {},
    limit: null,

    _create: ->
      $form = @element

      # повесим сортировку на файлы, они сохранятся в том порядке, в котором input:hidden придут в контроллер
      neofilesImageContainersSelector = ".neofiles-image-compact:not(.neofiles-image-compact-empty)"
      $form.sortable
        items: neofilesImageContainersSelector

      @limit = @options.limit

      if @limit
        limit = @limit;
        trigger = (e)->
          ourLimit = (e.data && e.data.limit) || limit
          if $(neofilesImageContainersSelector).length >= ourLimit
            $(".neofiles-image-compact-empty").hide()
          else
            $(".neofiles-image-compact-empty").show()

        $("body").on("neofiles.newimage", trigger)
        $("body").on("neofiles.click.remove", {limit: limit + 1}, trigger)