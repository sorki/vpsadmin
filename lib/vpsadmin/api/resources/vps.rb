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

  params(:status) do
    bool :running, label: 'Running'
    integer :process_count, label: 'Process count'
    integer :used_memory, label: 'Used memory', desc: 'in MB'
    integer :used_disk, label: 'Used disk', desc: 'in MB'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List VPS'

    input do
      resource VpsAdmin::API::Resources::User, label: 'User', desc: 'VPS owner',
               value_label: :login
    end

    output(:object_list) do
      use :id
      use :common
      use :status
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      output whitelist: %i(id hostname os_template dns_resolver node backup_enabled
                            maintenance_lock maintenance_lock_reason)
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
      q = Vps.where(with_restricted)
      q = q.where(m_id: input[:user].id) if input[:user]
      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query).includes(:vps_status).limit(params[:vps][:limit]).offset(params[:vps][:offset])
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
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i(environment location hostname os_template dns_resolver)
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
          error('provide either an environment or a location')
        end

        if input[:location]
          node = ::Node.pick_by_location(input[:location])

        else
          node = ::Node.pick_by_env(input[:environment])
        end

        input.delete(:location)
        input.delete(:environment)

        unless node
          error('no free node is available in selected environment/location')
        end

        env = node.location.environment

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
      use :id
      use :common
    end

    # example do
    #   request({})
    #   response({})
    #   comment ''
    # end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      output whitelist: %i(id hostname os_template dns_resolver node
                          backup_enabled maintenance_lock maintenance_lock_reason)
      allow
    end

    def prepare
      @vps = with_includes.find_by!(with_restricted(vps_id: params[:vps_id]))
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
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      input whitelist: %i(hostname os_template dns_resolver)
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      if vps.update(to_db_names(input))
        ok
      else
        error('update failed', to_param_names(vps.errors.to_hash, :input))
      end
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
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      vps.lazy_delete(
          current_user.role == :admin ? params[:vps][:lazy] : true
      )
      ok
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

  class Revive < HaveAPI::Action
    desc 'Revive a lazily deleted VPS'
    route ':%{resource}_id/revive'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      vps = ::Vps.unscoped.where(vps_id: params[:vps_id]).where.not(vps_deleted: nil).take!
      maintenance_check!(vps)

      vps.revive
      vps.save!
    end
  end

  include VpsAdmin::API::Maintainable::Action

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
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        vps = ::Vps.find(params[:vps_id])
        maintenance_check!(vps)

        if input[:ip_address]
          begin
            vps.add_ip(ip = input[:ip_address])

          rescue VpsAdmin::API::Exceptions::IpAddressInUse
            error('IP address is already in use')

          rescue VpsAdmin::API::Exceptions::IpAddressInvalidLocation
            error('IP address is from the wrong location')
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
      end

      def exec
        vps = ::Vps.find(params[:vps_id])
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
      end

      def exec
        vps = ::Vps.find(params[:vps_id])
        maintenance_check!(vps)

        vps.delete_ips((params[:ip_addresses] || {})[:version])
      end
    end
  end

  class Dataset < HaveAPI::Resource
    version 1
    route ':vps_id/datasets'
    model ::Dataset
    desc 'VPS datasets'

    params(:id) do
      id :id
    end

    params(:common) do
      string :name, label: 'Name', db_name: :full_name
      string :mountpoint, label: 'Mountpoint', db_name: :hypervisor_mountpoint
      resource VpsAdmin::API::Resources::VPS::Dataset, label: 'Parent',
               name: :parent, value_label: :name
    end

    params(:all) do
      use :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS datasets'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        ret = []
        vps = ::Vps.includes(dataset_in_pool: [:dataset]).find(params[:vps_id])

        ret << vps.dataset_in_pool.dataset

        ::Dataset.descendants_of(vps.dataset_in_pool.dataset).order('full_name').each do |ds|
          ret << ds
        end

        ret
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a dataset'

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
        vps.dataset_in_pool.dataset.descendants.find(params[:dataset_id])
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a subdataset'

      input do
        string :name, label: 'Name'
        string :mountpoint, label: 'Mountpoint'
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
        vps = ::Vps.includes(dataset_in_pool: [:dataset]).find(params[:vps_id])

        unless vps.dataset_in_pool.dataset.user_create
          error('insufficient permission to create a dataset')
        end

        vps.create_subdataset(
            input[:name].strip,
            input[:mountpoint]
        )
        ok

      rescue VpsAdmin::API::Exceptions::DatasetAlreadyExists => e
        error(e.message)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Destroy a dataset with all its subdatasets and snapshots'

      input do
        string :name, label: 'Name'
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.includes(dataset_in_pool: [:dataset]).find(params[:vps_id])

        # FIXME
        #unless vps.dataset_in_pool.dataset.user_destroy
        #  error('insufficient permission to destroy a dataset')
        #end

        vps.destroy_subdataset(::Dataset.find(params[:dataset_id]))
        ok

      rescue VpsAdmin::API::Exceptions::DatasetDoesNotExist => e
        error(e.message)
      end
    end
  end

  class Snapshot < HaveAPI::Resource
    version 1
    route ':vps_id/snapshots'
    model ::Snapshot
    desc 'VPS snapshots'

    params(:all) do
      id :id
      datetime :created_at # FIXME: this is not correct creation time
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List snapshots'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        Vps.includes(dataset_in_pool: [:dataset])
          .find_by!(with_restricted(vps_id: params[:vps_id]))
          .dataset_in_pool.dataset.snapshots.order('created_at')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show snapshot'
      resolve ->(s){
        [
            Vps.joins(dataset_in_pool: [dataset: [:snapshots]])
               .where(snapshots: {id: s.id}).take!.id,
            s.id
        ]
      }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        Vps.includes(dataset_in_pool: [:dataset])
          .find_by!(with_restricted(vps_id: params[:vps_id]))
          .dataset_in_pool.dataset.snapshots.find(params[:snapshot_id])
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create snapshot'

      # FIXME: return snapshot id
      # output do
      #   use :all
      # end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        vps = Vps.includes(:dataset_in_pool)
          .find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)


        vps.dataset_in_pool.snapshot
      end
    end

    class Rollback < HaveAPI::Action
      desc 'Rollback to a snapshot'
      route ':%{resource}_id/rollback'
      http_method :post

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = Vps.includes(dataset_in_pool: [:dataset])
          .find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        snap = vps.dataset_in_pool.dataset.snapshots.find(params[:snapshot_id])

        vps.restore(snap)
        ok
      end
    end
  end
end
