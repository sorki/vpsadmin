class VpsAdmin::API::Resources::VPS < HaveAPI::Resource
  version 1
  model ::Vps
  desc 'Manage VPS'

  params(:id) do
    id :id, label: 'VPS id', db_name: :vps_id
  end

  params(:template) do
    resource VpsAdmin::API::Resources::OsTemplate, label: 'OS template'
  end

  params(:common) do
    resource VpsAdmin::API::Resources::User, label: 'User', desc: 'VPS owner',
             value_label: :login
    string :hostname, desc: 'VPS hostname', db_name: :vps_hostname,
           required: true
    use :template
    string :info, label: 'Info', desc: 'VPS description', db_name: :vps_info
    resource VpsAdmin::API::Resources::DnsResolver, label: 'DNS resolver',
             desc: 'DNS resolver the VPS will use'
    resource VpsAdmin::API::Resources::Node, label: 'Node', desc: 'Node VPS will run on',
             value_label: :name
    bool :onboot, label: 'On boot', desc: 'Start VPS on node boot?',
         db_name: :vps_onboot, default: true
    bool :onstartall, label: 'On start all',
         desc: 'Start VPS on start all action?', db_name: :vps_onstartall,
         default: true
    bool :backup_enabled, label: 'Enable backups', desc: 'Toggle VPS backups',
         db_name: :vps_backup_enabled, default: true
    string :config, label: 'Config', desc: 'Custom configuration options',
           db_name: :vps_config, default: ''
  end

  params(:dataset) do
    resource VpsAdmin::API::Resources::Dataset, label: 'Dataset',
             desc: 'Dataset the VPS resides in', value_label: :name
  end

  params(:status) do
    bool :running, label: 'Running'
    integer :process_count, label: 'Process count'
    integer :used_memory, label: 'Used memory', desc: 'in MB'
    integer :used_disk, label: 'Used disk', desc: 'in MB'
  end

  params(:resources) do
    VpsAdmin::API::ClusterResources.to_params(::Vps, self, resources: %i(memory swap cpu))
  end

  params(:all) do
    use :id
    use :common
    use :dataset
    use :resources
    use :status
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List VPS'

    input do
      resource VpsAdmin::API::Resources::User, label: 'User', desc: 'Filter by owner',
               value_label: :login
      resource VpsAdmin::API::Resources::Node, label: 'Node', desc: 'Filter by node',
          value_label: :name
      resource VpsAdmin::API::Resources::Location, label: 'Location', desc: 'Filter by location'
      resource VpsAdmin::API::Resources::Environment, label: 'Environment', desc: 'Filter by environment'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      output whitelist: %i(id user hostname os_template dns_resolver node dataset
                          memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          running process_count used_memory used_disk)
      allow
    end

    example do
      request({})
      response({vpses: [
        {
            id: 150,
            user: {
                id: 1,
                name: 'somebody'
            },
            hostname: 'thehostname',
            os_template: {
                id: 1,
                label: 'Scientific Linux 6'
            },
            info: 'My very important VPS',
            dns_resolver: {
                id: 1,
            },
            node: {
                id: 1,
                name: 'node1'
            },
            onboot: true,
            onstartall: true,
            backup_enabled: true,
            vps_config: '',
        }
      ]})
    end

    def query
      q = if input[:object_state]
        Vps.unscoped.where(
            object_state: Vps.object_states[input[:object_state]]
        )

      else
        Vps.existing
      end

      q = q.where(with_restricted)
      q = q.where(m_id: input[:user].id) if input[:user]

      if input[:node]
        q = q.where(vps_server: input[:node].id)
      end

      if input[:location]
        q = q.joins(:node).where(servers: {server_location: input[:location].id})
      end

      if input[:environment]
        q = q.joins(:node).where(servers: {environment_id: input[:environment].id})
      end

      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query).includes(
          :vps_status,
          dataset_in_pool: [:dataset]
      ).limit(params[:vps][:limit]).offset(params[:vps][:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create VPS'

    input do
      resource VpsAdmin::API::Resources::Environment, label: 'Environment',
               desc: 'Environment in which to create the VPS, for non-admins'
      resource VpsAdmin::API::Resources::Location, label: 'Location',
               desc: 'Location in which to create the VPS, for non-admins'
      use :common
      VpsAdmin::API::ClusterResources.to_params(::Vps, self)
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i(environment location hostname os_template
                          dns_resolver cpu memory diskspace ipv4 ipv6)
      output whitelist: %i(id user hostname os_template dns_resolver node dataset
                          memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          running process_count used_memory used_disk)
      allow
    end

    example 'Create vps' do
      request({
        vps: {
          user: 1,
          hostname: 'my-vps',
          os_template: 1,
          info: '',
          dns_resolver: 1,
          node: 1,
          onboot: true,
          onstartall: true,
          backup_enabled: true,
          vps_config: ''
        }
      })
      response({
        vps: {
            id: 150
        }
      })
      comment <<END
Create VPS owned by user with ID 1, template ID 1 and DNS resolver ID 1. VPS
will be created on node ID 1. Action returns ID of newly created VPS.
END
    end

    def exec
      if current_user.role == :admin
        input[:user] ||= current_user

      else
        if input[:environment].nil? && input[:location].nil?
          error('provide either an environment, a location or both')
        end

        if input[:environment]
          node = ::Node.pick_by_env(input[:environment], input[:location])

        else
          node = ::Node.pick_by_location(input[:location])
        end

        input.delete(:location)
        input.delete(:environment)

        unless node
          error('no free node is available in selected environment/location')
        end

        env = node.environment

        if !current_user.env_config(env, :can_create_vps)
          error('insufficient permission to create a VPS in this environment')

        elsif current_user.vps_in_env(env) >= current_user.env_config(env, :max_vps_count)
          error('cannot create more VPSes in this environment')
        end

        input.update({
            user: current_user,
            node: node
        })
      end

      maintenance_check!(input[:node])

      vps = ::Vps.new(to_db_names(input))
      vps.set_cluster_resources(input)

      if vps.create(current_user.role == :admin)
        ok(vps)

      else
        error('save failed', to_param_names(vps.errors.to_hash, :input))
      end
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show VPS properties'

    output do
      use :all
    end

    # example do
    #   request({})
    #   response({})
    #   comment ''
    # end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      output whitelist: %i(id user hostname os_template dns_resolver node dataset
                          memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          running process_count used_memory used_disk)
      allow
    end

    def prepare
      @vps = with_includes(::Vps.including_deleted).find_by!(with_restricted(
          vps_id: params[:vps_id])
      )
    end

    def exec
      @vps
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update VPS'

    input do
      use :common
      patch :hostname, required: false
      VpsAdmin::API::ClusterResources.to_params(::Vps, self, resources: %i(cpu memory swap))
      string :change_reason, label: 'Change reason',
             desc: 'If filled, it is send to VPS owner in an email'
      bool :admin_override, label: 'Admin override',
           desc: 'Make it possible to assign more resource than the user actually has'
      string :admin_lock_type, label: 'Admin lock type', choices: %i(no_lock absolute not_less not_more),
          desc: 'How is the admin lock enforced'
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      input whitelist: %i(hostname os_template dns_resolver cpu memory swap)
      allow
    end

    def exec
      vps = ::Vps.including_deleted.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      if input.empty?
        error('provide at least one attribute to update')
      end

      update_object_state!(vps) if change_object_state?

      if input[:user]
        resources = ::Vps.cluster_resources[:required] + ::Vps.cluster_resources[:optional]

        resources.each do |r|
          if input.has_key?(r)
            error('resources cannot be changed when changing VPS owner')
          end
        end
      end

      vps.update(to_db_names(input))

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record == vps ? to_param_names(vps.errors.to_hash, :input) : e.record.errors.to_hash)
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete VPS'

    input do
      bool :lazy, label: 'Lazy delete', desc: 'Only mark VPS as deleted',
           default: true
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      input whitelist: []
      allow
    end

    def exec
      vps = ::Vps.including_deleted.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      # FIXME: check if object_state is filled for non-admins

      update_object_state!(vps)
    end
  end

  class Start < HaveAPI::Action
    desc 'Start VPS'
    route ':%{resource}_id/start'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)
      vps.start
      ok
    end
  end

  class Restart < HaveAPI::Action
    desc 'Restart VPS'
    route ':%{resource}_id/restart'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      vps.restart
      ok
    end
  end

  class Stop < HaveAPI::Action
    desc 'Stop VPS'
    route ':%{resource}_id/stop'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      vps.stop
      ok
    end
  end

  class Passwd < HaveAPI::Action
    desc 'Set root password'
    route ':%{resource}_id/passwd'
    http_method :post

    output(:hash) do
      string :password, label: 'Password', desc: 'Auto-generated password'
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      {password: vps.passwd}
    end
  end

  class Reinstall < HaveAPI::Action
    desc 'Reinstall VPS'
    route ':%{resource}_id/reinstall'
    http_method :post

    input do
      use :template
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      tpl = input[:os_template] || vps.os_template

      error('selected os template is disabled') unless tpl.enabled?

      vps.reinstall(tpl)
    end
  end

  class Migrate < HaveAPI::Action
    desc 'Migrate VPS to another node'
    route ':%{resource}_id/migrate'
    http_method :post

    input do
      resource VpsAdmin::API::Resources::Node, label: 'Node', value_label: :name,
               required: true
      bool :replace_ip_addresses, label: 'Replace IP addresses',
          desc: 'When migrating to another location, current IP addresses are replaced by addresses from the new location'
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      vps = ::Vps.includes(dataset_in_pool: [:dataset]).find(params[:vps_id])

      if vps.node == input[:node]
        error('the VPS already is on this very node')

      elsif input[:node].server_type != 'node'
        error('target node is not a hypervisor')
      end

      vps.migrate(input[:node], input[:replace_ip_addresses])
      ok
    end
  end

  class Clone < HaveAPI::Action
    desc 'Clone VPS'
    route ':%{resource}_id/clone'
    http_method :post

    input do
      resource VpsAdmin::API::Resources::Environment, desc: 'Clone to environment'
      resource VpsAdmin::API::Resources::Location, desc: 'Clone to location'
      resource VpsAdmin::API::Resources::Node, desc: 'Clone to node', value_label: :name
      resource VpsAdmin::API::Resources::User, desc: 'The owner of the cloned VPS', value_label: :login
      resource VpsAdmin::API::Resources::VPS, desc: 'Clone into an existing VPS', value_label: :hostname
      bool :subdatasets, default: true, fill: true
      bool :dataset_plans, default: true, fill: true
      bool :configs, default: true, fill: true
      bool :resources, default: true, fill: true
      bool :features, default: true, fill: true
      string :hostname
      bool :stop, default: true, fill: true
      bool :keep_snapshots, default: false, fill: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.id
      input blacklist: %i(node user configs)
      output whitelist: %i(id hostname os_template dns_resolver node dataset
                          memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason)
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      if current_user.role == :admin
        input[:user] ||= current_user

      else
        input[:user] = current_user
      end

      error('cannot clone into itself') if input[:vps] == vps

      if input[:vps]
        node = input[:vps].node

        if current_user.role != :admin && vps.user != input[:vps].user
          error('insufficient permission to clone into this VPS')
        end

      elsif input[:node]
        node = input[:node]

      else
        if input[:environment].nil?
          error('specify environment with location, node or vps')
        end

        node = ::Node.pick_by_env(input[:environment], input[:location])
      end

      if current_user.role != :admin && !current_user.env_config(node.environment, :can_create_vps)
        error('insufficient permission to create a VPS in this environment')
      end

      input[:hostname] ||= "#{vps.hostname}-#{vps.id}-clone"

      vps.clone(node, input)
    end
  end

  include VpsAdmin::API::Maintainable::Action
  include VpsAdmin::API::Lifetimes::Resource

  class Config < HaveAPI::Resource
    version 1
    route ':vps_id/configs'
    desc 'Manage VPS configs'
    model ::VpsHasConfig

    params(:all) do
      resource VpsAdmin::API::Resources::VpsConfig, label: 'VPS config'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS configs'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.m_id
        allow
      end

      def query
        @vps ||= ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))

        ::VpsHasConfig.where(vps: @vps)
      end

      def count
        query.count
      end

      def exec
        query.order('`order`').limit(input[:limit]).offset(input[:offset])
      end
    end

    class Replace < HaveAPI::Actions::Default::Update
      desc 'Replace VPS configs'
      route 'replace'
      http_method :post

      input(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        vps = ::Vps.find(params[:vps_id])
        maintenance_check!(vps)

        vps.applyconfig(input.map { |cfg| cfg[:vps_config].id })
      end
    end
  end

  class Feature < HaveAPI::Resource
    version 1
    model ::VpsFeature
    route ':vps_id/features'
    desc 'Toggle VPS features'

    params(:toggle) do
      bool :enabled
    end

    params(:common) do
      string :name
      string :label
      use :toggle
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS features'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def query
        ::Vps.find_by!(with_restricted(vps_id: params[:vps_id])).vps_features
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show VPS feature'
      resolve ->(f){ [f.vps_id, f.id] }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def prepare
        @feature = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        ).vps_features.find(params[:feature_id])
      end

      def exec
        @feature
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Toggle VPS feature'

      input do
        use :toggle
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        )
        vps.set_feature(vps.vps_features.find(params[:feature_id]), input[:enabled])
      end
    end

    class UpdateAll < HaveAPI::Action
      desc 'Set all features at once'
      http_method :post
      route 'update_all'

      input do
        ::VpsFeature::FEATURES.each do |name, label|
          bool name, label: label
        end
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        )
        vps.set_features(input)
      end
    end
  end

  class IpAddress < HaveAPI::Resource
    version 1
    model ::IpAddress
    route ':vps_id/ip_addresses'
    desc 'Manage VPS IP addresses'

    params(:common) do
      id :id, label: 'IP address ID', db_name: :ip_id
      string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
      integer :version, label: 'IP version', desc: '4 or 6', db_name: :ip_v
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS IP addresses'

      input do
        integer :version, label: 'IP version', desc: '4 or 6', db_name: :ip_v
      end

      output(:object_list) do
        use :common
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.m_id
        allow
      end

      def exec
        ips = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        ).ip_addresses

        if input[:version]
          ips = ips.where(
              ip_v: input[:version]
          )
        end

        ips.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Assign IP address to VPS'

      input do
        resource VpsAdmin::API::Resources::IpAddress, label: 'IP address',
            desc: 'If the address is not provided, first free IP address of given version is assigned instead'
        integer :version, label: 'IP version',
                desc: 'provide only if IP address is not selected', db_name: :ip_v,
                choices: [4, 6]
      end

      output do
        use :common
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        if input[:ip_address]
          begin
            vps.add_ip(ip = input[:ip_address])

          rescue VpsAdmin::API::Exceptions::IpAddressInUse
            error('IP address is already in use')

          rescue VpsAdmin::API::Exceptions::IpAddressInvalidLocation
            error('IP address is from the wrong location')

          rescue VpsAdmin::API::Exceptions::IpAddressNotOwned
            error('Use an IP address you already own first')
          end

        elsif input[:version].nil?
          error('provide either an IP address or IP version')

        else
          begin
            ip = vps.add_free_ip(input[:version])

          rescue ActiveRecord::RecordNotFound
            error('no free IP address is available')
          end
        end

        ok(ip)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Free IP address'

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        vps.delete_ip(vps.ip_addresses.find_by!(
            ip_id: params[:ip_address_id],
            vps_id: vps.id)
        )
      end
    end

    class DeleteAll < HaveAPI::Action
      desc 'Free all IP addresses'
      route ''
      http_method :delete

      input(namespace: :ip_addresses) do
        integer :version, label: 'IP version',
                desc: '4 or 6, delete addresses of selected version', db_name: :ip_v
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        vps.delete_ips((params[:ip_addresses] || {})[:version])
      end
    end
  end

  class Mount < HaveAPI::Resource
    version 1
    route ':vps_id/mounts'
    model ::Mount
    desc 'Manage mounts'

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::Dataset, label: 'Dataset',
               value_label: :name
      resource VpsAdmin::API::Resources::Dataset::Snapshot, label: 'Snapshot',
               value_label: :created_at
      string :mountpoint, label: 'Mountpoint', db_name: :dst
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mounts'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vps: {m_id: u.id}
        allow
      end

      def query
        ::Mount.joins(:vps).where(with_restricted(vps_id: params[:vps_id]))
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show mount'
      resolve ->(m){ [m.vps_id, m.id] }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vps: {m_id: u.id}
        allow
      end

      def prepare
        @mount = ::Mount.joins(:vps).find_by!(with_restricted(
                                                  vps_id: params[:vps_id],
                                                  id: params[:mount_id])
        )
      end

      def exec
        @mount
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Mount remote dataset or snapshot to directory in VPS'

      input do
        resource VpsAdmin::API::Resources::Dataset, label: 'Dataset'
        resource VpsAdmin::API::Resources::Dataset::Snapshot, label: 'Snapshot'
        string :mountpoint, label: 'Mountpoint'
        string :mode, label: 'Mode', choices: %i(ro rw), default: :rw, fill: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        if !input[:dataset] && !input[:snapshot]
          error('specify either a dataset or a snapshot')
        end

        if input[:dataset]
          ds = input[:dataset]

        else
          ds = input[:snapshot].dataset
        end

        if ds.user != current_user
          error('insufficient permission to mount selected snapshot')
        end

        if input[:dataset]
          vps.mount_dataset(input[:dataset], input[:mountpoint], input[:mode])

        else
          vps.mount_snapshot(input[:snapshot], input[:mountpoint])
        end

      rescue VpsAdmin::API::Exceptions::SnapshotAlreadyMounted => e
        error(e.message)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete mount from VPS'

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        mnt = ::Mount.find_by!(vps: vps, id: params[:mount_id])
        vps.umount(mnt)

        ok
      end
    end
  end
end
