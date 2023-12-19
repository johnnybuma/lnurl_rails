class AddKeyValueToChainData < ActiveRecord::Migration[7.0]
  def change
    add_column :chain_data, :key, :string
    add_column :chain_data, :value, :text
  end
end
