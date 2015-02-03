module TransactionChains
  class Vps::Create < ::TransactionChain
    label 'Create VPS'

    def link_chain(vps, add_ips)
      vps.save!
      lock(vps)

      # FIXME: diskspace must be allocated by dataset, not a VPS!
      resources = vps.allocate_resources(
          vps.node.environment,
          required: %i(cpu memory diskspace),
          optional: [],
          user: vps.user,
          chain: self
      )

      pool = vps.node.pools.where(role: :hypervisor).take!

      ds = ::Dataset.create(
          name: vps.id.to_s,
          user: vps.user,
          user_editable: false,
          user_create: true,
          user_destroy: false
      )

      vps.dataset_in_pool = ::DatasetInPool.create(
          dataset: ds,
          pool: pool,
          label: vps.id.to_s
      )

      lock(vps.dataset_in_pool)

      append(Transactions::Storage::CreateDataset, args: vps.dataset_in_pool) do
        create(ds)
        create(vps.dataset_in_pool)
      end

      vps.dataset_in_pool.call_class_hooks_for(:create, self, args: [vps.dataset_in_pool])

      append(Transactions::Vps::Create, args: vps) do
        create(vps)
        resources.each { |r| create(r) }
      end

      use_chain(Vps::ApplyConfig, args: [vps, vps.node.environment.vps_configs.pluck(:id)])

      if add_ips
        versions = [:ipv4]
        versions << :ipv6 if vps.node.location.has_ipv6

        resources = vps.allocate_resources(
            vps.node.environment,
            required: [],
            optional: versions,
            user: vps.user,
            chain: self
        )

        if resources.size > 0
          append(Transactions::Utils::NoOp, args: vps.vps_server) do
            resources.each { |r| create(r) }
          end
        end
      end

      if vps.vps_onboot
        use_chain(TransactionChains::Vps::Start, args: vps)
      end

      vps.save!

      # mapping, last_id = StorageExport.create_default_exports(self, depend: last_id)
      # create_default_mounts(mapping)
      #
      # Transactions::Vps::Mounts.fire_chained(last_id, self, false)
    end
  end
end
