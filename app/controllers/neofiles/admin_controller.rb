# The main controller, doing all persistence related activities. It extends ApplicationController to derive
# any application-specific business logic, like before/after filters, auth & auth and stuff.
#
# To setup routes to this controller use Neofiles.routes_proc, @see lib/neofiles.rb
#
# As the main principle behind whole Neofiles thing is AJAX file manipulations, actions of this controller
# mainly form backend for AJAX calls.
#
class Neofiles::AdminController < ApplicationController

  # TODO: remove this! it should be controlled on application side
  skip_before_filter :verify_authenticity_token

  # Build AJAX edit/upload form for a single file in compact way: small file thumbnail + misc buttons, like "delete",
  # "change options" etc.
  #
  # It is expected that someday there will be "full" view (hence the prefix "compact" here), with metadata shown
  # and all kinds of tools exposed.
  #
  # If param[:id] is present, the form displayed is for editing a file, while empty or non existent ID displays
  # an upload form.
  #
  # The parameter fake_request allows to build form when needed, when there is no actual request available
  # (@see #file_save).
  #
  # Main parameters:
  #
  #   request[:input_name]    - input with this name will be present in HTML and populated with ID of persisted file
  #   request[:widget_id]     - DOM identifier for this file widget instance
  #   request[:clean_remove]  - after deleting this file, no substituting upload form should be shown (default '0')
  #   request[:append_create] - after persisting new file, action should return form for the file + an upload form
  #                             (default '0')
  #   request[:disabled]      - only show file, not allow anything to be edited (default '0')
  #   request[:multiple]      - allow uploading of multiple files at once (default '0')
  #   request[:with_desc]     - show short file description (default '0')
  #
  # Parameters clear_remove & append_create are used to organize Albums — technically a collection of single files.
  #
  def file_compact(fake_request = nil)
    request = fake_request || self.request

    begin
      @file = Neofiles::File.find request[:id] if request[:id].present?
    rescue Mongoid::Errors::DocumentNotFound
      @file = nil
    end

    @error = I18n.t('neofiles.file_not_found') if request[:id].present? and @file.blank?

    @input_name     = request[:input_name].to_s
    @widget_id      = request[:widget_id].presence
    @clean_remove   = request[:clean_remove].present? && request[:clean_remove] != '0'
    @append_create  = request[:append_create].present? && request[:append_create] != '0'
    @disabled       = request[:disabled].present? && request[:disabled] != '0'
    @multiple       = request[:multiple].present? && request[:multiple] != '0'
    @with_desc      = request[:with_desc].present? && request[:with_desc] != '0'
    @error        ||= ''

    if fake_request
      return render_to_string action: :file_compact, layout: false
    else
      render layout: false
    end
  end

  # Persist new file(s) to database and return view forms for all of them (@see #file_compact) as one big HTML.
  #
  # Raises exception if something went wrong.
  #
  # This method uses append_create parameter originally passed to #file_compact (stored by JavaScript and sent again
  # via AJAX call).
  #
  def file_save
    data = request[:neofiles]
    raise ArgumentError.new I18n.t('neofiles.data_not_passed') unless data.is_a? Hash

    files = data[:file]
    files = [files] unless files.is_a? Array
    old_file = data[:id].present? ? Neofiles::File.find(data[:id]) : nil

    file_objects = []
    errors = []
    last_exception = nil
    files.each_with_index do |uploaded_file, i|
      errors.push("#{I18n.t('neofiles.file_not_passed')} (#{i + 1})") and next unless uploaded_file.respond_to? :read

      file_class = Neofiles::File.class_by_file_object(uploaded_file)
      file = file_class.new do |f|
        f.description = data[:description].presence || old_file.try(:description)
        f.file = uploaded_file
      end

      begin
        Rails.application.config.neofiles.before_save.try!(:call, file)
        file.save!
      rescue Exception => ex
        last_exception = ex
        notify_airbrake(ex) if defined? notify_airbrake
        next
      end

      file_objects << file
    end

    result = []
    file_objects.each_with_index do |file, i|
      result << file_compact(data.merge(id: file.id, widget_id: "#{data[:widget_id]}_ap_#{i}", append_create: i == file_objects.count - 1 && !old_file && data[:append_create] == '1' ? '1' : '0'))
    end

    if result.empty?
      raise ArgumentError.new(last_exception || (errors.empty? ? I18n.t('neofiles.file_not_passed') : errors.join("\n")))
    end

    render text: result.join, layout: false
  end

  # As we don't actually delete anything, this method only marks file as deleted.
  #
  # This method uses clean_remove parameter originally passed to #file_compact (stored by JavaScript and sent again
  # via AJAX call).
  #
  def file_remove
    file, data = find_file_and_data

    file.is_deleted = true
    file.save!

    return render text: '' if data[:clean_remove].present? && data[:clean_remove] != '0'

    redirect_to neofiles_file_compact_path(data.merge(id: nil))
  end

  # As Neofiles treats files as immutables, this method updates only auxiliary fields: description, no_wm etc.
  #
  # Returns nothing.
  #
  def file_update
    file, data = find_file_and_data
    file.update data.slice(:description, :no_wm)
    render text: '', layout: false
  end

  # Neofiles knows how to play with Redactor.js and this method persists files uploaded via this WYSIWYG editor.
  #
  # Redactor.js may know which owner object is edited so we can store owner_type/id for later use.
  #
  # Returns JSON list of persisted files.
  #
  def redactor_upload
    owner_type, owner_id, file = prepare_owner_type(request[:owner_type]), request[:owner_id], request[:file]
    raise ArgumentError.new I18n.t('neofiles.data_not_passed') if owner_type.blank? || owner_id.blank?
    raise ArgumentError.new I18n.t('neofiles.file_not_passed') unless file.present? && file.respond_to?(:read)

    file_class = Neofiles::File.class_by_file_object(file)

    file = file_class.new do |f|
      f.owner_type  = owner_type
      f.owner_id    = owner_id
      f.description = request[:description].presence

      f.no_wm = true if f.respond_to?(:no_wm)
      f.file  = file
    end

    Rails.application.config.neofiles.before_save.try!(:call, file)
    file.save!

    # returns JSON {url: '/neofiles/serve-file/#{file.id}'}
    render json: {filelink: neofiles_file_path(file), filename: file.filename, url: neofiles_file_path(file), name: file.filename}
  end

  # Returns JSON of files assigned to specific owner to show them in Redactor.js tab "previously uploaded files".
  #
  def redactor_list
    type, owner_type, owner_id = request[:type], prepare_owner_type(request[:owner_type]), request[:owner_id]

    type ||= 'file'

    begin
      file_class = "Neofiles::#{type.classify}".constantize
    rescue
      raise ArgumentError.new I18n.t('neofiles.unknown_file_type', type: type)
    end

    result = []
    files = file_class.where(owner_type: owner_type, owner_id: owner_id)
    files.each do |f|
      if f.is_a?(Neofiles::Image)
        result << {
          thumb: neofiles_image_path(f, format: '100x100'),
          image: neofiles_file_path(f),
          title: f.description.to_s,
          #folder: '',
        }
      else
        result << {
          filelink: neofiles_file_path(f),
          title: f.description.to_s,
          #folder: '',
        }
      end
    end

    # returns JSON [{filelink: '/neofiles/serve-file/#{file.id}', title: '...', thumb: '/neo.../100x100'}, {...}, ...]
    render json: result

  rescue
    render json: []
  end



  private

  # Fetch common data from request.
  def find_file_and_data
    data = request[:neofiles]
    raise ArgumentError.new I18n.t('neofiles.data_not_passed') if data.blank? || !(data.is_a? Hash)
    raise ArgumentError.new I18n.t('neofiles.id_not_passed') unless data[:id].present?

    [Neofiles::File.find(data[:id]), data]
  end

  # TODO: owner_type must be stored properly as in Mongoid polymorphic relation
  def prepare_owner_type(type)
    type.to_s.gsub(':', '/')
  end
end