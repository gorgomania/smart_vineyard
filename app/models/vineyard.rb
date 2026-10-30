class Vineyard < ApplicationRecord
  belongs_to :user
  # Кусты (FK bushes → rows ON DELETE CASCADE) и привязки файлов к ним (media_items → bushes ON DELETE SET NULL)
  # убирает сама БД: один DELETE вместо destroy каждого из тысяч кустов
  has_many :rows, dependent: :delete_all
  has_many :bushes, through: :rows
  has_many :media_items, through: :bushes
  has_one :folder, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :user_id }
  validates :polygon, presence: true
  validates :area_hectares, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  validates :grape_variety, length: { maximum: 50 }, allow_blank: true
  validates :planting_year,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1900,
              less_than_or_equal_to: -> { Date.current.year },
              allow_nil: true
            }
  validates :total_rows, numericality: { greater_than: 0 }
  validates :total_bushes, numericality: { greater_than: 0 }
  validates :row_spacing, numericality: { greater_than_or_equal_to: 2.0, less_than_or_equal_to: 3.0 }
  validates :bush_spacing, numericality: { greater_than_or_equal_to: 1.2, less_than_or_equal_to: 1.8 }

  scope :active, -> { where(deleted_at: nil) }

  # Виноградники без папки. keep_vineyard_id — текущий виноградник перекрепляемой папки: его тоже можно выбрать
  scope :free, ->(keep_vineyard_id: nil) {
    where.not(id: Folder.where.not(vineyard_id: [ nil, keep_vineyard_id ]).select(:vineyard_id))
  }

  scope :for_index, -> {
    select(:id, :name, :polygon, :area_hectares, :grape_variety, :total_rows, :total_bushes).order(:name)
  }

  # Пользователь сразу перестаёт видеть виноградник (scope :active), а запись удаляет DestroyVineyardJob
  def soft_destroy
    update(deleted_at: Time.current)
    DestroyVineyardJob.perform_later(id)
  end

  # Привязки файлов к кустам поменялись: открытые тепловые карты этих виноградников перечитывают диагнозы
  # (vineyards/show, heatmap_refresh в application.js), страницы статистики обновляются. Одно сообщение
  # на виноградник, а не на каждый куст
  def self.broadcast_diagnoses_changed(vineyard_ids)
    where(id: vineyard_ids).find_each do |vineyard|
      Turbo::StreamsChannel.broadcast_action_to(vineyard, :heatmap, action: :heatmap_refresh, target: "map")
    end
    broadcast_stats_refresh(vineyard_ids)
  end

  # Открытые страницы статистики (turbo_stream_from в vineyards/stats) перезапрашивают себя морфингом:
  # и страница виноградника, и общая статистика его владельца
  def self.broadcast_stats_refresh(vineyard_ids)
    vineyards = where(id: vineyard_ids).to_a
    vineyards.each { |vineyard| Turbo::StreamsChannel.broadcast_refresh_to(vineyard, :stats) }
    User.where(id: vineyards.map(&:user_id)).find_each { |user| Turbo::StreamsChannel.broadcast_refresh_to(user, :stats) }
  end

  # Тепловая карта: { "ряд-куст" => [id файла, класс] } только для кустов с файлом, остальные карта красит серым
  def bushes_diagnoses
    bushes.joins(:row, :media_item)
          .pluck("rows.row_number", "bushes.bush_number", "media_items.id", "media_items.ai_class_id")
          .to_h { |row_number, bush_number, media_item_id, class_id| [ "#{row_number}-#{bush_number}", [ media_item_id, class_id ] ] }
  end

  def area_hectares=(value)
    if value.is_a?(String)
      # Удаляем последние 3 символа если это ' га' или просто 'га'
      cleaned = value.gsub(/\s*га$/, "")  # Удаляет ' га' или 'га' в конце
      value = cleaned.to_f
    end
    super(value)
  end
end
