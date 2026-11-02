class DemoCloneService
  DEMO_MASTER_EMAIL = ENV.fetch("DEMO_MASTER_EMAIL", nil)

  def self.call
    raise ActiveRecord::RecordNotFound, "DEMO_MASTER_EMAIL not configured" if DEMO_MASTER_EMAIL.blank?
    master = User.find_by!(email: DEMO_MASTER_EMAIL)
    new(master).clone
  end

  def initialize(master)
    @master = master
    @vineyard_map = {}
    @folder_map = {}
  end

  def clone
    temp_user = nil
    ActiveRecord::Base.transaction do
      temp_user = create_temp_user
      clone_vineyards(temp_user)
      clone_folders(temp_user)
    end
    # Карта виноградников, а не кустов: новый куст задача найдёт сама по номеру ряда и куста
    # (сотни тысяч пар id в аргументах — мегабайты JSON в solid_queue)
    CloneDemoMediaJob.perform_later(temp_user.id, @folder_map.stringify_keys, vineyard_map: @vineyard_map.stringify_keys)
    temp_user
  end

  # Таблица «старый id → новый id» для SQL: unnest двух массивов
  def self.id_map_sql(map, as:)
    ActiveRecord::Base.sanitize_sql_array([
      "unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS #{as}(old_id, new_id)",
      map.keys.map(&:to_i), map.values.map(&:to_i)
    ])
  end

  private

  def create_temp_user
    User.create!(
      email: "demo_#{SecureRandom.hex(8)}@demo.local",
      password: SecureRandom.hex(16),
      demo_temp: true,
      demo_expires_at: 24.hours.from_now,
      confirmed_at: Time.current
    )
  end

  # Виноградников единицы — копируем моделями. Ряды и кусты (на 50 га это сотни тысяч) копирует сама база
  # двумя INSERT … SELECT: через Ruby (объекты ActiveRecord + insert_all!) клон мастера на 183 тыс. кустов
  # занимал больше 30 с, и всё это время пользователь ждал ответа на кнопку «Демо-аккаунт»
  def clone_vineyards(user)
    # Удалённые мастером (soft delete) не копируем: папки и медиа на них в демо просто останутся без привязки
    @master.vineyards.active.find_each do |vineyard|
      new_vineyard = vineyard.dup
      new_vineyard.user = user
      new_vineyard.save!(validate: false)
      @vineyard_map[vineyard.id] = new_vineyard.id
    end
    return if @vineyard_map.empty?

    map = self.class.id_map_sql(@vineyard_map, as: "m")
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      INSERT INTO rows (vineyard_id, row_number, created_at, updated_at)
      SELECT m.new_id, r.row_number, now(), now()
      FROM rows r JOIN #{map} ON m.old_id = r.vineyard_id
    SQL
    # Новый ряд — по винограднику и номеру (уникальны вместе), куст переносит свой номер
    connection.execute(<<~SQL)
      INSERT INTO bushes (row_id, vineyard_id, bush_number, created_at, updated_at)
      SELECT nr.id, m.new_id, b.bush_number, now(), now()
      FROM bushes b
      JOIN rows r ON r.id = b.row_id
      JOIN #{map} ON m.old_id = r.vineyard_id
      JOIN rows nr ON nr.vineyard_id = m.new_id AND nr.row_number = r.row_number
    SQL
  end

  def clone_folders(user)
    now = Time.current
    all_folders = @master.folders.order(:id).to_a
    folder_by_id = all_folders.index_by(&:id)

    all_folders.group_by { |f| folder_depth(f, folder_by_id) }
               .sort_by { |depth, _| depth }
               .each do |_, folders|
      folders = folders.sort_by(&:id)
      folders_data = folders.map do |folder|
        {
          title: folder.title,
          user_id: user.id,
          parent_id: @folder_map[folder.parent_id],
          vineyard_id: @vineyard_map[folder.vineyard_id],
          created_at: now,
          updated_at: now
        }
      end
      new_ids = Folder.insert_all!(folders_data, returning: [ :id ]).map { |r| r["id"] }
      folders.each_with_index { |folder, i| @folder_map[folder.id] = new_ids[i] }
    end
  end

  def folder_depth(folder, folder_by_id)
    depth = 0
    current = folder
    while current.parent_id && (current = folder_by_id[current.parent_id])
      depth += 1
    end
    depth
  end
end
