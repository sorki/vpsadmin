class VpsAdmin::API::Resources::OsTemplate < HaveAPI::Resource
  version 1
  model ::OsTemplate
  desc 'Manage OS templates'

  params(:id) do
    id :id, label: 'ID', desc: 'OS template ID', db_name: :templ_id
  end

  params(:common) do
    string :name, label: 'Name', desc: 'Template file name',
           db_name: :templ_name
    string :label, label: 'Label', desc: 'Human-friendly label',
           db_name: :templ_label
    string :info, label: 'Info', desc: 'Information about template',
           db_name: :templ_info
    bool :enabled, label: 'Enabled', desc: 'Enable/disable template usage',
         db_name: :templ_enabled
    bool :supported, label: 'Supported', desc: 'Is template known to work?',
         db_name: :templ_supported
    integer :order, label: 'Order', desc: 'Template order', db_name: :templ_order
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List OS templates'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict templ_enabled: true
      output whitelist: %i(id label info supported)
      allow
    end

    example do
      request({})
      response({
         os_templates: [{
             id: 26,
             name: 'scientific-6-x86_64',
             label: 'Scientific Linux 6',
             info: 'Some important notes',
             enabled: true,
             supported: true,
             order: 1
         }]
     })
    end

    def query
      ::OsTemplate.where(with_restricted)
    end

    def count
      query.count
    end

    def exec
      query.limit(input[:limit]).offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict templ_enabled: true
      output whitelist: %i(id label info supported)
      allow
    end

    def prepare
      @os_template = ::OsTemplate.find_by!(with_restricted(templ_id: params[:os_template_id]))
    end

    def exec
      @os_template
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    input do
      use :common
      patch :name, required: true
      patch :label, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::OsTemplate.create!(to_db_names(input))

    rescue ActiveRecord::RecordInvalid => e
      error('create failed', to_param_names(e.record.errors.to_hash))
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    input do
      use :common, exclude: %i(name)
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::OsTemplate.find(params[:os_template_id]).update!(to_db_names(input))

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', to_param_names(e.record.errors.to_hash))
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      t = ::OsTemplate.find(params[:os_template_id])

      error('The OS template is in use') if t.in_use?
      t.destroy
      ok
    end
  end
end
