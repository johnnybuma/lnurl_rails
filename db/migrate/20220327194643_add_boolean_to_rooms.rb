class AddBooleanToRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :rooms, :is_private, :boolean
  end
end
