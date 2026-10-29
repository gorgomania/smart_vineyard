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
    CloneDemoMediaJob.perform_later(temp_user.id, @folder_map, @bush_map)
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
    @master.vineyards.includes(rows: :bushes).find_each do |vineyard|
      new_vineyard = vineyard.dup
      new_vineyard.user = user
      new_vineyard.deleted_at = nil
      new_vineyard.save!(validate: false)
      @vineyard_map[vineyard.id] = new_vineyard

      vineyard.rows.each do |row|
        new_row = row.dup
        new_row.vineyard = new_vineyard
        new_row.save!

        row.bushes.each do |bush|
          new_bush = bush.dup
          new_bush.row = new_row
          new_bush.vineyard_id = new_vineyard.id
          new_bush.save!
          @bush_map[bush.id] = new_bush.id
        end
      end
    end
  end

  def clone_folders(user)
    all_folders = @master.folders.order(:id).to_a
    folder_by_id = all_folders.index_by(&:id)
    all_folders.sort_by { |f| folder_depth(f, folder_by_id) }.each do |folder|
      new_folder = folder.dup
      new_folder.user = user
      new_folder.parent_id = @folder_map[folder.parent_id]
      new_folder.vineyard_id = @vineyard_map[folder.vineyard_id]&.id if folder.vineyard_id
      new_folder.save!(validate: false)
      @folder_map[folder.id] = new_folder.id
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
