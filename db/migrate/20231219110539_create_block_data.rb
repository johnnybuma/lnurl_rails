class CreateBlockData < ActiveRecord::Migration[7.0]
  def change
    create_table :block_data do |t|
      t.integer :block_number
      t.string :block_hash
      t.text :data

      t.timestamps
    end
  end
end
