# encoding: UTF-8
class Neofiles::File

  bson = defined?(Moped::BSON) ? Moped::BSON : BSON

  include Mongoid::Document
  include Mongoid::Timestamps

  store_in collection: "files.files", session: "neofiles"

  has_many :chunks, dependent: :destroy, order: [:n, :asc], class_name: 'Neofiles::FileChunk'

  DEFAULT_CHUNK_SIZE = 4.megabytes

  field :filename, type: String
  field :content_type, type: String
  field :length, type: Integer, default: 0
  field :chunk_size, type: Integer, default: DEFAULT_CHUNK_SIZE
  field :md5, type: String, default: Digest::MD5.hexdigest('')
  field :description, type: String
  field :owner_type, type: String
  field :owner_id, type: String
  field :deleted, type: Mongoid::Boolean

  validates :filename, :length, :chunk_size, :md5, presence: true

  before_save :save_file
  after_save :nullify_unpersisted_file



  # Пройдемся по всем чанкам, вызывая блок.
  def each(&block)
    chunks.all.order_by([:n, :asc]).each do |chunk|
      block.call(chunk.to_s)
    end
  end

  def slice(*args)
    case args.first
      when Range
        range = args.first
        first_chunk = (range.min / chunk_size).floor
        last_chunk = (range.max / chunk_size).ceil
        offset = range.min % chunk_size
        length = range.max - range.min + 1
      when Fixnum
        start = args.first
        start = self.length + start if start < 0
        length = args.size == 2 ? args.last : 1
        first_chunk = (start / chunk_size).floor
        last_chunk = ((start + length) / chunk_size).ceil
        offset = start % chunk_size
    end

    data = ''

    chunks.where(n: first_chunk..last_chunk).order_by(n: :asc).each do |chunk|
      data << chunk
    end

    data[offset, length]
  end

  # Получим байты файла в виде строки.
  def data
    data = ''
    each { |chunk| data << chunk }
    data
  end

  # Закодируем картинку в base64.
  def base64
    Array(to_s).pack('m')
  end

  # Закодируем картинку в DATA URI.
  def data_uri(options = {})
    data = base64.chomp
    "data:#{content_type};base64,#{data}"
  end

  # Получим байты файла в виде массива чанков. Если передан блок, то будем вызывать блок для каждого загружаемого чанка.
  def bytes(&block)
    if block
      each { |data| block.call(data) }
      length
    else
      bytes = []
      each { |data| bytes.push(*data) }
      bytes
    end
  end



  # Файл, который нужно сохранить. Если это поле не nil, то при следующем вызове save будем сохранять файл.
  attr_reader :file

  # Добавить файл. Можеть быть имя файла или его дескриптор. Фактически, может быть и потоком.
  # Реально работа не делается, только сохраняем ссылку на файл, сохранять будем в before_save.
  def file=(file)
    @file = file

    if @file
      self.filename = self.class.extract_basename(@file)
      self.content_type = self.class.extract_content_type(filename) || 'application/octet-stream'
    else
      self.filename = nil
      self.content_type = nil
    end
  end

  # Есть ли несохраненный файл?
  def unpersisted_file?
    not @file.nil?
  end

  # Перед сохранением запишем все кусочки файла в коллекцию чанков.
  def save_file
    if @file
      # удалим уже существущие чанки
      self.chunks.delete_all

      # теперь прочитаем картинку заново и запишем в монго
      md5 = Digest::MD5.new
      length = 0
      n = 0 # ???

      self.class.reading(@file) do |io|

        self.class.chunking(io, chunk_size) do |buf|
          md5 << buf
          length += buf.size
          chunk = self.chunks.build
          chunk.data = self.class.binary_for(buf)
          chunk.n = n
          n += 1
          chunk.save!
          self.chunks.push(chunk)
        end

      end

      self.length = length
      self.md5 = md5.hexdigest
    end
  end

  # Сохранили, значит, уберем ссылку на сохраненный файл.
  def nullify_unpersisted_file
    @file = nil
  end

  # Как будет выглядеть в админке этот файл в "компактном" представлении (при загрузке, в альбомах и т. п.)
  # Простой файл показывается в виде ссылки с описанием или названием.
  def admin_compact_view(template)
    template.neofiles_link self, nil, target: '_blank'
  end



  # Обернем входной аргумент в поток (так как аргумент может быть именем файла или потоком). Для потока вызовем блок.
  def self.reading(arg, &block)
    if arg.respond_to?(:read)
      self.rewind(arg) do |io|
        block.call(io)
      end
    else
      open(arg.to_s) do |io|
        block.call(io)
      end
    end
  end

  # Читаем поток, разбивая на чанки длинной chunk_size, и вызываем блок для каждого чанка.
  def self.chunking(io, chunk_size, &block)
    if io.method(:read).arity == 0
      data = io.read
      i = 0 # ???
      loop do
        offset = i * chunk_size
        length = i + chunk_size < data.size ? chunk_size : data.size - offset

        break if offset >= data.size

        buf = data[offset, length]
        block.call(buf)
        i += 1
      end
    else
      while buf = io.read(chunk_size)
        block.call(buf)
      end
    end
  end

  # Метод, конструирующий из строки бинарный объект для Монги.
  def self.binary_for(*buf)
    bson::Binary.new(:generic, buf.join)
  end

  # Получим имя файла (без директории) для входного объекта. Пробуем разные способы: :path, :filename etc.
  def self.extract_basename(object)
    filename = nil
    %i(original_path original_filename path filename pathname).each do |msg|
      if object.respond_to?(msg)
        filename = object.send(msg)
        break
      end
    end
    filename ? cleanname(filename) : nil
  end

  # Получим строку вида image/jpeg из имени файла xxxx.jpg.
  def self.extract_content_type(basename)
    if defined?(MIME)
      content_type = MIME::Types.type_for(basename.to_s).first
    else
      ext = ::File.extname(basename.to_s).downcase.sub(/[.]/, '')
      if ext.in? %w{ jpeg jpg gif png }
        content_type = 'image/' + ext.sub(/jpg/, 'jpeg')
      elsif ext == 'swf'
        content_type = 'application/x-shockwave-flash'
      else
        content_type = nil
      end
    end

    content_type.to_s if content_type
  end

  # Отрежем директорию от пути до файла.
  def self.cleanname(pathname)
    ::File.basename(pathname.to_s)
  end

  # Возвращает тип класса-наследника, который должен использоваться для сохранения файла типа content_type.
  # Если не найдет, вернет себя (Neofiles::File).
  #
  #   Neofiles::File.file_class_by_content_type('image/jpeg') # -> Neofiles::Image
  def self.class_by_content_type(content_type)
    case content_type
    when /\Aimage\//
      ::Neofiles::Image
    when 'application/x-shockwave-flash'
      ::Neofiles::Swf
    else
      self
    end
  end

  def self.class_by_file_name(file_name)
    class_by_content_type(extract_content_type(file_name))
  end

  def self.class_by_file_object(file_object)
    class_by_file_name(extract_basename(file_object))
  end

  # Перемотаем в начало аргумент, считая его потоком, и запустим для него (потока) блок.
  def self.rewind(io, &block)
    begin
      pos = io.pos
      io.flush
      io.rewind
    rescue
      nil
    end

    begin
      block.call(io)
    ensure
      begin
        io.pos = pos
      rescue
        nil
      end
    end
  end
end
