class Folder < ApplicationRecord
  belongs_to :parent, class_name: "Folder", optional: true
  has_many :children, class_name: "Folder", foreign_key: :parent_id, dependent: :destroy
  has_many_attached :images
  has_many_attached :videos
  validates :title, presence: true
  validates :title, uniqueness: { scope: :parent_id }
end
