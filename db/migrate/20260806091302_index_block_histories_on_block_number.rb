class IndexBlockHistoriesOnBlockNumber < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :block_histories, :block_number,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
