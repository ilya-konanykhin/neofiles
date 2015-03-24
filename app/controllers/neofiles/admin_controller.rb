# encoding: UTF-8
class Neofiles::AdminController < ApplicationController

  skip_before_filter :verify_authenticity_token

  def file_compact(fake_request = nil)
    request = fake_request || self.request

    begin
      @file = Neofiles::File.find request[:id] if request[:id].present?
    rescue Mongoid::Errors::DocumentNotFound
      @file = nil
    end

    @error = 'Файл не найден' if request[:id].present? and @file.blank?

    @input_name     = request[:input_name].to_s
    @widget_id      = request[:widget_id].presence
    @clean_remove   = request[:clean_remove].present? && request[:clean_remove] != '0'
    @append_create  = request[:append_create].present? && request[:append_create] != '0'
    @disabled       = request[:disabled].present? && request[:disabled] != '0'
    @multiple       = request[:multiple].present? && request[:multiple] != '0'
    @error        ||= ''

    if fake_request
      return render_to_string action: :file_compact, layout: false
    else
      render layout: false
    end
  end

  def file_save
    data = request[:neofiles]
    raise 'Не переданы данные для сохранения' unless data.is_a? Hash

    files = data[:file]
    files = [files] unless files.is_a? Array
    old_file = data[:id].present? ? Neofiles::File.find(data[:id]) : nil

    file_objects = []
    errors = []
    last_exception = nil
    files.each_with_index do |uploaded_file, i|
      errors.push("Не передан файл для сохранения (#{i + 1})") and next unless uploaded_file.respond_to? :read

      # создадим новый файл, если описание не передано, возьмем от старого, если есть
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
      raise last_exception || (errors.empty? ? 'Не передан файл для сохранения' : errors.join("\n"))
    end

    render text: result.join, layout: false
  end

  def file_remove
    file, data = find_file_and_data

    # реально мы не удаляем файл
    file.is_deleted = true
    file.save!

    # если передан clean_remove (не 0), то вернем пустой результат
    return render text: '' if data[:clean_remove].present? && data[:clean_remove] != '0'

    # clean_remove пустой, значит, перекинем на просмотр (загрузку) пустого файла
    redirect_to neofiles_file_compact_path(data.merge(id: nil))
  end

  def file_update
    file, data = find_file_and_data
    file.update data.slice(:description, :no_wm)
    render text: "", layout: false
  end

  # Обработка загрузки файла через redactor.js. Получает файл и мета-данные (owner_type, owner_id) и отдает JSON,
  # в котором путь до загруженного файла.
  def redactor_upload
    owner_type, owner_id, file = prepare_owner_type(request[:owner_type]), request[:owner_id], request[:file]
    raise 'Не переданы данные для сохранения' if owner_type.blank? or owner_id.blank?
    raise 'Не передан файл для сохранения' unless file.present? and file.respond_to? :read

    # выберем тип файла
    file_class = Neofiles::File.class_by_file_object(file)

    # создадим новый файл
    file = file_class.new do |f|
      f.owner_type  = owner_type
      f.owner_id    = owner_id
      f.description = request[:description].presence

      f.no_wm = true if f.respond_to?(:no_wm)
      f.file  = file
    end

    # сохраним все
    Rails.application.config.neofiles.before_save.try!(:call, file)
    file.save!

    # вернем путь до загруженного файла
    render json: {filelink: neofiles_file_path(file), filename: file.filename}

  end

  # Список загруженных файлов в формате JSON для redactor.js.
  def redactor_list
    type, owner_type, owner_id = request[:type], prepare_owner_type(request[:owner_type]), request[:owner_id]

    # по-умолчанию тип file
    type ||= "file"

    # проверим, есть ли такой тип файла?
    begin
      file_class = "Neofiles::#{type.classify}".constantize
    rescue
      raise "Не могу создать файл неизвестного типа #{type}"
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

    render json: result

  rescue
    render json: []
  end

  protected
    def find_file_and_data
      data = request[:neofiles]
      raise 'Не переданы данные для сохранения' if data.blank? || !(data.is_a? Hash)
      raise 'Не передан ID файла для удаления' unless data[:id].present?

      [Neofiles::File.find(data[:id]), data]
    end

    def prepare_owner_type(type)
      type.to_s.gsub(':', '/')
    end
end