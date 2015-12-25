# Помогайки (view helpers) для работы с файлами (neofiles).
module Neofiles::NeofilesHelper

  # Возвращает строку с тэгом IMG для картинки image_file (это может быть ID или объект Neofiles::Image).
  # Если передать width, height и resize_options, картинка будет смасштабирована соответственно, формат см.
  # Neofiles::ImagesController#show.
  # html_attrs - HTML-атрибуты тэга.
  def neofiles_img_tag(image_file, width = nil, height = nil, resize_options = {}, html_attrs = {})

    unless image_file.blank?
      resize_options = resize_options.merge(format: [width.to_i, height.to_i].join("x")) if width.to_i > 0 && height.to_i > 0
      size_attrs = resize_options.key?(:size_attrs) ? resize_options[:size_attrs] : true

      html_attrs.symbolize_keys!
      html_attrs[:src] = neofiles_image_url(image_file, resize_options)

      html_attrs[:width], html_attrs[:height] = dimensions_after_resize(image_file, width.to_i, height.to_i, resize_options) if size_attrs
    end

    tag :img, html_attrs
  end

  # Возвращает строку с тэгом A и IMG для картинки, см. #neofiles_img_tag
  # link_attrs, img_attrs - ХТМЛ-свойства тэгов A и IMG соотв.
  def neofiles_img_link(image_file, width = nil, height = nil, resize_options = {}, link_attrs = {}, img_attrs = {})
    link_attrs[:href] = neofiles_image_url image_file unless link_attrs[:href]
    neofiles_link(image_file, neofiles_img_tag(image_file, width, height, resize_options, img_attrs), link_attrs)
  end

  # Возвращает строку с тэгом A с путем до файла file (ID или объект Neofiles::File).
  # tag_content будет сформирован автоматом, если не передан.
  def neofiles_link(file, tag_content = nil, html_attrs = {})
    html_attrs[:href] = neofiles_file_url file unless html_attrs[:href]
    content_tag(:a, tag_content.presence || file.description.presence || file.filename, html_attrs)
  end

  def swf_embed(id, url, width, height, bgcolor, click_tag, alt = '')
    url = h(url)
    click_tag = h(click_tag)

    result = <<HTML
      <object classid="clsid:D27CDB6E-AE6D-11cf-96B8-444553540000" width="#{width}" height="#{height}" id="#{id}">
        <param name="movie" value="#{url}" />
        <param name="bgcolor" value="#{bgcolor}" />
        <param name="wmode" value="opaque" />
        <param name="allowfullscreen" value="false" />
        <param name="allowscriptaccess" value="never" />
        <param name="quality" value="autohigh" />
        <param name="flashvars" value="clickTAG=#{click_tag}" />

        <!--[if !IE]>-->
          <object type="application/x-shockwave-flash" data="#{url}" width="#{width}" height="#{height}">
            <param name="bgcolor" value="#{bgcolor}" />
            <param name="wmode" value="opaque" />
            <param name="allowfullscreen" value="false" />
            <param name="allowscriptaccess" value="never" />
            <param name="quality" value="autohigh" />
            <param name="flashvars" value="clickTAG=#{click_tag}" />
        <!--<![endif]-->

        #{alt}

        <!--[if !IE]>-->
          </object>
        <!--<![endif]-->
      </object>
      <script type="text/javascript">
        try { swfobject.registerObject("#{id}", "9.0.0"); } catch(e) {}
		  </script>
HTML
    result.html_safe
  end

  def neofiles_cdn_prefix(*args)
    cdns = Rails.application.config.neofiles.cdns || []
    cdns << root_url unless cdns.any?

    if cdns.count > 1
      some_file = args.first
      if some_file.is_a? Neofiles::File
        gen_time = some_file.id.generation_time.sec
      elsif some_file.is_a?  Hash
        tmp = some_file[:id] || some_file['id'] || some_file[:_id] || some_file['_id'] || ""
        gen_time = Neofiles::File::BSON::ObjectId.legal?(tmp) ? Neofiles::File::BSON::ObjectId.from_string(tmp).generation_time.sec : Time.now.strftime('%U').to_i
      elsif some_file.is_a? String
        gen_time = Neofiles::File::BSON::ObjectId.legal?(some_file) ? Neofiles::File::BSON::ObjectId.from_string(some_file).generation_time.sec : Time.now.strftime('%U').to_i
      else
        gen_time = Time.now.strftime('%U').to_i
      end

      cdn = cdns[gen_time % cdns.count]
    else
      cdn = cdns.first
    end

    cdn.sub! /\/\z/, ''
    cdn = 'http://' + cdn unless cdn =~ /\Ahttp[s]?:\/\//
    cdn
  end

  def neofiles_file_url(*args)
    neofiles_cdn_prefix(*args) + neofiles_file_path(*args)
  end

  def neofiles_image_url(*args)
    neofiles_cdn_prefix(*args) + neofiles_image_path(*args)
  end

  private

    # Правила ресайза:
    #
    #   — если не обрезаем (resize_options[:crop] == 1) но масштабируем, то вычислим размер (сторонний метод).
    #   — если обрезаем, то размер равен запрошенному
    #   — если не обрезаем и не машстабируем, если передан файл, а не ID, размер равен исходному
    #
    # Иначе вернет nil.
    #
    # TODO: перместить `::Neofiles::ServeController.resized_image_dimensions` в модель
    def dimensions_after_resize(image_file, width, height, resize_options)
      we_need_resizing = width > 0 && height > 0
      if image_file.is_a?(::Neofiles::Image) and image_file.width > 0 and image_file.height > 0

        if we_need_resizing
          ::Neofiles.resized_image_dimensions(image_file, width, height, resize_options)
        else
          [image_file.width, image_file.height]
        end

      elsif we_need_resizing and resize_options[:crop].present? and resize_options[:crop].to_s != '0'
        [width, height]
      else
        [nil, nil]
      end
    end
end