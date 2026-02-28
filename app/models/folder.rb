class Folder < ApplicationRecord
  belongs_to :parent, class_name: "Folder", optional: true
  has_many :children, class_name: "Folder", foreign_key: :parent_id, dependent: :destroy
  has_many :media_items, dependent: :destroy
  validates :title, presence: { message: "Имя не может быть пустым." }
  validates :title, uniqueness: { scope: :parent_id, message: "Имя папки уже используется." }
  validates :title, length: { maximum: 15, message: "Длина не более 15 символов." }
end
