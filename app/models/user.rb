class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable
  # prepend: раньше dependent: :destroy, чтобы тот не обходил каждую папку и файл по одному
  before_destroy :delete_folder_trees, prepend: true
  has_many :folders, dependent: :destroy
  has_many :vineyards, dependent: :destroy

  private

  def delete_folder_trees
    Folder.delete_trees!(folders.where(parent_id: nil).ids)
  end
end
