module Neofiles::NeofilesHelper

  # Returns HTML IMG tag.
  #
  #   image_file      - ID, Neofiles::Image of Hash
  #   width, height   - if both are passed, image will be no more that that size
  #   resize_options  - crop: '1'/'0' (change or preserve aspect ration, @see Neofiles::ImagesController#show)
  #   html_attrs      - hash of additional HTML attrs like ALT, TITLE etc.
  #
  def neofiles_img_tag(image_file, width = nil, height = nil, resize_options = {}, html_attrs = {})

    resize_options ||= {} # в gem_neo_adv мы передаем nil

    unless image_file.blank?
      resize_options  = resize_options.merge(format: [width.to_i, height.to_i].join('x')) if width.to_i > 0 && height.to_i > 0
      size_attrs      = resize_options.key?(:size_attrs) ? resize_options[:size_attrs] : true
      image_or_id     = image_file.is_a?(Hash) ? image_file[:id] : image_file

      html_attrs.try :symbolize_keys!
      html_attrs[:src] = neofiles_image_url image_or_id, resize_options

      html_attrs[:width], html_attrs[:height] = dimensions_after_resize(image_file, width.to_i, height.to_i, resize_options) if size_attrs
    end

    tag :img, html_attrs
  end

  # Same as neofiles_img_tag but returned IMG is wrapped into A tag (HTML link) pointing to the file original.
  #
  #   link_attrs - HTML attrs for A
  #   img_attrs  - HTML attrs for IMG
  #
  # Other params are equivalent to neofiles_img_tag.
  #
  def neofiles_img_link(image_file, width = nil, height = nil, resize_options = {}, link_attrs = {}, img_attrs = {})
    link_attrs[:href] = neofiles_image_url image_file unless link_attrs[:href]
    neofiles_link(image_file, neofiles_img_tag(image_file, width, height, resize_options, img_attrs), link_attrs)
  end

  # Returns HTML A tag with link to the passed file.
  #
  #   file        - ID or Neofiles::File
  #   tag_content - what the link content will be (default: file description of filename)
  #   html_attrs  - additional HTML attrs like TITLE, TARGET etc.
  #
  def neofiles_link(file, tag_content = nil, html_attrs = {})
    html_attrs[:href] = neofiles_file_url file unless html_attrs[:href]
    content_tag(:a, tag_content.presence || file.description.presence || file.filename, html_attrs)
  end

  # Returns HTML OBJECT tag to embed SWF (Flash) files.
  #
  # For fully crossbrowser experience include swfobject.js on page, where SWF embedding is performed.
  #
  #   id        - DOM ID of the object
  #   url       - path/url to SWF file
  #   width     - resulting object's area width
  #   height    - resulting object's area height
  #   bgcolor   - if passed, the object's area will be colored in this CSS color
  #   click_tag - clickTAG is a common name for Flash variable used to tell a movie clip to redirect viewer to a certain
  #               URL after clicking (used in banners)
  #   alt       - alternative HTML, in case if Flash is not available
  #
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

  # Returns CDN (Content Delivery Network) prefix - mainly a domain - if available.
  #
  # Array of CDNs is set via Rails.application.config.neofiles.cdns. If many exist, we choose one by taking remainder
  # of dividing unix epoch creation time of the object, for which prefix is requested, by number of CDNs.
  #
  # If no CDN available, will take current domain via Rails helper root_url.
  #
  # First argument is considered Neofiles::File, ID or Hash. Other arguments are ignored.
  #
  # Returned prefix is of form 'http://doma.in/url/prefix'.
  #
  def neofiles_cdn_prefix(*args)
    cdns = Rails.application.config.neofiles.cdns || []
    cdns << root_url unless cdns.any?

    if cdns.count > 1
      some_file = args.first
      if some_file.is_a? Neofiles::File
        gen_time = some_file.id.generation_time.sec
      elsif some_file.is_a?  Hash
        tmp = some_file[:id] || some_file['id'] || some_file[:_id] || some_file['_id'] || ""
        gen_time = BSON::ObjectId.legal?(tmp) ? BSON::ObjectId.from_string(tmp).generation_time.sec : Time.now.strftime('%U').to_i
      elsif some_file.is_a? String
        gen_time = BSON::ObjectId.legal?(some_file) ? BSON::ObjectId.from_string(some_file).generation_time.sec : Time.now.strftime('%U').to_i
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

  # Override file URL generation to include CDN prefix.
  def neofiles_file_url(*args)
    neofiles_cdn_prefix(*args) + neofiles_file_path(*args)
  end

  # Override image URL generation to include CDN prefix.
  def neofiles_image_url(*args)
    neofiles_cdn_prefix(*args) + neofiles_image_path(*args)
  end



  private

  # Calculate dimensions of an image after resize applied, according to rules in Neofiles::ImagesController#show.
  #
  # 1) if not cropping (resize_options[:crop] != '1'), but destination width and height are set, calculate resized
  #    dimensions via external method (uses ImageMagick)
  # 2) if cropping (resize_options[:crop] == '1'), resized dimensions are equal to the requested with & height
  # 3) if not cropping and with & height not set, resized dimensions are equal to the input file width & height
  # 4) if some variables are not available (like input file or height, if file ID is passed), returns nil
  #
  #   image_file      - Neofiles::Image, ID or Hash
  #   width, height   - resulting width & height
  #   resize_options  - {crop: '1'/'0'}
  #
  def dimensions_after_resize(image_file, width, height, resize_options)
    we_need_resizing = width > 0 && height > 0

    if image_file.is_a? Neofiles::Image
      image_file_width = image_file.width
      image_file_height = image_file.height
    elsif image_file.is_a? Hash
      image_file_width = image_file[:width]
      image_file_height = image_file[:height]
    end

    if (image_file_width.present? && image_file_height.present?) && (image_file_width > 0 && image_file_height > 0)
      if we_need_resizing
        ::Neofiles.resized_image_dimensions(image_file, width, height, resize_options)
      else
        [image_file_width, image_file_height]
      end
    elsif we_need_resizing and resize_options[:crop].present? and resize_options[:crop].to_s != '0'
      [width, height]
    else
      [nil, nil]
    end
  end
end