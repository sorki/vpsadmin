module VpsAdmin
  module API
    module Resources
      class VPS < API::Resource
        version 1
        model Vps
        desc 'Manage VPS'

        class Index < API::Actions::Default::Index
          desc 'List VPS'

          def exec
            'Howdy?'
          end
        end

        class Create < API::Actions::Default::Create
          desc 'Create VPS'

          input do
            param :hostname, desc: 'VPS hostname'
            param :distribution, desc: 'Distribution to install'
            param :one, label: 'One', desc: 'oh yes, very interesting', required: true, type: String
            param :two, label: 'Two', desc: 'not very interesting', required: false, type: Integer
          end

          output do
            structure({
              status: Boolean,
            })
          end

          def exec

          end
        end

        class Show < API::Actions::Default::Show
          desc 'Show VPS properties'

          output do
            structure({
              hostname: String,
              distribution: Integer,
            })
          end

          example do
            request({kokot: 'yes'})
            response({})
            comment 'no jasne no'
          end

          def exec
            'Well how do you like that?<br>'
            "My version is #{@version}"
          end
        end

        class Update < API::Actions::Default::Update
          input do
            param :id, desc: 'VPS id'
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
