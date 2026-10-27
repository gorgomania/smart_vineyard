class AddDemoFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :demo_temp, :boolean, default: false, null: false
    add_column :users, :demo_expires_at, :datetime
  end
end
