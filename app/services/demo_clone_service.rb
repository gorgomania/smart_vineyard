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
    @row_map = {}
    @bush_map = {}
    @folder_map = {}
  end

  def clone
    temp_user = nil
    ActiveRecord::Base.transaction do
      temp_user = create_temp_user
      clone_vineyards(temp_user)
      clone_folders(temp_user)
    end
    CloneDemoMediaJob.perform_later(temp_user.id, @folder_map.stringify_keys, @bush_map.stringify_keys)
    temp_user
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

  def clone_vineyards(user)
    now = Time.current
    vineyards = @master.vineyards.includes(rows: :bushes).to_a

    vineyards.each do |vineyard|
      new_vineyard = vineyard.dup
      new_vineyard.user = user
      new_vineyard.deleted_at = nil
      new_vineyard.save!(validate: false)
      @vineyard_map[vineyard.id] = new_vineyard.id
    end

    all_rows = vineyards.flat_map(&:rows).sort_by(&:id)
    if all_rows.any?
      rows_data = all_rows.map do |row|
        { vineyard_id: @vineyard_map[row.vineyard_id], row_number: row.row_number, created_at: now, updated_at: now }
      end
      new_row_ids = Row.insert_all!(rows_data, returning: [ :id ]).map { |r| r["id"] }
      all_rows.each_with_index { |row, i| @row_map[row.id] = new_row_ids[i] }
    end

    all_bushes = vineyards.flat_map { |v| v.rows.flat_map(&:bushes) }.sort_by(&:id)
    if all_bushes.any?
      bushes_data = all_bushes.map do |bush|
        {
          row_id: @row_map[bush.row_id],
          vineyard_id: @vineyard_map[bush.vineyard_id],
          bush_number: bush.bush_number,
          created_at: now,
          updated_at: now
        }
      end
      new_bush_ids = Bush.insert_all!(bushes_data, returning: [ :id ]).map { |r| r["id"] }
      all_bushes.each_with_index { |bush, i| @bush_map[bush.id] = new_bush_ids[i] }
    end
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
