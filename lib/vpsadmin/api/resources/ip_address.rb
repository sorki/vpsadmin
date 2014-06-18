class VpsAdmin::API::Resources::IpAddress < HaveAPI::Resource
  version 1
  model ::IpAddress
  desc 'Manage IP addresses'

  params(:id) do
    id :id, label: 'ID', desc: 'IP address ID', db_name: :ip_id
  end

  params(:filters) do
    resource VpsAdmin::API::Resources::VPS, label: 'VPS', desc: 'VPS this IP is assigned to, might be null',
             value_label: :hostname
    integer :version, label: 'IP version', desc: '4 or 6', db_name: :ip_v
    resource VpsAdmin::API::Resources::Location, label: 'Location',
              desc: 'Location this IP address is available in'
  end

  params(:common) do
    use :filters
    string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List IP addresses'

    input do
      use :filters
    end

    output(:list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({
        ip_addresses: {
          vps_id: 101
        }
      })
      response({
        ip_addresses: [
            {
                id: 10,
                vps: {
                    id: 101,
                    hostname: 'myvps'
                },
                version: 4,
                location: {
                    id: 1,
                    label: 'The Location'
                },
                addr: '192.168.0.50'
            }
        ]
      })
      comment 'List IP addresses assigned to VPS with ID 101.'
    end

    def exec
      ret = []

      ips = ::IpAddress

      %i(vps version location).each do |filter|
        next unless params[:ip_address][filter]

        ips = ips.where(
            filter => params[:ip_address][filter],
        )
      end

      ips.limit(params[:ip_address][:limit]).offset(params[:ip_address][:offset]).each do |ip|
        ret << to_param_names(all_attrs(ip))
      end

      ret
    end
  end
end
