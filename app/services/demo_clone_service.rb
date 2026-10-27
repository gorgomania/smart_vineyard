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
    temp_user = create_temp_user
    clone_vineyards(temp_user)
    clone_folders(temp_user)
    clone_media_items
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
    @master.vineyards.find_each do |vineyard|
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
    roots = @master.folders.where(parent_id: nil).to_a
    clone_folder_level(roots, nil, user)
  end

  def clone_folder_level(folders, new_parent_id, user)
    folders.each do |folder|
      new_folder = folder.dup
      new_folder.user = user
      new_folder.parent_id = new_parent_id
      new_folder.vineyard_id = @vineyard_map[folder.vineyard_id]&.id if folder.vineyard_id
      new_folder.save!(validate: false)
      @folder_map[folder.id] = new_folder.id

      children = folder.children.to_a
      clone_folder_level(children, new_folder.id, user) if children.any?
    end
  end

  def clone_media_items
    MediaItem.where(folder_id: @folder_map.keys).find_each do |item|
      new_item = item.dup
      new_item.folder_id = @folder_map[item.folder_id]
      new_item.bush_id = @bush_map[item.bush_id] if item.bush_id
      new_item.ai_classified_at = item.ai_classified_at
      new_item.save!(validate: false)

      new_item.media.attach(item.media.blob) if item.media.attached?
      new_item.video_preview.attach(item.video_preview.blob) if item.video_preview.attached?
    end
  end
end
