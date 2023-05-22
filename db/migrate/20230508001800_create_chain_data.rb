class CreateChainData < ActiveRecord::Migration[7.0]
  def change
    create_table :chain_data do |t|

      t.timestamps
    end
  end
end
