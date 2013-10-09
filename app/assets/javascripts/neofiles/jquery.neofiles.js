(function($) {

    $.widget("neofiles.image", {

        options: {

        },

        _$transferInput: null,
        _$fileInput: null,
        _$removeButton: null,

        _create: function() {

            var $form = this.element;

            // иницилизация интересующих нас элементов
            this._$transferInput = $form.find(".neofiles-image-transfer-input");
            this._$fileInput = $form.find(".neofiles-image-compact-file");
            this._$removeButton = $form.find(".neofiles-image-compact-remove");

            // повесим аяксовую загрузку файла
            $form.fileupload({

                dropZone: $form,
                pasteZone: $form,

                formData: function() {
                    return $form.find("input, select").serializeArray();
                },

                start: $.proxy(function() {
                    this.loading();
                }, this),

                success: $.proxy(function(response, textStatus, jqXhr) {
                    $form.replaceWith(response);
                    this.destroy();
                }, this),

                error: $.proxy(function() {
                    alert("Ошибка при загрузке файла, попробуйте обновить страницу.\nТакже, проверьте тип файла, загружать можно только картинки.");
                    this.notloading();
                    return false;
                }, this)
            });

            // повесим обработчик кнопки удаления
            this._$removeButton.click($.proxy(function(e) {

                var data = {};

                $.each($form.find("input[type!=file][name^=neofiles], select[name^=neofiles]").serializeArray(), function(i, o) {
                    data[o.name] = o.value;
                });

                this.loading();

                $.ajax(this._$removeButton.is("a") ? this._$removeButton.attr("href") : this._$removeButton.data("url"), {

                    type: "POST",
                    data: data,

                    success: $.proxy(function(response) {
                        $form.replaceWith(response);
                        this.destroy();

                    }, this)
                });

                e.preventDefault();

                $(this._$removeButton).trigger("neofiles.click.remove");

            }, this));

            $form.find(".neofiles-image-compact-upload-icon").click($.proxy(function() {
                this._$fileInput.click();
            }, this));
        },

        imageId: function() {
            return this._$transferInput.val();
        },

        loading: function() {
            this.element[0].className += " neofiles-image-compact-loading";
        },

        notloading: function() {
            this.element[0].className = this.element[0].className.replace(/(^|\s+)neofiles-image-compact-loading/, "");
        }
    });



    $.widget("neofiles.album", {

        options: {},
        limit: null,

        _create: function() {
            var $form = this.element;

            // повесим сортировку на файлы, они сохранятся в том порядке, в котором input:hidden придут в контроллер
            var neofilesImageContainersSelector = ".neofiles-image-compact:not(.neofiles-image-compact-empty)";
            $form.sortable({
                items: neofilesImageContainersSelector
            });

            this.limit = this.options.limit;

            if (this.limit) {

                var limit = this.limit;
                var trigger = function (e) {
                    var ourLimit = (e.data && e.data.limit) || limit;

                    if ($(neofilesImageContainersSelector).length >= ourLimit) {
                        $(".neofiles-image-compact-empty").hide()
                    } else {
                        $(".neofiles-image-compact-empty").show()
                    }
                }

                $("body").on("neofiles.newimage", trigger);
                $("body").on("neofiles.click.remove", {limit: limit + 1}, trigger);
            }
        }

    });

})(window.jQuery);

