module VpsAdmin
  module API
    module Resources
      class VPS < API::Resource
        version 1
        model ::Vps
        desc 'Manage VPS'

        class Index < API::Actions::Default::Index
          desc 'List VPS'

          output(:vpses) do
            list_of(:vpses, {
              vps_id: Integer,
              user_id: Integer,
              hostname: String,
              template_id: Integer,
              info: String,
              dns_resolver_id: Integer,
              node_id: Integer,
              onboot: Boolean,
              onstartall: Boolean,
              backup_enabled: Boolean,
              config: String,
            })

            foreign_key :user_id, label: 'User', desc: 'VPS owner'
            string :hostname, desc: 'VPS hostname'
            foreign_key :template_id, label: 'Template', desc: 'id of OS template'
            string :info, label: 'Info', desc: 'VPS description'
            foreign_key :dns_resolver_id, label: 'DNS resolver', desc: 'DNS resolver the VPS will use'
            integer :node_id, label: 'Node', desc: 'Node VPS will run on'
            bool :onboot, label: 'On boot', desc: 'Start VPS on node boot?'
            bool :onstartall, label: 'On start all', desc: 'Start VPS on start all action?'
            bool :backup_enabled, label: 'Enable backups', desc: 'Toggle VPS backups'
            string :config, label: 'Config', desc: 'Custom configuration options'
          end

          authorize do |u|
            allow if u.role == :admin
            restrict m_id: u.m_id
            output whitelist: %i(vps_id hostname template_id dns_resolver_id node_id backup_enabled)
            allow
          end

          def exec
            ret = []

            Vps.where(with_restricted).each do |vps|
              ret << {
                vps_id: vps.id,
                hostname: vps.hostname,
                template_id: vps.os_template.id,
                info: vps.vps_info,
                dns_resolver_id: 1,
                node_id: vps.node.id,
                onboot: vps.vps_onboot,
                onstartall: vps.vps_onstartall,
                backup_enabled: vps.vps_backup_enabled,
                config: vps.vps_config,
              }
            end

            ret
          end
        end

        class Create < API::Actions::Default::Create
          desc 'Create VPS'

          input do
            id :user_id, label: 'User', desc: 'VPS owner'
            string :hostname, desc: 'VPS hostname'
            foreign_key :template_id, label: 'Template', desc: 'id of OS template'
            string :info, label: 'Info', desc: 'VPS description'
            foreign_key :dns_resolver_id, label: 'DNS resolver', desc: 'DNS resolver the VPS will use'
            integer :node_id, label: 'Node', desc: 'Node VPS will run on'
            bool :onboot, label: 'On boot', desc: 'Start VPS on node boot?'
            bool :onstartall, label: 'On start all', desc: 'Start VPS on start all action?'
            bool :backup_enabled, label: 'Enable backups', desc: 'Toggle VPS backups'
            string :config, label: 'Config', desc: 'Custom configuration options'
          end

          output do
            object(:vps, {
              vps_id: Integer
            })

            integer :vps_id, label: 'VPS id', desc: 'ID of created VPS'
          end

          authorize do |u|
            allow if u.role == :admin
            input whitelist: %i(hostname template_id dns_resolver_id)
            allow
          end

          example do
            request({
              vps: {
                  user_id: 1,
                  hostname: 'my-vps',
                  template_id: 1,
                  info: '',
                  dns_resolver_id: 1,
                  node_id: 1,
                  onboot: true,
                  onstartall: true,
                  backup_enabled: true,
                  config: ''
              }
            })
            response({
              vps: {
                  vps_id: 150
              }
            })
            comment <<END
Create VPS owned by user with ID 1, template ID 1 and DNS resolver ID 1. VPS
will be created on node ID 1. Action returns ID of newly created VPS.
END
          end

          def exec
            puts 'Did magic'
          end
        end

        class Show < API::Actions::Default::Show
          desc 'Show VPS properties'

          output do
            object(:vps, {
              vps_id: Integer,
              hostname: String,
              distribution: Integer,
            })
          end

          # example do
          #   request({})
          #   response({})
          #   comment ''
          # end

          authorize do |u|
            allow if u.role == :admin
            restrict m_id: u.m_id
            allow
          end

          def exec
            vps = Vps.find_by!(with_restricted(vps_id: @params[:vps_id]))

            {
                vps_id: vps.vps_id,
                hostname: vps.hostname,
                distribution: 15615
            }
          end
        end

        class Update < API::Actions::Default::Update
          input do
            param :id, desc: 'VPS id'
          end

          authorize do |u|
            restrict m_id: u.m_id
            whitelist
          end
        end

        class Delete < API::Actions::Default::Delete

        end

        class IpAddress < API::Resource
          version 1
          model IpAddress
          route ':vps_id/ip_addresses'
          desc 'Manage VPS IP addresses'

          class Index < API::Actions::Default::Index

          end

          class Show < API::Actions::Default::Show

          end
        end
      end
    end
  end
end
