module Transactions::Storage
  class ApplyRollback < ::Transaction
    t_name :storage_apply_rollback
    t_type 5211

    def params(dataset_in_pool)
      self.t_server = dataset_in_pool.pool.node_id

      {
          pool_fs: dataset_in_pool.pool.filesystem,
          dataset_name: dataset_in_pool.dataset.full_name
      }
    end
  end
end
