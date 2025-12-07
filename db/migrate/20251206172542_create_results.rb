class CreateResults < ActiveRecord::Migration[8.0]
  def change
    create_table :results do |t|
      t.timestamps
    end
  end
end
